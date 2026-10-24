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


def frames_idle():
    out = []
    for dy in (0, 1, 1, 2):
        f = Frame(48, 48, 46)
        place_feet(f, breathe(REF, dy), REF_AXIS, bottom=REF_Y1)
        out.append(f)
    return out


def frames_idle_x():
    poses = [blink(REF), look(REF, -1), look(REF, 1), toe_up(REF, 3), REF]
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


def parts(closed=False):
    """Части эталона (closed — с закрытыми глазами)."""
    if closed not in _PARTS:
        _PARTS[closed] = hp.Parts(blink(REF) if closed else REF)
    return _PARTS[closed]


def outline_fix(img):
    """Край силуэта — тёмный контур, как у эталона: после поворота частей
    светлый пиксель иногда оказывается снаружи (кожа прямо на фоне)."""
    a = img[..., 3] > 0
    edge = a & hp.neighbors4(~a)
    lum = hp._lum(img[..., :3].astype(float))
    fix = edge & (lum > 95)
    img[fix] = parts().outline
    return img


def pose_frame(pose, w_u=48, h_u=48, ground_u=46, closed=False, back=None, front=None, axis_dx=0):
    img, joints = hp.render(parts(closed), pose, extra_back=back, extra_front=front)
    img = outline_fix(img)
    f = Frame(w_u, h_u, ground_u)
    place_feet(f, img, REF_AXIS + axis_dx)
    return f


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
    return [pose_frame(hp.Pose(**JUMP_POSES[k])) for k in JUMP_ORDER]


def frames_fall():
    poses = [
        dict(arm_n=(-120, -150), arm_f=(120, 140), leg_n=(-14, 2), leg_f=(14, 10)),
        dict(arm_n=(-145, -170), arm_f=(140, 165), leg_n=(-10, 10), leg_f=(18, 4)),
        dict(arm_n=(-110, -130), arm_f=(130, 152), leg_n=(-18, -4), leg_f=(10, 16)),
        dict(arm_n=(-150, -160), arm_f=(115, 135), leg_n=(-12, 8), leg_f=(16, 2)),
    ]
    return [pose_frame(hp.Pose(head_tilt=-4, **p)) for p in poses]


def frames_hurt():
    flinch = hp.Pose(arm_n=(-45, -30), arm_f=(50, 70), lean=-9, head_tilt=-8, leg_n=(-8, 4), leg_f=(10, 2))
    ko = hp.Pose(arm_n=(-22, -12), arm_f=(28, 16), lean=-14, head_tilt=-16, leg_n=(-12, 10), leg_f=(14, -4))
    return [pose_frame(flinch, closed=True), pose_frame(ko, closed=True)]


def frames_sleep():
    """Спит на земле: та же стойка с закрытыми глазами, повёрнутая головой влево."""
    img, _ = hp.render(parts(True), hp.Pose(arm_n=(-6, 4), arm_f=(6, -4)))
    lying = hp.rotate(img, -90.0, (REF_AXIS, 132.0), (100.0, 150.0), (240, 200))
    f = Frame(48, 48, 46)
    x0, y0, x1, y1 = bbox(lying)
    place_feet(f, lying, (x0 + x1) / 2.0)
    return [f]


# ---------------------------------------------------------------------------
# Сборка листов
# ---------------------------------------------------------------------------

def layout(n, fw):
    """Ряды и столбцы: лента в один ряд, если влезает в MAX_TEX, иначе ровные ряды."""
    rows = max(1, math.ceil(n * fw / MAX_TEX))
    cols = math.ceil(n / rows)
    return cols, rows


def write_sheet(rel, frames, meta):
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
}


def main(argv):
    names = [a for a in argv if not a.startswith("--")]
    meta = {}
    if os.path.exists(META):
        with open(META) as f:
            meta = json.load(f).get("sheets", {})
    for rel, fn in SHEETS.items():
        if names and rel not in names:
            continue
        write_sheet(rel, fn(), meta)
    doc = {
        "_comment": "Геометрия листов мальчика (tools/gen_hero_ref.py): fw/fh — кадр в текселях, ground — линия земли (подошва на строке над ней), scale — текселей на логическую точку, cell — текселей на пиксель рисунка (шейдер чёткости), cols — кадров в ряду (листы шире 4096 — в несколько рядов), frames — сколько кадров. Не править руками.",
        "sheets": {k: meta[k] for k in sorted(meta)},
    }
    with open(META, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent="\t")
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
