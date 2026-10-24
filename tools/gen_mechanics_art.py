#!/usr/bin/env python3
"""gen_mechanics_art.py — графика механик раунда 3 (тайники, азарт, журнал) → art/mechanics/.

Замена-заглушка уровня «программист нарисовал аккуратно», не работа художника владельца:
PNG можно заменить под теми же именами, код их только читает.

Что рисует:
  chest_<wood|iron|gold>.png   — лист сундука для мира: 4 кадра 96×96 в ряд (сетка 32×32, растянута ×3,
                                 как тайлы руд): закрыт · крышка приоткрыта (свет изнутри) · открыт с добычей ·
                                 открыт пустой. Сундук лежит в клетке поверх её породы (тайл не трогается).
  chest_<...>_icon.png         — тот же закрытый сундук 32×32 для журнала и тостов.
  streak.png, fever.png        — значки шкалы азарта (оранжевое пламя с самородком) и лихорадки (бело-золотое).
  journal.png                  — пункт меню «Журнал»: книга с киркой на обложке.
  star_on.png, star_off.png    — звёзды мастерства 12×12 (золотая и пустая).

Приёмы — как у руд и лавы (tools/ores_metals.py, tools/gen_tech_art.py): лесенка из 6–8 тонов на
материал, контур тёмным тоном самого материала (не чёрным), свет сверху-слева, отражённый свет на тёмной
стороне, блики на металле, мягкая тень под сундуком; без размытия и антиалиасинга (ореол золотого
сундука — отдельный мягкий слой с альфой, как ореолы руд).

Запуск:  python3 tools/gen_mechanics_art.py [--sheet путь.png]
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "art", "mechanics")
G = 32
SCALE = 3


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


# ── материалы: тоны от контура к блику ───────────────────────────────────────
WOOD = [hexc(c) for c in ("#22140b", "#3d2414", "#563420", "#71462a", "#8c5a33", "#a8723f", "#c48c4e", "#e0ad6c")]
IRON = [hexc(c) for c in ("#15181e", "#262c35", "#3a424e", "#525c6a", "#6c7888", "#8e9aab", "#b6c1cf", "#e6eef6")]
GOLD = [hexc(c) for c in ("#4a2c06", "#764a0e", "#a06c16", "#c8901e", "#e6b22e", "#f6cc48", "#ffe57a", "#fff8d0")]
RUBY = [hexc(c) for c in ("#3a0610", "#6a0c1e", "#9c1830", "#c62440", "#ea4a60", "#ff8496", "#ffd0d8")]
DARK_IN = [hexc(c) for c in ("#0e0805", "#1c120b", "#2a1a10", "#3a2516")]
FIRE = [hexc(c) for c in ("#5a1206", "#9a2a0c", "#d24a12", "#f07a1e", "#ffae34", "#ffd860", "#fff4c0")]
PAPER = [hexc(c) for c in ("#3a2a18", "#7a5a34", "#b89a68", "#dcc494", "#f2e2b8")]
LEATHER = [hexc(c) for c in ("#1e0e10", "#3a1a1e", "#5a2830", "#7a3a42", "#9c5058", "#c07a7e")]

CHESTS = {
    # дерево корпуса, металл обивки, металл замка, что светится изнутри
    # простой ящик: тёмные полосы только по углам и шву, железная накладка замка
    "wood": {"wood": WOOD, "band": [IRON[0]] + IRON[:7], "lock": IRON, "glow": GOLD, "gem": None, "studs": False,
             "mid_bands": False, "lid": None},
    # окованный: крышка обшита сталью, широкие уголки с заклёпками, медный замок
    "iron": {"wood": WOOD, "band": IRON, "lock": GOLD, "glow": GOLD, "gem": None, "studs": True,
             "mid_bands": True, "lid": IRON},
    "gold": {"wood": [hexc(c) for c in ("#1e0c16", "#38142a", "#521e3c", "#6c2a4e", "#863a60", "#a24e74",
                                        "#c06a8c", "#dc8eaa")],
             "band": GOLD, "lock": GOLD, "glow": GOLD, "gem": RUBY, "studs": True, "mid_bands": True, "lid": None},
}


def blank(w=G, h=G):
    return np.zeros((h, w, 4), np.uint8)


def mask_of(draw_fn, w=G, h=G):
    m = Image.new("L", (w, h), 0)
    draw_fn(ImageDraw.Draw(m))
    return np.array(m) > 0


def put(a, m, c):
    a[m] = c


def shifted(m, dx, dy):
    out = np.zeros_like(m)
    h, w = m.shape
    ys, yd = slice(max(dy, 0), h + min(dy, 0)), slice(max(-dy, 0), h + min(-dy, 0))
    xs, xd = slice(max(dx, 0), w + min(dx, 0)), slice(max(-dx, 0), w + min(-dx, 0))
    out[ys, xs] = m[yd, xd]
    return out


def bevel(a, m, ramp, base, light=1, dark=1):
    """Плоская заливка base + светлая кромка сверху-слева, тёмная снизу-справа."""
    a[m] = ramp[base]
    top = m & ~shifted(m, 0, 1)
    left = m & ~shifted(m, 1, 0)
    bot = m & ~shifted(m, 0, -1)
    right = m & ~shifted(m, -1, 0)
    a[(top | left) & m] = ramp[min(base + light, len(ramp) - 1)]
    a[(bot | right) & m] = ramp[max(base - dark, 1)]


def outline(a, color, diag=False):
    alpha = a[:, :, 3] > 0
    grow = alpha.copy()
    steps = [(1, 0), (-1, 0), (0, 1), (0, -1)] + ([(1, 1), (-1, -1), (1, -1), (-1, 1)] if diag else [])
    for dx, dy in steps:
        grow |= shifted(alpha, dx, dy)
    a[grow & ~alpha] = color


def over(dst, src):
    """Наложение src на dst по альфе (обе — uint8 RGBA)."""
    sa = src[:, :, 3:4].astype(np.float32) / 255.0
    da = dst[:, :, 3:4].astype(np.float32) / 255.0
    oa = sa + da * (1 - sa)
    rgb = (src[:, :, :3] * sa + dst[:, :, :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    out = np.zeros_like(dst)
    out[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(oa[:, :, 0] * 255, 0, 255).astype(np.uint8)
    return out


def px(a, x, y, c):
    if 0 <= x < a.shape[1] and 0 <= y < a.shape[0]:
        a[y, x] = c


# ── сундук ───────────────────────────────────────────────────────────────────
BX0, BX1 = 5, 26          # корпус по x (22 пикселя)
BODY_Y0, BODY_Y1 = 17, 28  # корпус по y
LID_Y0 = 10                # верх крышки (закрытой)


def _planks(a, m, ramp, y0, y1, seed):
    """Доски: горизонтальные швы и волокна дерева."""
    rng = np.random.default_rng(seed)
    for y in range(y0, y1 + 1):
        for x in range(BX0, BX1 + 1):
            if not m[y, x]:
                continue
            if (y - y0) % 4 == 3:
                a[y, x] = ramp[2]          # шов между досками
            elif rng.random() < 0.10:
                a[y, x] = ramp[3]          # волокно
            elif rng.random() < 0.05:
                a[y, x] = ramp[5]          # светлая жилка


def _band_v(a, x, y0, y1, ramp, studs):
    for y in range(y0, y1 + 1):
        a[y, x] = ramp[5]
        a[y, x + 1] = ramp[3]
    if studs:
        for y in range(y0 + 1, y1, 3):
            a[y, x] = ramp[7]
            a[y, x + 1] = ramp[4]


def _lock(a, cx, cy, spec, open_=False):
    lock, gem = spec["lock"], spec["gem"]
    m = mask_of(lambda d: d.rectangle([cx - 2, cy - 2, cx + 2, cy + 3], fill=255))
    bevel(a, m, lock, 4, light=2, dark=2)
    if gem is not None:
        px(a, cx, cy, gem[4])
        px(a, cx - 1, cy, gem[3])
        px(a, cx + 1, cy, gem[3])
        px(a, cx, cy - 1, gem[5])
        px(a, cx, cy + 1, gem[2])
        px(a, cx - 1, cy - 1, gem[6])
    else:
        px(a, cx, cy, lock[1])             # замочная скважина
        px(a, cx, cy + 1, lock[1])
        px(a, cx, cy + 2, lock[2])
    px(a, cx - 2, cy - 2, lock[7])         # блик на уголке


def _body(a, spec, seed):
    wood, band = spec["wood"], spec["band"]
    body = mask_of(lambda d: d.rectangle([BX0, BODY_Y0, BX1, BODY_Y1], fill=255))
    bevel(a, body, wood, 4, light=2, dark=2)
    _planks(a, body, wood, BODY_Y0 + 1, BODY_Y1 - 1, seed)
    # отражённый свет снизу на тёмной стороне — кромка не проваливается в контур
    for x in range(BX0 + 2, BX1 - 1):
        a[BODY_Y1 - 1, x] = wood[3]
    # нижняя окантовка и уголки
    for x in range(BX0, BX1 + 1):
        a[BODY_Y1, x] = band[3]
    for x0 in (BX0, BX1 - 1):
        _band_v(a, x0, BODY_Y0, BODY_Y1, band, spec["studs"])
    if spec["mid_bands"]:
        _band_v(a, 10, BODY_Y0, BODY_Y1, band, spec["studs"])
        _band_v(a, 20, BODY_Y0, BODY_Y1, band, spec["studs"])


def _lid_closed(a, spec, seed, lift=0):
    """Выпуклая крышка: дуга сверху, обивка поперёк, кромка у шва. lift — щель над корпусом."""
    wood = spec["lid"] or spec["wood"]
    band = spec["band"]
    y_top = LID_Y0 - lift
    y_bot = BODY_Y0 - 1 - lift
    lid = mask_of(lambda d: (d.rectangle([BX0, y_top + 2, BX1, y_bot], fill=255),
                             d.ellipse([BX0, y_top, BX1, y_top + 6], fill=255)))
    bevel(a, lid, wood, 5, light=2, dark=2)
    rng = np.random.default_rng(seed + 7)
    for y in range(y_top, y_bot + 1):
        for x in range(BX0, BX1 + 1):
            if lid[y, x] and rng.random() < 0.08:
                a[y, x] = wood[4]
    # свет дуги: верхний ряд ярче, по центру блик
    for x in range(BX0 + 3, BX1 - 2):
        if lid[y_top + 1, x]:
            a[y_top + 1, x] = wood[6]
    for x in range(BX0 + 6, BX0 + 10):
        a[y_top + 1, x] = wood[7]
    # обивка крышки: продольная кромка у шва и поперечные полосы
    for x in range(BX0, BX1 + 1):
        a[y_bot, x] = band[3]
        a[y_bot - 1, x] = band[5]
    for x0 in (BX0, BX1 - 1, 10, 20) if spec["mid_bands"] else (BX0, BX1 - 1):
        for y in range(y_top + 1, y_bot):
            if lid[y, x0]:
                a[y, x0] = band[5]
            if lid[y, x0 + 1]:
                a[y, x0 + 1] = band[3]
        if spec["studs"]:
            px(a, x0, y_top + 3, band[7])
    if spec["lid"] is not None:
        # заклёпки по стальной крышке
        for x in range(BX0 + 3, BX1 - 2, 4):
            px(a, x, y_bot - 3, band[7])
            px(a, x + 1, y_bot - 3, band[3])


def _lid_open(a, spec):
    """Откинутая крышка: видна её внутренняя сторона (тёмная) и торец сверху."""
    wood = spec["lid"] or spec["wood"]
    band = spec["band"]
    lid = mask_of(lambda d: d.polygon([(BX0 + 1, 4), (BX1 - 1, 4), (BX1, 11), (BX0, 11)], fill=255))
    bevel(a, lid, wood, 3, light=1, dark=1)
    for y in (6, 9):
        for x in range(BX0 + 1, BX1):
            if lid[y, x]:
                a[y, x] = wood[2]
    for x in range(BX0 + 1, BX1):
        a[4, x] = band[6]
        a[5, x] = band[4]
    for x0 in (BX0 + 1, BX1 - 2, 10, 20) if spec["mid_bands"] else (BX0 + 1, BX1 - 2):
        for y in range(4, 12):
            if lid[y, x0]:
                a[y, x0] = band[4]


def _interior(a, spec, loot):
    """Нутро открытого сундука: тёмная полость, у полного — горка добычи с бликами."""
    inner = mask_of(lambda d: d.rectangle([BX0 + 2, 12, BX1 - 2, BODY_Y0 + 1], fill=255))
    a[inner] = DARK_IN[1]
    for x in range(BX0 + 2, BX1 - 1):
        a[12, x] = DARK_IN[0]
    # передняя стенка корпуса: её верхняя кромка — светлая доска
    for x in range(BX0, BX1 + 1):
        a[BODY_Y0, x] = spec["wood"][6]
    if not loot:
        return
    gold = GOLD
    pile = mask_of(lambda d: d.ellipse([BX0 + 3, 11, BX1 - 3, 19], fill=255)) & mask_of(
        lambda d: d.rectangle([0, 0, G, BODY_Y0 - 1], fill=255))
    bevel(a, pile, gold, 4, light=2, dark=2)
    # монеты (кружки) и самоцвет на горке
    for (cx, cy) in ((11, 14), (15, 13), (19, 14), (13, 15), (17, 15)):
        px(a, cx, cy, gold[6])
        px(a, cx + 1, cy, gold[5])
        px(a, cx, cy + 1, gold[3])
    gem = spec["gem"] or RUBY
    for (x, y, k) in ((16, 12, 5), (15, 12, 4), (17, 12, 3), (16, 11, 6)):
        px(a, x, y, gem[k])
    px(a, 12, 12, gold[7])
    px(a, 20, 13, gold[7])


def _shadow(a):
    """Мягкая тень сундука на породу (полупрозрачная, без антиалиасинга)."""
    sh = mask_of(lambda d: d.ellipse([BX0 - 1, BODY_Y1 - 1, BX1 + 1, BODY_Y1 + 3], fill=255))
    sh &= a[:, :, 3] == 0
    a[sh] = (10, 6, 4, 110)


def _glow_layer(color, cx, cy, r, alpha):
    """Ореол (свет из сундука): радиальная альфа ступенями — пиксель-арт без размытия."""
    g = blank()
    yy, xx = np.mgrid[0:G, 0:G]
    d = np.sqrt((xx - cx) ** 2 + ((yy - cy) * 1.3) ** 2) / r
    steps = np.clip(np.floor((1.0 - d) * 4) / 4, 0, 1)
    g[:, :, 0], g[:, :, 1], g[:, :, 2] = color[0], color[1], color[2]
    g[:, :, 3] = (steps * alpha * 255).astype(np.uint8)
    return g


def _rays(a, color):
    """Лучи света из щели приоткрытой крышки."""
    for (x0, x1) in ((9, 6), (13, 12), (16, 16), (19, 20), (22, 25)):
        for i, y in enumerate(range(11, 2, -1)):
            x = x0 + (x1 - x0) * i // 8
            if 0 <= x < G and a[y, x, 3] == 0:
                a[y, x] = (color[0], color[1], color[2], 150 - i * 14)


def chest_frame(kind, frame):
    spec = CHESTS[kind]
    seed = {"wood": 3, "iron": 5, "gold": 9}[kind]
    a = blank()
    if frame == 0:
        _body(a, spec, seed)
        _lid_closed(a, spec, seed)
        _lock(a, 15, BODY_Y0, spec)
    elif frame == 1:
        _body(a, spec, seed)
        # щель светится: полоса света между корпусом и крышкой
        for x in range(BX0 + 1, BX1):
            a[BODY_Y0 - 1, x] = spec["glow"][6]
            a[BODY_Y0 - 2, x] = spec["glow"][5]
        _lid_closed(a, spec, seed, lift=2)
        _lock(a, 15, BODY_Y0, spec)
    else:
        _lid_open(a, spec)
        _body(a, spec, seed)
        _interior(a, spec, loot=(frame == 2))
        _lock(a, 15, BODY_Y0 + 2, spec, open_=True)
    outline(a, spec["wood"][0])
    if frame == 1:
        _rays(a, spec["glow"][6])
    _shadow(a)
    if kind == "gold" and frame in (0, 2):
        # блёстки на золоте: крестики-искры, как на тайле золота
        for (x, y) in ((8, 12), (24, 19)) if frame == 0 else ((10, 10), (22, 12)):
            px(a, x, y, GOLD[7])
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if a[y + dy, x + dx, 3] == 0:
                    px(a, x + dx, y + dy, (255, 246, 200, 200))
    if frame in (1, 2):
        a = over(_glow_layer(spec["glow"][5], 15.5, 13, 13 if frame == 1 else 10, 0.35 if frame == 1 else 0.22), a)
    return a


def chest_sheet(kind):
    frames = [chest_frame(kind, f) for f in range(4)]
    sheet = Image.new("RGBA", (G * SCALE * 4, G * SCALE), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        im = Image.fromarray(fr, "RGBA").resize((G * SCALE, G * SCALE), Image.NEAREST)
        sheet.paste(im, (i * G * SCALE, 0))
    return sheet, Image.fromarray(frames[0], "RGBA")


# ── значки ───────────────────────────────────────────────────────────────────

def _flame(a, ramp, cx, base_y, h, w):
    outer = mask_of(lambda d: d.polygon([(cx, base_y - h), (cx + w // 2 + 1, base_y - h // 2),
                                         (cx + w // 2 + 2, base_y - 4), (cx + w // 2, base_y - 1), (cx, base_y + 1),
                                         (cx - w // 2, base_y - 1), (cx - w // 2 - 2, base_y - 4),
                                         (cx - w // 2 - 1, base_y - h // 2), (cx - 2, base_y - h + 6),
                                         (cx - 1, base_y - h + 3)], fill=255))
    bevel(a, outer, ramp, 2, light=1, dark=1)
    mid = mask_of(lambda d: d.polygon([(cx + 1, base_y - h + 7), (cx + w // 2, base_y - 5), (cx + 2, base_y - 1),
                                       (cx - 3, base_y - 1), (cx - w // 2 + 1, base_y - 6)], fill=255))
    a[mid] = ramp[4]
    core = mask_of(lambda d: d.polygon([(cx, base_y - h // 2 + 1), (cx + 3, base_y - 4), (cx, base_y - 1),
                                        (cx - 3, base_y - 4)], fill=255))
    a[core] = ramp[5]


def icon_streak(fever=False):
    a = blank()
    ramp = FIRE if not fever else [hexc(c) for c in ("#6a3a06", "#b4740c", "#e6aa20", "#ffd040", "#ffe988",
                                                      "#fff6c8", "#ffffff")]
    _flame(a, ramp, 16, 28, 25, 16)
    # самородок в сердце пламени: азарт — это про жилу, а не про жару
    nug = mask_of(lambda d: d.ellipse([12, 19, 20, 26], fill=255))
    bevel(a, nug, GOLD, 4, light=2, dark=2)
    px(a, 14, 21, GOLD[7])
    px(a, 15, 21, GOLD[6])
    outline(a, ramp[0])
    if fever:
        for (x, y) in ((5, 8), (26, 6), (27, 18), (4, 20)):
            px(a, x, y, (255, 255, 255, 255))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if a[y + dy, x + dx, 3] == 0:
                    px(a, x + dx, y + dy, (255, 236, 150, 220))
    return a


def icon_journal():
    a = blank()
    pages = mask_of(lambda d: d.rectangle([8, 6, 26, 27], fill=255))
    bevel(a, pages, PAPER, 3, light=1, dark=1)
    for y in range(8, 26, 2):
        a[y, 26] = PAPER[2]
    cover = mask_of(lambda d: d.rectangle([5, 4, 24, 26], fill=255))
    bevel(a, cover, LEATHER, 3, light=2, dark=2)
    for y in range(5, 26):            # корешок
        a[y, 5] = LEATHER[1]
        a[y, 6] = LEATHER[2]
        a[y, 7] = LEATHER[4]
    for x in range(8, 24):            # тиснение рамкой
        a[6, x] = GOLD[3]
        a[24, x] = GOLD[2]
    for y in range(6, 25):
        a[y, 9] = GOLD[3]
        a[y, 22] = GOLD[2]
    # кирка на обложке: древко и навершие
    for i in range(10):
        px(a, 11 + i, 21 - i, WOOD[5] if i % 2 else WOOD[4])
    pick = mask_of(lambda d: d.polygon([(12, 10), (16, 9), (20, 11), (23, 15), (21, 14), (17, 12), (13, 12)], fill=255))
    bevel(a, pick, IRON, 5, light=2, dark=2)
    px(a, 14, 10, IRON[7])
    # закладка-ленточка
    for y in range(26, 30):
        px(a, 19, y, RUBY[3])
        px(a, 20, y, RUBY[2])
    outline(a, LEATHER[0])
    return a


STAR = [
    "....##....",
    "....##....",
    "...####...",
    "##########",
    ".########.",
    "..######..",
    "..######..",
    ".###..###.",
    ".##....##.",
]


STAR_S = [
    "...##...",
    "...##...",
    "########",
    ".######.",
    "..####..",
    ".######.",
    ".##..##.",
    ".#....#.",
]


def star(size, filled, pattern=None):
    """Звезда мастерства по нарисованному шаблону 10×9 (у мелкой звезды многоугольник рвётся)."""
    pattern = pattern or STAR
    a = blank(size, size)
    m = np.zeros((size, size), bool)
    ox, oy = (size - len(pattern[0])) // 2, (size - len(pattern)) // 2
    for y, row in enumerate(pattern):
        for x, ch in enumerate(row):
            if ch == "#":
                m[oy + y, ox + x] = True
    if filled and pattern is STAR_S:
        a[m] = GOLD[5]
        a[m & ~shifted(m, 0, 1)] = GOLD[7]
        a[m & ~shifted(m, 0, -1)] = GOLD[3]
    elif filled:
        a[m] = GOLD[5]
        a[m & ~shifted(m, 0, 1)] = GOLD[7]
        a[m & ~shifted(m, 1, 0) & ~shifted(m, 0, 1)] = GOLD[7]
        a[m & ~shifted(m, 0, -1)] = GOLD[3]
        a[m & ~shifted(m, -1, 0) & ~shifted(m, 0, -1)] = GOLD[2]
        outline(a, GOLD[0])
    elif pattern is STAR_S:
        a[m] = (96, 80, 60, 255)
    else:
        a[m] = (52, 40, 30, 255)
        outline(a, (120, 100, 76, 255))
    return a


def save(arr_or_img, name):
    os.makedirs(OUT, exist_ok=True)
    im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img, "RGBA")
    im.save(os.path.join(OUT, name))
    return im


def main():
    made = []
    for kind in CHESTS:
        sheet, icon = chest_sheet(kind)
        made.append(save(sheet, "chest_%s.png" % kind))
        made.append(save(icon, "chest_%s_icon.png" % kind))
    made.append(save(icon_streak(False), "streak.png"))
    made.append(save(icon_streak(True), "fever.png"))
    made.append(save(icon_journal(), "journal.png"))
    made.append(save(star(12, True), "star_on.png"))
    made.append(save(star(12, False), "star_off.png"))
    # мелкие звёзды плиток журнала (8×8 без обводки: плашка тёмная, обводка съела бы форму)
    made.append(save(star(8, True, STAR_S), "star_s_on.png"))
    made.append(save(star(8, False, STAR_S), "star_s_off.png"))
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        bg = Image.new("RGBA", (1200, 640), (52, 48, 60, 255))
        y = 8
        for kind in CHESTS:
            sh = Image.open(os.path.join(OUT, "chest_%s.png" % kind)).resize((96 * 4 * 1, 96), Image.NEAREST)
            # на фоне тайла земли — так сундук видно в игре
            tile = Image.open(os.path.join(ROOT, "art", "tiles", "dirt_1.png")).convert("RGBA")
            for i in range(4):
                bg.paste(tile, (8 + i * 100, y), tile)
            bg.alpha_composite(sh, (8, y))
            big = sh.crop((0, 0, 96, 96)).resize((192, 192), Image.NEAREST)
            bg.alpha_composite(big, (420 + list(CHESTS).index(kind) * 200, 8))
            y += 104
        x = 8
        for name in ("streak", "fever", "journal", "star_on", "star_off"):
            im = Image.open(os.path.join(OUT, name + ".png"))
            s = 128 // im.size[0]
            im = im.resize((im.size[0] * s, im.size[1] * s), Image.NEAREST)
            bg.alpha_composite(im, (x, 330))
            x += im.size[0] + 16
        bg.save(path)
    print("art/mechanics: %d файлов" % len(made))


if __name__ == "__main__":
    main()
