#!/usr/bin/env python3
"""gen_hero_ref.py — все кадры мальчика по эталону владельца (раунд 4, «boy-art»).

Владелец: «Мальчик сейчас выглядит ужасно, я добавил картинку как он должен
выглядеть, найди все арты с мальчиком, убедись, что они в высоком разрешении»
и «Я добавил анимацию его ходьбы».

Источник — родная пиксельная сетка эталона и видео ходьбы, которую готовит
tools/hero_ref_extract.py (art/_source/hero_ref/: ref.png — эталон, 160
пикселей рисунка ростом; walk_01..16.png — кадры видео в той же сетке и
палитре; palette.png — 32 цвета эталона). Отсюда:

  * разрешение: 4 пикселя рисунка на логическую точку (герой 40 точек = 160
    пикселей, ровно как на эталоне), и каждый пиксель рисунка — 2×2 текселя:
    текстура ×8 от логических точек (было ×3). Телефону (×5,2) больше не
    приходится растягивать кадр — его приходится уменьшать; шейдер чёткости
    героя берёт пиксель рисунка = 2 текселя (cell 2), мипмап уровня 1 — ровно
    родная сетка эталона;
  * увеличение — только ближайшим соседом, альфа только 0/255, цвета — только
    из палитры эталона (+ рампы снаряжения и инструментов);
  * стойка и «оживление» (моргание, взгляд, постукивание ногой) — сам эталон;
    ходьба — кадры видео 13–16 и 10–12 (два шага: левой и правой; кадры 6 и
    10 у видео смазаны — 6 не берём, у 10 ноги взяты из чистого 13);
    поворот (кадр 3 видео) — переход «стоит анфас → идёт в профиль»;
  * остальные позы — кукла из частей эталона (голова, туловище, руки, ноги;
    поворот вокруг сустава ближайшим соседом по сетке рисунка), снаряжение и
    инструменты дорисованы рампами поверх (см. позы ниже).

Геометрия: имена листов и кадров прежние; кадр — прежний прямоугольник в
логических точках (idle 48×48, кирка 64×48, …), центр кадра по ширине — ось
героя, строка ground — линия земли (подошва на ней). Листы шире 4096 текселей
раскладываются в несколько рядов (лимит текстуры мобильного WebGL).
Геометрию всех листов скрипт пишет в art/character/hero_sheets.json — её
читают CharacterView, сюжетные актёры, дом и экран героя (HeroSheets).

Запуск:  python3 tools/gen_hero_ref.py            — все листы
         python3 tools/gen_hero_ref.py idle walk  — только эти
         python3 tools/gen_hero_ref.py --sheet OUT.png — лист «эталон/было/стало»
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_puppet as hp  # noqa: E402
import hero_tools as ht  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF_DIR = os.path.join(ROOT, "art", "_source", "hero_ref")
OUT_DIR = os.path.join(ROOT, "art", "character")
META = os.path.join(OUT_DIR, "hero_sheets.json")

PX = 4          # пикселей рисунка на логическую точку
CELL = 2        # текселей на пиксель рисунка
SCALE = PX * CELL
MAX_TEX = 4096  # лимит стороны текстуры мобильного WebGL


def load(name):
    return np.asarray(Image.open(os.path.join(REF_DIR, name)).convert("RGBA")).copy()


PALETTE = load("palette.png")[0, :, :3].astype(int)


def bbox(img):
    ys, xs = np.nonzero(img[..., 3])
    return xs.min(), ys.min(), xs.max(), ys.max()


def head_x(img):
    ys, xs = np.nonzero(img[..., 3])
    top = ys.min()
    return float(xs[ys < top + 16].mean())


# ---------------------------------------------------------------------------
# Холст кадра: размеры в логических точках, работа — в пикселях рисунка
# ---------------------------------------------------------------------------

class Frame:
    def __init__(self, w_u, h_u, ground_u):
        self.w = int(round(w_u * PX))
        self.h = int(round(h_u * PX))
        self.ground = int(round(ground_u * PX))
        self.img = np.zeros((self.h, self.w, 4), np.uint8)

    @property
    def axis(self):
        return self.w // 2

    def paste(self, src, dx, dy):
        """Наложить src (RGBA, альфа 0/255) со сдвигом: src[y, x] -> (y+dy, x+dx)."""
        h, w = src.shape[:2]
        x0, y0 = max(0, dx), max(0, dy)
        x1, y1 = min(self.w, dx + w), min(self.h, dy + h)
        if x1 <= x0 or y1 <= y0:
            return
        s = src[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
        m = s[..., 3] > 0
        self.img[y0:y1, x0:x1][m] = s[m]


# Ось героя на эталоне: середина между ступнями. Голова чуть правее оси
# (смотрит вправо) — все остальные позы выравниваются по ней же.
REF = load("ref.png")
REF_X0, REF_Y0, REF_X1, REF_Y1 = bbox(REF)
REF_AXIS = 78.5
REF_HEAD_DX = head_x(REF) - REF_AXIS


def place_feet(frame, img, axis_x, bottom=None):
    """Положить рисунок img так, чтобы его ось axis_x пришлась на ось кадра,
    а нижний пиксель (или bottom) — на строку над линией земли."""
    b = bbox(img)[3] if bottom is None else bottom
    frame.paste(img, int(round(frame.axis - axis_x)), frame.ground - 1 - b)


# ---------------------------------------------------------------------------
# Стойка и её «оживление» — сам эталон
# ---------------------------------------------------------------------------

# Части эталона (координаты родной сетки ref.png): талия — нижняя строка
# футболки, кисти — ниже талии, но едут вместе с корпусом.
WAIST = 155
HANDS = [(46, 150, 64, 168), (92, 150, 106, 168)]
EYES = [(77, 77, 87, 84), (91, 77, 99, 84)]
SKIN_EYE = None


def _upper_mask(img):
    h, w = img.shape[:2]
    m = np.zeros((h, w), bool)
    m[:WAIST + 1] = True
    for x0, y0, x1, y1 in HANDS:
        m[y0:y1 + 1, x0:x1 + 1] = True
    return m & (img[..., 3] > 0)


def breathe(img, dy):
    """Вдох: корпус с головой и руками выше на dy, талия растягивается."""
    if dy == 0:
        return img.copy()
    up = _upper_mask(img)
    out = img.copy()
    out[up] = 0
    moved = np.zeros_like(img)
    moved[:-dy][up[dy:]] = img[dy:][up[dy:]]
    # строки талии, которые освободились, — копия нижней строки футболки
    for k in range(dy):
        row = WAIST - k
        src = img[WAIST]
        cols = (src[:, 3] > 0) & ~np.isin(np.arange(img.shape[1]), [])
        out[row][cols] = src[cols]
    m = moved[..., 3] > 0
    out[m] = moved[m]
    return out


def blink(img):
    """Глаза закрыты: веко цвета кожи с тенью сверху, ресницы — дуга «︶»."""
    out = img.copy()
    skin = img[86, 85].copy()
    shadow = img[77, 80].copy()
    lash = img[79, 81].copy()
    for x0, x1 in ((78, 86), (92, 98)):
        out[78:80, x0:x1 + 1] = shadow
        out[80:84, x0:x1 + 1] = skin
        out[80, x0] = lash
        out[80, x1] = lash
        out[81, x0 + 1:x1] = lash
    return out


def look(img, dx):
    """Взгляд в сторону: радужка и зрачок (строки 80–83) сдвинуты на dx, на
    старом месте — белок."""
    out = img.copy()
    for x0, y0, x1, y1 in EYES:
        reg = img[80:84, x0 + 1:x1].copy()
        lum = reg[..., :3].astype(int).sum(-1)
        dark = (lum < 300) & (reg[..., 3] > 0)
        white = lum > 560
        if not white.any() or not dark.any():
            continue
        newreg = reg.copy()
        newreg[dark] = reg[white][0]
        sh = np.zeros_like(dark)
        src = np.zeros_like(reg)
        if dx > 0:
            sh[:, dx:] = dark[:, :-dx]
            src[:, dx:] = reg[:, :-dx]
        else:
            sh[:, :dx] = dark[:, -dx:]
            src[:, :dx] = reg[:, -dx:]
        sh &= (white | dark)
        newreg[sh] = src[sh]
        out[80:84, x0 + 1:x1] = newreg
    return out


def toe_up(img, lift):
    """Носок правой (дальней от зрителя) ноги приподнят: постукивание."""
    out = img.copy()
    x0, y0, x1, y1 = 84, 196, 104, 212
    reg = img[y0:y1 + 1, x0:x1 + 1].copy()
    out[y0:y1 + 1, x0:x1 + 1] = 0
    for x in range(x1 - x0 + 1):
        d = int(round(lift * max(0, x - 6) / (x1 - x0 - 6)))
        col = reg[:, x]
        dst = np.zeros_like(col)
        if d:
            dst[:-d] = col[d:]
        else:
            dst = col
        m = dst[:, 3] > 0
        out[y0:y1 + 1, x0 + x][m] = dst[m]
    return out


def base_ref():
    """Эталон в текущей одежде (обычной или экспедиционной)."""
    return gear_dress(REF) if STYLE["gear"] else REF


def frames_idle():
    out = []
    for dy in (0, 1, 1, 2):
        f = Frame(48, 48, 46)
        place_feet(f, breathe(base_ref(), dy), REF_AXIS, bottom=REF_Y1)
        out.append(f)
    return out


def frames_idle_x():
    b = base_ref()
    poses = [blink(b), look(b, -1), look(b, 1), toe_up(b, 3), b]
    out = []
    for p in poses:
        f = Frame(48, 48, 46)
        place_feet(f, p, REF_AXIS, bottom=REF_Y1)
        out.append(f)
    return out


# ---------------------------------------------------------------------------
# Ходьба и поворот — кадры видео владельца
# ---------------------------------------------------------------------------

def vid(i):
    return load("walk_%02d.png" % i)


def legs_from(dst, src, top):
    """Ноги кадра dst (ниже строки top) заменить ногами src (смаз у видео)."""
    out = dst.copy()
    out[top:] = 0
    m = src[top:, :, 3] > 0
    out[top:][m] = src[top:][m]
    return out


# Порядок ленты: 16 кадров = 4 шага по 4 кадра, проходная поза — 0/4/8/12
# (HeroAnim.frames_to_passing). Шаг «левой» — кадры видео 13–16, шаг
# «правой» — 10–12 и 12 ещё раз (у видео этот шаг короче на кадр).
WALK_ORDER = [13, 14, 15, 16, 10, 11, 12, 12]


def frames_walk():
    out = []
    for i in WALK_ORDER * 2:
        img = vid(i)
        if i == 10:
            img = legs_from(img, vid(13), 168)
        f = Frame(48, 48, 46)
        hx = head_x(img)
        place_feet(f, img, hx - REF_HEAD_DX)
        out.append(f)
    return out


def frames_turn():
    """Поворот: 0 — анфас (кадр 2 видео), 1 — вполоборота (кадр 3)."""
    out = []
    for i in (2, 3):
        img = vid(i)
        f = Frame(48, 48, 46)
        place_feet(f, img, head_x(img) - REF_HEAD_DX)
        out.append(f)
    return out


# ---------------------------------------------------------------------------
# Кукла: прыжок, падение, «ой», сон
# ---------------------------------------------------------------------------

_PARTS = {}
STYLE = {"gear": False}   # экспедиционная форма (boy_gear) — тот же мальчик в другой одежде


def parts(closed=False):
    """Части эталона (closed — с закрытыми глазами; в форме — если STYLE["gear"])."""
    key = (closed, STYLE["gear"])
    if key not in _PARTS:
        img = blink(REF) if closed else REF
        _PARTS[key] = hp.Parts(gear_dress(img) if STYLE["gear"] else img)
    return _PARTS[key]


def outline_fix(img):
    """Край силуэта — тёмный контур, как у эталона: после поворота частей
    светлый пиксель иногда оказывается снаружи (кожа прямо на фоне)."""
    a = img[..., 3] > 0
    edge = a & hp.neighbors4(~a)
    lum = hp._lum(img[..., :3].astype(float))
    fix = edge & (lum > 95)
    img[fix] = parts().outline
    return img


MARGIN = 70   # поле вокруг эталона под инструмент и снаряжение


def pose_frame(pose, w_u=48, h_u=48, ground_u=46, closed=False, back=None, mid=None, front=None,
               after=None, feet_on_ground=True, align_head=False):
    """Поза куклы в кадре: подошва (по самому мальчику, без инструмента) — на
    линии земли, ось эталона — на оси кадра. after(img, joints) — поверх
    готового рисунка (комья, пыль: у них свой контур)."""
    shape = (REF.shape[0] + 2 * MARGIN, REF.shape[1] + 2 * MARGIN)
    off = (MARGIN, MARGIN)
    boy, _ = hp.render(parts(closed), pose, shape=shape, offset=off)
    bottom = bbox(boy)[3]
    img, joints = hp.render(parts(closed), pose, shape=shape, offset=off,
                            extra_back=back, extra_mid=mid, extra_front=front)
    img = outline_fix(img)
    if after:
        after(img, joints)
    f = Frame(w_u, h_u, ground_u)
    LAST["bottom"] = bottom if feet_on_ground else bbox(img)[3]
    # Позы в воздухе и «ой» сводятся по голове (как ходьба): наклон корпуса
    # не должен уводить голову с оси, её и так водит слой движения.
    axis = head_x(boy) - REF_HEAD_DX if align_head else REF_AXIS + MARGIN
    place_feet(f, img, axis, bottom=LAST["bottom"])
    return f


LAST = {}
EXTRA = {}   # дополнительные поля геометрии листа (сопло джетпака и т. п.)


def sole_units(x, y):
    """Точка холста куклы → логические точки от подошвы на оси (герой вправо)."""
    return [round((x - (REF_AXIS + MARGIN)) / PX, 2), round((y - (LAST["bottom"] + 1)) / PX, 2)]


# Поза: (рука ближняя, рука дальняя, нога ближняя, нога дальняя, наклон, сдвиг корпуса).
# Углы — от «вниз», плюс — к лицу мальчика (вправо); ближняя рука — левая на рисунке.
JUMP_POSES = {
    "crouch": dict(arm_n=(-35, -15), arm_f=(-25, -5), leg_n=(-28, 12), leg_f=(22, -8), lean=10, head_tilt=-4),
    "launch": dict(arm_n=(-165, -175), arm_f=(155, 170), leg_n=(-4, 6), leg_f=(6, 14), lean=-3),
    "rise": dict(arm_n=(-150, -165), arm_f=(150, 165), leg_n=(-12, 18), leg_f=(10, 30)),
    "apex": dict(arm_n=(-95, -105), arm_f=(95, 110), leg_n=(-14, 12), leg_f=(16, 34)),
    "fall": dict(arm_n=(-125, -140), arm_f=(125, 145), leg_n=(-16, -2), leg_f=(16, 6)),
    "fall_fast": dict(arm_n=(-160, -172), arm_f=(160, 172), leg_n=(-6, -4), leg_f=(7, 5), head_tilt=-6),
    "recover": dict(arm_n=(30, 45), arm_f=(25, 45), leg_n=(-18, 6), leg_f=(16, -6), lean=8),
    "apex_b": dict(arm_n=(-112, -125), arm_f=(110, 128), leg_n=(-8, 22), leg_f=(12, 18)),
    "rise_lo": dict(arm_n=(-60, -72), arm_f=(60, 78), leg_n=(-8, 12), leg_f=(8, 22)),
}
JUMP_ORDER = ["crouch", "launch", "rise", "apex", "fall", "fall_fast", "recover", "apex_b", "rise_lo"]


def frames_jump():
    return [pose_frame(hp.Pose(**JUMP_POSES[k]), align_head=True) for k in JUMP_ORDER]


def frames_fall():
    poses = [
        dict(arm_n=(-120, -150), arm_f=(120, 140), leg_n=(-14, 2), leg_f=(14, 10)),
        dict(arm_n=(-145, -170), arm_f=(140, 165), leg_n=(-10, 10), leg_f=(18, 4)),
        dict(arm_n=(-110, -130), arm_f=(130, 152), leg_n=(-18, -4), leg_f=(10, 16)),
        dict(arm_n=(-150, -160), arm_f=(115, 135), leg_n=(-12, 8), leg_f=(16, 2)),
    ]
    return [pose_frame(hp.Pose(head_tilt=-4, **p), align_head=True) for p in poses]


def frames_hurt():
    flinch = hp.Pose(arm_n=(-45, -30), arm_f=(50, 70), lean=-9, head_tilt=-8, leg_n=(-8, 4), leg_f=(10, 2))
    ko = hp.Pose(arm_n=(-22, -12), arm_f=(28, 16), lean=-14, head_tilt=-16, leg_n=(-12, 10), leg_f=(14, -4))
    return [pose_frame(flinch, closed=True, align_head=True), pose_frame(ko, closed=True, align_head=True)]


def frames_sleep():
    """Спит на земле: та же стойка с закрытыми глазами, повёрнутая головой влево."""
    img, _ = hp.render(parts(True), hp.Pose(arm_n=(-6, 4), arm_f=(6, -4)))
    lying = hp.rotate(img, -90.0, (REF_AXIS, 132.0), (100.0, 150.0), (240, 200))
    f = Frame(48, 48, 46)
    x0, y0, x1, y1 = bbox(lying)
    place_feet(f, lying, (x0 + x1) / 2.0)
    return [f]


# ---------------------------------------------------------------------------
# Копка: кирка, ржавая кирка, лопата, ручной бур
# ---------------------------------------------------------------------------

GROUND_REF = REF_Y1 + 1   # строка земли на эталоне (под подошвой)


def _tool_cb(sprite, pivot, angle, grip):
    def cb(canvas, joints):
        ox, oy = joints["offset"]
        ht.place(canvas, sprite, pivot, angle, (grip[0] + ox, grip[1] + oy))
    return cb


# Кадр копки киркой: (точка хвата ближней руки на эталоне, угол рукояти от
# «вверх» по часовой, слой инструмента, наклон корпуса, ноги, комья).
# Порядок — как у авторского листа: замах (0–2), удар с дугой (3), упор в
# породу (4, держится дольше), подъём на плечо (5), «готов» (6–7).
PICK_FRAMES = [
    dict(grip=(46, 72), ang=-48, layer="back", lean=-6, legs=((-8, 2), (9, 0))),
    dict(grip=(54, 66), ang=-8, layer="back", lean=-8, legs=((-8, 2), (9, 0))),
    dict(grip=(110, 98), ang=50, layer="mid", lean=3, legs=((-9, 2), (10, 0))),
    dict(grip=(108, 148), ang=128, layer="mid", lean=13, legs=((-13, 6), (14, -3)), hit=True),
    dict(grip=(108, 156), ang=146, layer="mid", lean=15, legs=((-13, 6), (14, -3)), hit=True),
    dict(grip=(100, 128), ang=-30, layer="back", lean=3, legs=((-10, 3), (10, 0))),
    dict(grip=(100, 142), ang=-112, layer="mid", lean=0, legs=((-8, 2), (9, 0))),
    dict(grip=(98, 136), ang=-96, layer="mid", lean=-2, legs=((-8, 2), (9, 0))),
]


def frames_pick(metal="steel", cracked=False):
    sprite = ht.pickaxe(metal, cracked)
    out = []
    for i, fr in enumerate(PICK_FRAMES):
        g = fr["grip"]
        far = ht.along(g, fr["ang"], 11)
        cb = _tool_cb(sprite, ht.PICK_GRIP, fr["ang"], g)
        pose = hp.Pose(grip_n=g, grip_f=far, lean=fr["lean"], leg_n=fr["legs"][0], leg_f=fr["legs"][1],
                       bend_n=-1, bend_f=-1)
        after = None
        if fr.get("hit"):
            def after(img, joints, i=i):
                ox, oy = joints["offset"]
                ht.pebbles(img, 138 + ox, GROUND_REF + oy - 2, 7, seed=i, spread=12, rise=14 if i == 3 else 6)
        kw = {fr["layer"]: cb}
        out.append(pose_frame(pose, 64, 48, 46, after=after, **kw))
    return out


# Лопата: (хват ближней руки, угол черенка, наклон, ноги, земля на лотке/горка/бросок).
SHOVEL_FRAMES = [
    dict(grip=(108, 166), ang=2, lean=2, legs=((-8, 2), (9, 0))),
    dict(grip=(110, 170), ang=12, lean=9, legs=((-11, 4), (12, -2))),
    dict(grip=(112, 175), ang=18, lean=13, legs=((-13, 6), (14, -3))),
    dict(grip=(113, 178), ang=26, lean=15, legs=((-13, 6), (14, -3)), heap=True),
    dict(grip=(100, 152), ang=-72, lean=8, legs=((-10, 3), (11, -1)), load=True),
    dict(grip=(98, 136), ang=-52, lean=0, legs=((-8, 2), (9, 0)), load=True),
    dict(grip=(98, 128), ang=-22, lean=-5, legs=((-8, 2), (9, 0)), throw=True),
    dict(grip=(106, 162), ang=0, lean=0, legs=((-8, 2), (9, 0))),
]


def frames_shovel():
    sprite = ht.shovel()
    out = []
    for i, fr in enumerate(SHOVEL_FRAMES):
        g = fr["grip"]
        top = ht.along(g, fr["ang"], ht.SHOVEL_GRIP[1] - ht.SHOVEL_TOP[1])
        cb = _tool_cb(sprite, ht.SHOVEL_GRIP, fr["ang"], g)
        pose = hp.Pose(grip_n=g, grip_f=top, lean=fr["lean"], leg_n=fr["legs"][0], leg_f=fr["legs"][1],
                       bend_n=-1, bend_f=-1)

        def after(img, joints, fr=fr, g=g, i=i):
            ox, oy = joints["offset"]
            blade = ht.along(g, fr["ang"], -(78 - ht.SHOVEL_GRIP[1] - 8))
            if fr.get("heap"):
                ht.heap(img, 132 + ox, GROUND_REF + oy - 1, 22, 7)
            if fr.get("load"):
                ht.heap(img, blade[0] + ox, blade[1] + oy - 2, 12, 4)
            if fr.get("throw"):
                ht.pebbles(img, 142 + ox, 120 + oy, 9, seed=40 + i, spread=10, rise=16)
        out.append(pose_frame(pose, 64, 48, 46, mid=cb, after=after))
    return out


def frames_drill(side):
    """Ручной бур: вниз — держит перед собой сверлом в землю; вбок — у пояса,
    сверлом вправо. 8 кадров — оборот винта, вибрация и крошка."""
    out = []
    for i in range(8):
        sprite = ht.drill(i)
        shake = (0, 1, 0, -1, 0, 1, 0, -1)[i]
        if side:
            ang = 90 + shake * 1.5
            center = (112, 150 + shake)
            gn = ht.along(center, ang - 90, 0)
            pivot = (20.0, 16.0)
            gn = (center[0] - 12, center[1] + 1)
            gf = (center[0] - 12, center[1] - 9)
            pose = hp.Pose(grip_n=gn, grip_f=gf, lean=4, leg_n=(-12, 4), leg_f=(13, -2), bend_n=1, bend_f=-1)
            cb = _tool_cb(sprite, pivot, ang, center)

            def after(img, joints, i=i):
                ox, oy = joints["offset"]
                ht.pebbles(img, 154 + ox, 150 + oy + 6, 3 + i % 3, seed=60 + i, spread=5, rise=12,
                           ramp=ht.RAMPS["dirt"])
            out.append(pose_frame(pose, 48, 48, 46, front=cb, after=after))
        else:
            center = (80, 168 + shake)
            pivot = (20.0, 16.0)
            gn = (center[0] - 14, center[1])
            gf = (center[0] + 14, center[1])
            pose = hp.Pose(grip_n=gn, grip_f=gf, lean=10, leg_n=(-16, 8), leg_f=(16, -6), body_dy=2,
                           bend_n=1, bend_f=-1, far_arm_front=True)
            cb = _tool_cb(sprite, pivot, 0, center)

            def after(img, joints, i=i):
                ox, oy = joints["offset"]
                ht.pebbles(img, 80 + ox, GROUND_REF + oy - 1, 3 + i % 3, seed=80 + i, spread=11, rise=6)
            out.append(pose_frame(pose, 48, 48, 46, front=cb, after=after))
    return out


# ---------------------------------------------------------------------------
# Полёт: ранец с винтом, большой винт, джетпак, ракета
# ---------------------------------------------------------------------------

# Висит на лямках: руки держат лямки у груди, ноги свисают, колени чуть назад.
HANG = dict(grip_n=(66, 128), grip_f=(94, 126), bend_n=1, bend_f=-1, leg_n=(4, -10), leg_f=(10, -4))


def _pack(canvas, ox, oy, ramp="canvas"):
    """Ранец на спине (слева от туловища — мальчик смотрит вправо)."""
    cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
    ht.blob(cv, 52 + ox, 128 + oy, 13, 19, ht.RAMPS[ramp])
    ht.capsule(cv, (44 + ox, 116 + oy), (60 + ox, 116 + oy), 2.0, ht.RAMPS["olive"])
    ht.outline(cv.img, ht.RAMPS[ramp][0])
    hp.over(canvas, cv.img)


def _rotor(canvas, cx, cy, span, phase, spinning, big):
    """Винт: мачта до ступицы, лопасти. На ходу — диск-«размах» вместо лопастей."""
    cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
    if spinning:
        ht.blob(cv, cx, cy, span, 2.4 if not big else 4.0, ht.RAMPS["dark_steel"])
        # светлые «спицы» размаха
        for k in range(3):
            a = math.radians(phase * 40 + k * 60)
            x = cx + math.cos(a) * span * 0.8
            ht.capsule(cv, (cx, cy), (x, cy + math.sin(a) * (1.5 if not big else 3)), 0.8, ht.RAMPS["steel"])
    else:
        for k in range(2 if not big else 4):
            a = math.radians(phase * 34 + k * (180 if not big else 90))
            x = cx + math.cos(a) * span
            y = cy + math.sin(a) * (2.0 if not big else 5.0)
            ht.capsule(cv, (cx, cy), (x, y), 1.6, ht.RAMPS["steel"])
    ht.capsule(cv, (cx, cy - 1), (cx, cy + 1), 2.4, ht.RAMPS["red"])
    ht.outline(cv.img, ht.RAMPS["steel"][0])
    hp.over(canvas, cv.img)


def frames_fly_prop(big):
    out = []
    span = 46 if big else 28
    mast_top = 26 if big else 34
    for i in range(6):
        spinning = i >= 3

        def back(canvas, joints, i=i, spinning=spinning):
            ox, oy = joints["offset"]
            mast = ht.Canvas(canvas.shape[1], canvas.shape[0])
            ht.capsule(mast, (50 + ox, 112 + oy), (64 + ox, mast_top + oy), 1.4, ht.RAMPS["dark_steel"])
            ht.outline(mast.img, ht.RAMPS["steel"][0])
            hp.over(canvas, mast.img)
            _pack(canvas, ox, oy)
            _rotor(canvas, 64 + ox, mast_top + oy, span, i, spinning, big)

        def mid(canvas, joints):
            _straps(canvas, joints)
        w, h, g = (68, 56, 54) if big else (52, 54, 52)
        out.append(pose_frame(hp.Pose(**HANG), w, h, g, back=back, mid=mid))
    return out


def _straps(canvas, joints, ramp="olive"):
    """Лямки ранца поверх футболки — за них он и держится."""
    ox, oy = joints["offset"]
    cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
    ht.capsule(cv, (60 + ox, 108 + oy), (66 + ox, 136 + oy), 1.3, ht.RAMPS[ramp])
    ht.capsule(cv, (91 + ox, 108 + oy), (93 + ox, 134 + oy), 1.3, ht.RAMPS[ramp])
    ht.outline(cv.img, ht.RAMPS[ramp][0])
    hp.over(canvas, cv.img)


def _flame(canvas, x, y, length, width, ramp="flame", ang=0.0):
    """Факел вниз (ang — отклонение по часовой): конус из тонов пламени, без контура
    у кончика — свет сам по себе."""
    cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
    a = math.radians(ang)
    tip = (x - math.sin(a) * length, y + math.cos(a) * length)
    for k, (r, t) in enumerate(((width, 1), (width * 0.66, 2), (width * 0.4, 3), (width * 0.2, 4))):
        l = length * (1.0 - k * 0.2)
        tp = (x - math.sin(a) * l, y + math.cos(a) * l)
        steps = 10
        for j in range(steps + 1):
            u = j / steps
            px = x + (tp[0] - x) * u
            py = y + (tp[1] - y) * u
            rr = r * (1.0 - u) + 0.6
            body = ht.capsule(ht.Canvas(1, 1), (0, 0), (0, 0), 0.1, ht.RAMPS[ramp]) if False else None
            yy0, yy1 = int(py - rr - 1), int(py + rr + 2)
            xx0, xx1 = int(px - rr - 1), int(px + rr + 2)
            for yy in range(max(0, yy0), min(cv.img.shape[0], yy1)):
                for xx in range(max(0, xx0), min(cv.img.shape[1], xx1)):
                    if (xx + 0.5 - px) ** 2 + (yy + 0.5 - py) ** 2 <= rr * rr:
                        cv.img[yy, xx] = ht.RAMPS[ramp][t]
    hp.over(canvas, cv.img)
    return tip


def _tanks(canvas, ox, oy):
    cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
    for dx in (0, 11):
        ht.capsule(cv, (44 + dx + ox, 106 + oy), (44 + dx + ox, 140 + oy), 5.2, ht.RAMPS["steel"])
        ht.capsule(cv, (44 + dx + ox, 141 + oy), (44 + dx + ox, 146 + oy), 3.2, ht.RAMPS["dark_steel"])
    ht.capsule(cv, (40 + ox, 118 + oy), (60 + ox, 118 + oy), 1.6, ht.RAMPS["canvas"])
    ht.outline(cv.img, ht.RAMPS["steel"][0])
    hp.over(canvas, cv.img)


JET_FLAME = [26, 34, 30, 37, 28, 33]


def frames_fly_jet():
    out = []
    for i in range(6):
        def back(canvas, joints, i=i):
            ox, oy = joints["offset"]
            for dx in (0, 11):
                _flame(canvas, 44 + dx + ox, 147 + oy, JET_FLAME[(i + dx) % 6], 4.4)
            _tanks(canvas, ox, oy)

        def mid(canvas, joints):
            _straps(canvas, joints, "canvas")
        out.append(pose_frame(hp.Pose(**HANG), 51, 47, 43, back=back, mid=mid))
    EXTRA["fly_3"] = {"nozzle": sole_units(50 + MARGIN, 152 + MARGIN), "jet_dir": [-0.15, 1.0]}
    return out


def frames_fly_rocket():
    """Топовый джетпак: летит, наклонившись вперёд, ракета на спине, длинный факел назад-вниз."""
    out = []
    lean = 52
    for i in range(6):
        def back(canvas, joints, i=i):
            ox, oy = joints["offset"]
            # ракета вдоль спины, повёрнута вместе с корпусом
            cv = ht.Canvas(canvas.shape[1], canvas.shape[0])
            hip = (77 + ox, 163 + oy)
            top = hp._rot_about((52 + ox, 92 + oy), hip, math.radians(lean))
            bot = hp._rot_about((52 + ox, 150 + oy), hip, math.radians(lean))
            ht.capsule(cv, top, bot, 7.0, ht.RAMPS["steel"])
            band = hp._rot_about((52 + ox, 138 + oy), hip, math.radians(lean))
            ht.capsule(cv, band, bot, 7.2, ht.RAMPS["red"])
            nose = hp._rot_about((52 + ox, 84 + oy), hip, math.radians(lean))
            ht.capsule(cv, nose, top, 4.0, ht.RAMPS["red"])
            ht.outline(cv.img, ht.RAMPS["steel"][0])
            base = hp._rot_about((52 + ox, 156 + oy), hip, math.radians(lean))
            _flame(canvas, base[0], base[1], 58 + (i % 3) * 8, 9.0, "jet", ang=lean)
            hp.over(canvas, cv.img)
            FLY4["base"] = base
        pose = hp.Pose(lean=lean, head_tilt=-20, arm_n=(60, 70), arm_f=(80, 95),
                       leg_n=(-30, -40), leg_f=(-20, -34), body_dy=0)
        out.append(pose_frame(pose, 87, 46, 41, back=back, feet_on_ground=False))
    b = FLY4["base"]
    a = math.radians(lean)
    EXTRA["fly_4"] = {"nozzle": sole_units(b[0] - math.sin(a) * 8, b[1] + math.cos(a) * 8),
                      "jet_dir": [round(-math.sin(a), 2), round(math.cos(a), 2)]}
    return out


FLY4 = {}


def frames_fly_old(jet):
    """Старые ленты fly/fly_jet (запасные, если нет fly_1..4) — те же рисунки."""
    return (frames_fly_jet() if jet else frames_fly_prop(False))[:4]


# ---------------------------------------------------------------------------
# Экспедиционная форма (boy_gear): зелёная футболка, жилет, штаны карго
# ---------------------------------------------------------------------------

GEAR_SHIRT = ["2c3a1e", "3e5228", "52683a", "6a8248", "86a05c"]
GEAR_PANTS = ["3a2a1a", "5a4028", "735436", "8e6a44", "a88456"]


def _ramp_map(img, sel, ramp_hex):
    """Перекрасить пиксели sel в рампу по светлоте (тёмное → тёмное)."""
    ramp = [ht.rgb(h) for h in ramp_hex]
    lum = hp._lum(img[..., :3].astype(float))
    vals = lum[sel]
    if not len(vals):
        return
    lo, hi = np.percentile(vals, 2), np.percentile(vals, 98)
    k = np.clip(np.round((lum - lo) / max(1.0, hi - lo) * (len(ramp) - 1)), 0, len(ramp) - 1).astype(int)
    for i, c in enumerate(ramp):
        img[sel & (k == i)] = c


def _cloth_masks(img):
    a = img[..., 3] > 0
    r, g, b = [img[..., i].astype(int) for i in range(3)]
    lum = hp._lum(img[..., :3].astype(float))
    shirt = a & (b > r + 18) & (lum > 55)
    jeans = a & (np.abs(r - g) < 14) & (np.abs(g - b) < 16) & (lum > 78) & (lum < 185)
    return shirt, jeans, lum


def gear_dress(img):
    out = img.copy()
    a = out[..., 3] > 0
    shirt, jeans, lum = _cloth_masks(out)
    _ramp_map(out, shirt, GEAR_SHIRT)
    _ramp_map(out, jeans, GEAR_PANTS)
    # жилет: полы по бокам груди, середина открыта (видна футболка), карманы
    vest = ht.Canvas(out.shape[1], out.shape[0])
    yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]]
    torso = a & (yy >= 106) & (yy <= 152)
    left = torso & (xx >= 61) & (xx <= 75)
    right = torso & (xx >= 85) & (xx <= 95)
    panel = (left | right) & ~(lum < 50)
    vest.img[panel] = ht.RAMPS["canvas"][3]
    vest.img[panel & ((xx == 75) | (xx == 85))] = ht.RAMPS["canvas"][1]
    for x0, y0 in ((64, 126), (87, 126)):
        pk = (xx >= x0) & (xx <= x0 + 6) & (yy >= y0) & (yy <= y0 + 7) & panel
        vest.img[pk] = ht.RAMPS["canvas"][2]
        vest.img[pk & ((yy == y0) | (xx == x0) | (xx == x0 + 6) | (yy == y0 + 7))] = ht.RAMPS["canvas"][0]
    m = vest.img[..., 3] > 0
    out[m] = vest.img[m]
    # ремень сумки через грудь
    strap = ht.Canvas(out.shape[1], out.shape[0])
    ht.capsule(strap, (92, 107), (64, 150), 1.2, ht.RAMPS["wood"])
    sm = (strap.img[..., 3] > 0) & a
    out[sm] = strap.img[sm]
    return out


def frames_gear(fn):
    STYLE["gear"] = True
    try:
        return fn()
    finally:
        STYLE["gear"] = False


def frames_gear_walk():
    out = []
    for f in frames_walk():
        shirt, jeans, _ = _cloth_masks(f.img)
        _ramp_map(f.img, shirt, GEAR_SHIRT)
        _ramp_map(f.img, jeans, GEAR_PANTS)
        out.append(f)
    return out


# ---------------------------------------------------------------------------
# Возраст 8–15 (сюжетная «перемотка»): тот же мальчик, ниже и уже
# ---------------------------------------------------------------------------

# возраст: (сколько строк убрать, сколько столбцов убрать ниже шеи)
AGES = {"age_8": (32, 4), "age_9": (26, 3), "age_10": (20, 2), "age_11": (15, 1),
        "age_12": (10, 0), "age_15": (0, 0)}


def younger(img, rows_off, cols_off):
    """Голова прежняя (у детей она крупнее к росту), ниже шеи — короче и уже:
    строки убираются по бёдрам, голеням и груди, столбцы — по середине тела."""
    n_legs = int(round(rows_off * 0.62))
    drop = set(np.linspace(170, 200, n_legs, dtype=int).tolist()) if n_legs else set()
    if rows_off - n_legs > 0:
        drop |= set(np.linspace(122, 148, rows_off - n_legs, dtype=int).tolist())
    keep = [y for y in range(img.shape[0]) if y not in drop]
    out = np.zeros_like(img)
    out[img.shape[0] - len(keep):] = img[keep]
    if cols_off:
        neck = 103 + (img.shape[0] - len(keep))
        cut = 78 - cols_off // 2
        for y in range(neck, out.shape[0]):
            row = out[y].copy()
            out[y, cut:out.shape[1] - cols_off] = row[cut + cols_off:]
            out[y, out.shape[1] - cols_off:] = 0
    return out


def frames_age(name):
    rows, cols = AGES[name]
    img = younger(REF, rows, cols)
    f = Frame(17, 42, 42)
    place_feet(f, img, REF_AXIS - cols / 2.0)
    return [f]


# ---------------------------------------------------------------------------
# Портрет для диалогов: бюст эталона 64×64, 3 кадра × 5 выражений
# ---------------------------------------------------------------------------

BUST = (47, 50)     # левый верхний угол бюста 64×64 на эталоне
MOUTH = (80, 90, 93, 98)
EXPRESSIONS = ["neutral", "surprise", "happy", "angry", "sad"]


def _erase_mouth(img):
    out = img.copy()
    skin = img[96, 86].copy()
    x0, y0, x1, y1 = MOUTH
    reg = out[y0:y1, x0:x1]
    dark = hp._lum(reg[..., :3].astype(float)) < 150
    reg[dark] = skin
    return out


def _px(img, pts, c):
    for x, y in pts:
        img[y, x] = c


def face(img, expr, frame):
    """Выражение (брови, рот) и кадр: 0 — молчит, 1 — говорит, 2 — моргнул."""
    out = img.copy()
    lip = np.array([120, 52, 46, 255], np.uint8)
    inside = np.array([70, 22, 24, 255], np.uint8)
    teeth = np.array([244, 236, 222, 255], np.uint8)
    skin = img[86, 85].copy()
    yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]]
    brows = (yy >= 72) & (yy <= 76) & (xx >= 77) & (xx <= 99) \
        & (hp._lum(out[..., :3].astype(float)) < 90) & (out[..., 3] > 0)
    if expr in ("surprise", "angry", "sad"):
        pts = np.argwhere(brows)
        b = out.copy()
        for y, x in pts:
            out[y, x] = skin
        for y, x in pts:
            inner = 84 <= x <= 92
            dy = {"surprise": -1, "angry": 2 if inner else 1, "sad": -1 if inner else 1}[expr]
            out[y + dy, x] = b[y, x]
    talk = frame == 1
    if expr != "neutral" or talk:
        out = _erase_mouth(out)
    if expr == "neutral" and talk:
        _px(out, [(x, 94) for x in range(84, 90)], lip)
        _px(out, [(x, 95) for x in range(84, 90)], inside)
        _px(out, [(x, 96) for x in range(85, 89)], lip)
    elif expr == "surprise":
        r = 2 if talk else 1
        for y in range(94 - r, 95 + r):
            for x in range(86 - r, 88 + r):
                out[y, x] = inside
        _px(out, [(x, 93 - r) for x in range(86 - r, 88 + r)], lip)
    elif expr == "happy":
        _px(out, [(83, 93), (91, 93)], lip)
        _px(out, [(x, 94) for x in range(84, 91)], teeth if talk else lip)
        _px(out, [(x, 95) for x in range(85, 90)], inside if talk else lip)
        if talk:
            _px(out, [(x, 96) for x in range(86, 89)], lip)
    elif expr == "angry":
        _px(out, [(x, 95) for x in range(84, 90)], lip)
        if talk:
            _px(out, [(x, 96) for x in range(84, 90)], inside)
            _px(out, [(x, 97) for x in range(85, 89)], lip)
    elif expr == "sad":
        _px(out, [(84, 96), (89, 96)], lip)
        _px(out, [(x, 95) for x in range(85, 89)], lip)
        if talk:
            _px(out, [(x, 96) for x in range(85, 89)], inside)
    if frame == 2:
        out = blink(out)
    return out


def portrait_sheet(gear=False):
    base = gear_dress(REF) if gear else REF
    cell = 64 * CELL
    sheet = np.zeros((5 * cell, 3 * cell, 4), np.uint8)
    for r, e in enumerate(EXPRESSIONS):
        for c in range(3):
            img = face(base, e, c)
            bust = img[BUST[1]:BUST[1] + 64, BUST[0]:BUST[0] + 64]
            sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = bust.repeat(CELL, 0).repeat(CELL, 1)
    return sheet


def hud_icon():
    """Значок героя в HUD: голова эталона 64×64 (на кнопке 32 точки — ×2)."""
    img = REF[48:112, 54:118].copy()
    img[58:, :] = 0
    a = img[..., 3] > 0
    ring = hp.neighbors4(a) & ~a
    img[ring] = parts().outline
    return img


# ---------------------------------------------------------------------------
# Сборка листов
# ---------------------------------------------------------------------------

def layout(n, fw):
    """Ряды и столбцы: лента в один ряд, если влезает в MAX_TEX, иначе ровные ряды."""
    rows = max(1, math.ceil(n * fw / MAX_TEX))
    cols = math.ceil(n / rows)
    return cols, rows


def trim(frames):
    """Пустое поле кадра — прочь (память видеокарты): по ширине симметрично
    вокруг оси (ось остаётся серединой кадра), сверху — до самого высокого
    пикселя ленты; низ (линия земли и запас под ней) не трогаем. Размеры —
    в целых логических точках."""
    f0 = frames[0]
    a = np.zeros((f0.h, f0.w), bool)
    for f in frames:
        a |= f.img[..., 3] > 0
    ys, xs = np.nonzero(a)
    half = max(f0.axis - xs.min(), xs.max() + 1 - f0.axis) + 1
    half = int(math.ceil(half / (PX / 2.0)) * (PX // 2))
    half = int(min(half, f0.axis))
    top = int(max(0, ys.min() - 1))
    top -= top % PX
    for f in frames:
        f.img = f.img[top:, f.axis - half:f.axis + half]
        f.w, f.h, f.ground = 2 * half, f.h - top, f.ground - top
    return frames


def write_sheet(rel, frames, meta):
    frames = trim(frames)
    f0 = frames[0]
    fw, fh = f0.w * CELL, f0.h * CELL
    cols, rows = layout(len(frames), fw)
    sheet = np.zeros((rows * fh, cols * fw, 4), np.uint8)
    for i, f in enumerate(frames):
        big = f.img.repeat(CELL, 0).repeat(CELL, 1)
        y, x = (i // cols) * fh, (i % cols) * fw
        sheet[y:y + fh, x:x + fw] = big
    assert sheet.shape[0] <= MAX_TEX and sheet.shape[1] <= MAX_TEX, rel
    path = os.path.join(OUT_DIR, rel + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(sheet).save(path, optimize=True)
    meta[rel] = {"fw": fw, "fh": fh, "ground": f0.ground * CELL, "scale": SCALE,
                 "cell": CELL, "cols": cols, "frames": len(frames)}
    meta[rel].update(EXTRA.get(rel, {}))
    print("%-22s %2d кадров %4d×%-4d → %d×%d" % (rel, len(frames), fw, fh, sheet.shape[1], sheet.shape[0]))


SHEETS = {
    "idle": frames_idle,
    "idle_x": frames_idle_x,
    "walk": frames_walk,
    "walk_turn": frames_turn,
    "jump": frames_jump,
    "fall": frames_fall,
    "hurt": frames_hurt,
    "sleep": frames_sleep,
    "dig_pick": frames_pick,
    "dig_pick_rusty": lambda: frames_pick("rust"),
    "dig_shovel": frames_shovel,
    "dig_drill_down": lambda: frames_drill(False),
    "dig_drill_side": lambda: frames_drill(True),
    "fly_1": lambda: frames_fly_prop(False),
    "fly_2": lambda: frames_fly_prop(True),
    "fly_3": frames_fly_jet,
    "fly_4": frames_fly_rocket,
    "fly": lambda: frames_fly_old(False),
    "fly_jet": lambda: frames_fly_old(True),
    "boy_gear/idle": lambda: frames_gear(frames_idle),
    "boy_gear/walk": frames_gear_walk,
    "boy_gear/fall": lambda: frames_gear(frames_fall),
    "boy_gear/fly": lambda: frames_gear(lambda: frames_fly_old(False)),
    "boy_gear/fly_jet": lambda: frames_gear(lambda: frames_fly_old(True)),
    "boy_gear/dig_pick": lambda: frames_gear(frames_pick),
    "boy_gear/dig_shovel": lambda: frames_gear(frames_shovel),
    "boy_gear/sleep": lambda: frames_gear(frames_sleep),
}
for _age in AGES:
    SHEETS["boy/" + _age] = (lambda n: (lambda: frames_age(n)))(_age)

# Сюжетный «мальчик» (art/character/boy/) — копии листов героя: один рисунок на всю игру.
COPIES = ["idle", "walk", "fall", "sleep", "dig_shovel", "dig_pick_rusty", "dig_pick",
          "dig_drill_down", "dig_drill_side", "fly", "fly_jet"]


# ---------------------------------------------------------------------------
# Лист «эталон / было / стало»
# ---------------------------------------------------------------------------

SHEET_POSES = [("idle", 0), ("walk", 2), ("walk", 6), ("jump", 3), ("hurt", 0), ("dig_pick", 3),
               ("dig_shovel", 4), ("dig_drill_side", 2), ("fly_1", 4), ("fly_2", 4), ("fly_3", 1),
               ("fly_4", 1), ("sleep", 0), ("boy_gear/idle", 0), ("boy/age_8", 0)]
WAS_REV = "da1c42f"   # последний коммит до раунда 4 (мальчик ветки hero-art)
OLD_FW = {"dig_pick": 192, "dig_shovel": 192, "fly_1": 154, "fly_2": 204, "fly_3": 152, "fly_4": 260,
          "boy/age_8": 47}


def _old_frame(rel, i):
    import io
    import subprocess
    try:
        data = subprocess.run(["git", "-C", ROOT, "show", "%s:art/character/%s.png" % (WAS_REV, rel)],
                              check=True, capture_output=True).stdout
    except subprocess.CalledProcessError:
        return None
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    fw = OLD_FW.get(rel, 144)
    return im.crop((i * fw, 0, (i + 1) * fw, im.height))


def _new_frame(rel, i, meta):
    m = meta[rel]
    im = Image.open(os.path.join(OUT_DIR, rel + ".png")).convert("RGBA")
    x, y = (i % m["cols"]) * m["fw"], (i // m["cols"]) * m["fh"]
    return im.crop((x, y, x + m["fw"], y + m["fh"]))


def before_after_sheet(out_path, ppu=4):
    """Эталон слева; ряды: было (раунд 3), стало (по эталону); всё — ppu пикселей на точку."""
    from PIL import ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    except OSError:
        font = None
    with open(META) as f:
        meta = json.load(f)["sheets"]
    cell_h = 60 * ppu
    cols = []
    for rel, i in SHEET_POSES:
        old = _old_frame(rel, i)
        new = _new_frame(rel, i, meta)
        if old is not None:
            old = old.resize((int(old.width * ppu / 3), int(old.height * ppu / 3)), Image.NEAREST)
        new = new.resize((int(new.width * ppu / SCALE), int(new.height * ppu / SCALE)), Image.NEAREST)
        cols.append((rel, i, old, new))
    ref = Image.open(os.path.join(ROOT, "art", "_source", "hero_reference.jpg")).convert("RGB")
    ref = ref.crop((240, 260, 660, 1250))
    ref = ref.resize((int(ref.width * 2 * cell_h / ref.height), 2 * cell_h), Image.LANCZOS)
    col_w = [max(c[3].width, c[2].width if c[2] is not None else 0) + 8 for c in cols]
    W = ref.width + 16 + sum(col_w) + 60
    H = 2 * cell_h + 40
    sheet = Image.new("RGB", (W, H), (34, 36, 44))
    d = ImageDraw.Draw(sheet)
    sheet.paste(ref, (8, 30))
    d.text((8, 8), "эталон владельца", fill=(230, 230, 230), font=font)
    x0 = ref.width + 16 + 60
    d.text((x0 - 56, 30 + cell_h // 2), "было", fill=(230, 200, 120), font=font)
    d.text((x0 - 56, 30 + cell_h + cell_h // 2), "стало", fill=(140, 220, 140), font=font)
    bg = [(52, 56, 66), (58, 46, 36)]
    x = x0
    for k, (rel, i, old, new) in enumerate(cols):
        d.text((x, 8), "%s/%d" % (rel.split("/")[-1], i), fill=(200, 200, 200), font=font)
        for r, im in enumerate((old, new)):
            y = 30 + r * cell_h
            d.rectangle((x, y, x + col_w[k] - 4, y + cell_h - 4), fill=bg[r % 2])
            if im is not None:
                pane = Image.new("RGBA", im.size, (0, 0, 0, 0))
                pane.alpha_composite(im)
                sheet.paste(pane, (x + (col_w[k] - 4 - im.width) // 2, y + cell_h - 4 - im.height), pane)
        x += col_w[k]
    sheet.save(out_path)
    print("лист:", out_path, sheet.size)


def main(argv):
    names = [a for a in argv if not a.startswith("--")]
    meta = {}
    if os.path.exists(META):
        with open(META) as f:
            meta = json.load(f).get("sheets", {})
    if "--sheet" in argv:
        before_after_sheet(argv[argv.index("--sheet") + 1])
        return
    for rel, fn in SHEETS.items():
        if names and rel not in names:
            continue
        write_sheet(rel, fn(), meta)
    for rel in COPIES:
        if names and rel not in names and ("boy/" + rel) not in names:
            continue
        Image.open(os.path.join(OUT_DIR, rel + ".png")).save(os.path.join(OUT_DIR, "boy", rel + ".png"))
        meta["boy/" + rel] = dict(meta[rel])
    if not names or "portraits" in names:
        Image.fromarray(portrait_sheet()).save(os.path.join(ROOT, "art", "dialogue", "portrait_boy.png"), optimize=True)
        Image.fromarray(portrait_sheet(True)).save(os.path.join(ROOT, "art", "dialogue", "portrait_boy_gear.png"),
                                                   optimize=True)
        Image.fromarray(hud_icon()).save(os.path.join(ROOT, "art", "ui", "icons", "hero.png"), optimize=True)
        print("портреты диалога (кадр %d), значок героя 64×64" % (64 * CELL))
    doc = {
        "_comment": "Геометрия листов мальчика (tools/gen_hero_ref.py): fw/fh — кадр в текселях, ground — линия земли (подошва на строке над ней), scale — текселей на логическую точку, cell — текселей на пиксель рисунка (шейдер чёткости), cols — кадров в ряду (листы шире 4096 — в несколько рядов), frames — сколько кадров. Не править руками.",
        "sheets": {k: meta[k] for k in sorted(meta)},
    }
    with open(META, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent="\t")
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
