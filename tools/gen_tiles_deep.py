#!/usr/bin/env python3
"""gen_tiles_deep.py — графика глубины: тайлы поясов, руды глубже 3000, кладка руин, стены-фоны.

Что делает (всё из палитры проекта и уже готовых тайлов, без внешних файлов):

1. Атласы поясов `art/tiles/deep/belt_<i>.png` (i = 1..7) + `atlas.json`. Пояс 0 («Корни») — прежние
   тайлы, их не трогаем. В остальных поясах земля и ВСЕ руды пересведены к тону пояса тем же приёмом,
   что и в tools/import_tiles.py: фоновый (грунтовый) кластер каждого тайла сдвигается к цели пояса с
   весом «насколько пиксель похож на грунт», поэтому руда остаётся как нарисована, а плашек-заплаток
   на фоне нет (ГДД §15.1: тайлы сводятся к общему тону фона; земля одной светлоты внутри пояса).
   Поверх грунта — лёгкая текстура пояса (прослойки, блики кристаллов, трещины магмы, кладка, звёзды).
2. Восемь новых руд (геокристалл, древний металл, обсидиан, адский камень, чёрная материя, вселениум,
   ангельский камень, божественное сердце) и кладка руин: пиксель-арт на сетке 32x32, контур, блик,
   палитра; для пояса 0 пишутся отдельными файлами art/tiles/<имя>.png, для остальных — в атласы.
3. Стены-фоны подземного параллакса `art/env/deep/wall_<имя>.png`: бесшовные 96x96, тёмные.

Запуск:  python3 tools/gen_tiles_deep.py
Это замена-заглушка уровня «программист нарисовал аккуратно», не работа художника владельца.
"""

import json
import math
import os
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from sprite_kit import Sprite

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILES = os.path.join(ROOT, "art", "tiles")
DEEP = os.path.join(TILES, "deep")
ENV = os.path.join(ROOT, "art", "env", "deep")

T = 96            # размер тайла в пикселях текстуры (ART_SCALE 3 x 32)
G = 32            # сетка пиксель-арта
PAD = 2           # экструзия краёв в атласе (против просвечивания соседей)
COLS, ROWS = 7, 6

ATLAS_NAMES = (
    [f"dirt_{i}" for i in range(1, 9)] + ["stone", "empty"]
    + ["ore_iron", "ore_lead", "ore_silver", "ore_copper", "ore_aluminium", "ore_gold", "ore_diamond",
       "ore_nickel", "ore_peat", "ore_coal", "ore_platinum", "ore_titanium", "ore_lithium", "ore_mercury",
       "ore_uranium", "ore_ruby", "ore_emerald", "ore_scrap"]
    + ["ore_geocrystal", "ore_ancient_metal", "ore_obsidian", "ore_hellstone", "ore_dark_matter",
       "ore_universalium", "ore_angelstone", "ore_divine_heart", "ruin_brick"]
)
NEW_ORES = ["ore_geocrystal", "ore_ancient_metal", "ore_obsidian", "ore_hellstone", "ore_dark_matter",
            "ore_universalium", "ore_angelstone", "ore_divine_heart"]

# ── цвет ──────────────────────────────────────────────────────────────────

_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
_MI = np.linalg.inv(_M)
_WP = np.array([0.95047, 1.0, 1.08883])


def rgb2lab(rgb):
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = (lin @ _M.T) / _WP
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab2rgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * _WP
    lin = np.clip(xyz @ _MI.T, 0, 1)
    c = np.where(lin > 0.0031308, 1.055 * lin ** (1 / 2.4) - 0.055, 12.92 * lin)
    return np.clip(np.rint(c * 255), 0, 255)


def soil_weights(lab, ref, sigma=14.0, lw=0.35, iters=6):
    """Вес «это грунт» на пиксель: робастный кластер фона вокруг затравки ref (как background() в import_tiles)."""
    m = np.asarray(ref, dtype=np.float64)
    w = None
    for _ in range(iters):
        d2 = ((lab[..., 0] - m[0]) * lw) ** 2 + (lab[..., 1] - m[1]) ** 2 + (lab[..., 2] - m[2]) ** 2
        w = np.exp(-d2 / (2 * sigma * sigma))
        s = w.sum()
        if s < 1e-6:
            break
        m = (w[..., None] * lab).sum((0, 1)) / s
    return w


def rng_for(*parts):
    return np.random.default_rng(zlib.crc32("/".join(str(p) for p in parts).encode()))


def load(path):
    return np.array(Image.open(path).convert("RGB"), dtype=np.float64)


def save_rgb(arr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(np.rint(arr), 0, 255).astype(np.uint8), "RGB").save(path, optimize=True)


# ── палитра руд глубже 3000 (в art/PALETTE.md их нет — добавлены здесь) ────

PAL = {
    "geo_dark": (138, 42, 18), "geo_base": (255, 122, 46), "geo_light": (255, 198, 107), "geo_out": (74, 24, 10),
    "anc_dark": (44, 84, 72), "anc_base": (90, 160, 138), "anc_light": (168, 224, 200), "anc_out": (24, 44, 38),
    "anc_rune": (232, 179, 46),
    "obs_base": (28, 20, 36), "obs_sheen": (106, 76, 156), "obs_light": (201, 179, 240), "obs_out": (8, 4, 14),
    "hell_dark": (90, 19, 12), "hell_base": (150, 38, 20), "hell_glow": (255, 74, 28), "hell_light": (255, 179, 71),
    "hell_out": (30, 6, 4),
    "dm_core": (7, 4, 12), "dm_rim": (122, 44, 255), "dm_light": (214, 190, 255),
    "uni_cyan": (111, 224, 216), "uni_gold": (255, 224, 102), "uni_white": (255, 255, 255), "uni_out": (58, 92, 122),
    "ang_base": (255, 244, 194), "ang_shade": (232, 200, 120), "ang_gold": (255, 224, 102), "ang_out": (140, 108, 52),
    "div_base": (255, 85, 112), "div_dark": (194, 30, 58), "div_gold": (255, 224, 102), "div_out": (96, 14, 30),
}


# ── пиксель-арт на сетке 32x32: класс Sprite — в tools/sprite_kit.py ──


def sprite_geocrystal():
    s = Sprite()
    P = PAL
    # три призмы: боковые грани светлая/тёмная
    def crystal(cx, top, bot, w, tilt=0):
        h = (bot - top)
        a = [(cx + tilt, top), (cx + w, top + h * 0.28), (cx + w, bot - h * 0.22), (cx, bot), (cx - w, bot - h * 0.22), (cx - w, top + h * 0.28)]
        s.poly(a, P["geo_base"])
        s.poly([a[0], a[5], a[4], a[3]], P["geo_light"])
        s.poly([a[0], a[1], a[2], a[3]], P["geo_dark"])
        s.line(a[0], (cx - 1, bot - 3), P["geo_base"], 255)
    crystal(8, 12, 27, 4, -1)
    crystal(23, 10, 26, 4, 1)
    crystal(16, 4, 28, 6, 0)
    s.outline(P["geo_out"])
    s.glow(P["geo_base"], 2.5, 0.55)
    for p in ((14, 8), (15, 9), (21, 13), (6, 17)):
        s.px(*p, (255, 245, 200))
    return s


def sprite_ancient():
    s = Sprite()
    P = PAL
    # плита патинированной бронзы + малый слиток; на лице — руна
    s.poly([(4, 11), (23, 8), (28, 14), (26, 23), (7, 25), (3, 18)], P["anc_base"])
    s.poly([(4, 11), (23, 8), (28, 14), (26, 12), (6, 15)], P["anc_light"])
    s.poly([(3, 18), (7, 25), (26, 23), (28, 14), (26, 20), (7, 21)], P["anc_dark"])
    s.poly([(18, 21), (27, 20), (28, 27), (19, 28)], P["anc_dark"])
    s.poly([(18, 21), (27, 20), (26, 22), (19, 23)], P["anc_base"])
    s.outline(P["anc_out"])
    # руна: кольцо и вертикальная черта
    for p in ((13, 13), (14, 12), (15, 12), (16, 13), (16, 14), (16, 15), (15, 16), (14, 16), (13, 15), (13, 14)):
        s.px(*p, P["anc_rune"])
    for y in range(11, 18):
        s.px(19, y, P["anc_rune"])
    s.px(18, 13, P["anc_rune"])
    s.px(20, 15, P["anc_rune"])
    for p in ((7, 13), (22, 10), (24, 12)):
        s.px(*p, (230, 250, 240))
    return s


def sprite_obsidian():
    s = Sprite()
    P = PAL
    def shard(pts, sheen):
        s.poly(pts, P["obs_base"])
        s.poly(sheen, P["obs_sheen"])
    shard([(16, 3), (21, 14), (19, 27), (13, 27), (11, 14)], [(16, 3), (21, 14), (19, 16), (16, 8)])
    shard([(7, 14), (11, 19), (10, 28), (5, 27), (4, 20)], [(7, 14), (11, 19), (9, 19), (6, 17)])
    shard([(25, 12), (28, 19), (27, 27), (22, 27), (22, 19)], [(25, 12), (28, 19), (26, 20), (24, 16)])
    s.outline(P["obs_out"])
    for p in ((16, 5), (16, 6), (18, 11), (8, 16), (26, 15)):
        s.px(*p, P["obs_light"])
    return s


def sprite_hellstone():
    s = Sprite()
    P = PAL
    s.poly([(5, 14), (11, 6), (22, 5), (28, 12), (27, 23), (19, 28), (8, 27), (4, 21)], P["hell_dark"])
    s.poly([(11, 6), (22, 5), (25, 9), (15, 11), (8, 12)], P["hell_base"])
    s.outline(P["hell_out"])
    s.glow(P["hell_glow"], 2.0, 0.5)
    # прожилки магмы
    for a, b in (((8, 15), (14, 19)), ((14, 19), (13, 25)), ((14, 19), (22, 16)), ((22, 16), (25, 20)), ((18, 9), (20, 14))):
        s.line(a, b, P["hell_glow"])
    for a, b in (((9, 16), (13, 19)), ((15, 19), (21, 16))):
        s.line(a, b, P["hell_light"])
    for p in ((6, 25), (25, 7), (10, 4), (28, 18)):
        s.px(*p, P["hell_light"])
    return s


def sprite_dark_matter():
    s = Sprite()
    P = PAL
    cx = cy = 15.5
    for y in range(G):
        for x in range(G):
            d = math.hypot(x - cx, y - cy)
            if d <= 9.2:
                s.px(x, y, P["dm_core"])
    for y in range(G):
        for x in range(G):
            d = math.hypot(x - cx, y - cy)
            if 8.2 < d <= 9.4:
                s.px(x, y, P["dm_rim"])
    # аккреционная дуга
    for k in range(40):
        t = k / 40.0 * 2.6 + 3.3
        r = 11.5 - k * 0.04
        x = cx + r * math.cos(t)
        y = cy + 0.45 * r * math.sin(t)
        s.px(round(x), round(y), P["dm_light"], 235)
    s.glow(P["dm_rim"], 2.8, 0.7)
    for p in ((5, 6), (26, 8), (27, 24), (6, 25), (16, 2)):
        s.px(*p, (255, 255, 255))
    return s


def sprite_universalium():
    s = Sprite()
    P = PAL
    star = [(16, 3), (19, 13), (29, 16), (19, 19), (16, 29), (13, 19), (3, 16), (13, 13)]
    s.poly(star, P["uni_cyan"])
    s.poly([(16, 3), (16, 16), (29, 16), (19, 13)], P["uni_gold"])
    s.poly([(16, 29), (16, 16), (3, 16), (13, 19)], P["uni_gold"])
    s.poly([(13, 13), (16, 10), (19, 13), (16, 22), (13, 19)], P["uni_white"])
    s.outline(P["uni_out"])
    s.glow(P["uni_cyan"], 2.4, 0.45)
    for p in ((16, 6), (8, 15), (24, 17), (16, 25)):
        s.px(*p, (255, 255, 255))
    return s


def sprite_angelstone():
    s = Sprite()
    P = PAL
    s.poly([(16, 6), (24, 13), (21, 25), (16, 28), (11, 25), (8, 13)], P["ang_base"])
    s.poly([(16, 6), (24, 13), (21, 25), (16, 28)], P["ang_shade"])
    s.poly([(16, 6), (12, 11), (14, 24), (16, 28), (11, 25), (8, 13)], P["ang_base"])
    s.outline(P["ang_out"])
    # нимб над камнем
    for k in range(28):
        t = k / 28.0 * math.tau
        s.px(round(16 + 6.5 * math.cos(t)), round(4.5 + 1.8 * math.sin(t)), P["ang_gold"])
    s.glow(P["ang_gold"], 2.6, 0.55)
    for p in ((14, 12), (15, 13), (16, 11), (6, 20), (26, 21)):
        s.px(*p, (255, 255, 255))
    return s


def sprite_divine_heart():
    s = Sprite()
    P = PAL
    heart = [(16, 27), (6, 17), (5, 11), (9, 7), (14, 8), (16, 11), (18, 8), (23, 7), (27, 11), (26, 17)]
    s.poly(heart, P["div_base"])
    s.poly([(16, 27), (26, 17), (27, 11), (23, 7), (18, 8), (16, 11), (17, 19)], P["div_dark"])
    s.outline(P["div_out"])
    s.glow(P["div_gold"], 2.8, 0.6)
    for k in range(10):
        t = k / 10.0 * math.tau
        x0, y0 = 16 + 10 * math.cos(t), 16 + 10 * math.sin(t)
        x1, y1 = 16 + 13 * math.cos(t), 16 + 13 * math.sin(t)
        if 0 <= x1 < G and 0 <= y1 < G:
            s.line((round(x0), round(y0)), (round(x1), round(y1)), P["div_gold"], 200)
    for p in ((9, 10), (10, 9), (10, 11)):
        s.px(*p, (255, 220, 230))
    s.px(16, 14, P["div_gold"])
    s.px(15, 15, P["div_gold"])
    s.px(17, 15, P["div_gold"])
    s.px(16, 16, P["div_gold"])
    return s


SPRITES = {
    "ore_geocrystal": sprite_geocrystal, "ore_ancient_metal": sprite_ancient, "ore_obsidian": sprite_obsidian,
    "ore_hellstone": sprite_hellstone, "ore_dark_matter": sprite_dark_matter,
    "ore_universalium": sprite_universalium, "ore_angelstone": sprite_angelstone,
    "ore_divine_heart": sprite_divine_heart,
}


def _load_resource_modules():
    """Спрайты ресурсов лежат в tools/ores_metals.py и tools/ores_gems.py (TILES: имя тайла -> функция,
    возвращающая Sprite с залежью без грунта). Они перекрывают и прежние руды, и «новые» выше."""
    import importlib
    found = {}
    for mod_name in ("ores_metals", "ores_gems"):
        try:
            m = importlib.import_module(mod_name)
        except ModuleNotFoundError as e:
            if e.name != mod_name:
                raise
            continue
        found.update(getattr(m, "TILES", {}))
    return found


SPRITES.update(_load_resource_modules())


def _load_override(mod_name, attr):
    """Необязательные модули-переопределения: tools/ground_tiles.py (GROUND: земля и камень пояса 0)
    и tools/walls_deep.py (WALLS: стены-фоны). Каждая запись — функция без аргументов, возвращающая
    float RGB (96, 96, 3), бесшовную по обоим краям."""
    import importlib
    try:
        m = importlib.import_module(mod_name)
    except ModuleNotFoundError as e:
        if e.name != mod_name:
            raise
        return {}
    return dict(getattr(m, attr, {}))
# все руды, у которых есть спрайт, собираются поверх грунта пояса (а не режутся из авторского листа)
NEW_ORES = [n for n in ATLAS_NAMES if n in SPRITES]


# ── кладка руин ───────────────────────────────────────────────────────────

def ruin_brick_base():
    """Песчаник: ряды по 8 клеток-пикселей (24 px), кирпич 16 (48 px), перевязка в полкирпича."""
    rng = rng_for("ruin_brick")
    img = np.zeros((T, T, 3), dtype=np.float64)
    base = np.array([132, 114, 88], dtype=np.float64)
    mortar = np.array([66, 56, 44], dtype=np.float64)
    hi = np.array([166, 146, 114], dtype=np.float64)
    for c in range(4):
        y0 = c * 24
        off = 0 if c % 2 == 0 else 24
        for k in range(3):
            x0 = (off + k * 48) % T
            tone = 1.0 + rng.uniform(-0.09, 0.09)
            for yy in range(y0, y0 + 24):
                for xx in range(x0, x0 + 48):
                    img[yy, xx % T] = base * tone
            # сколы и зерно
            for _ in range(10):
                px = (x0 + rng.integers(3, 45)) % T
                py = y0 + rng.integers(3, 21)
                img[py, px] *= rng.uniform(0.82, 1.14)
    for c in range(4):
        y0 = c * 24
        img[y0:y0 + 2, :] = mortar
        img[y0 + 2:y0 + 4, :] = img[y0 + 2:y0 + 4, :] * 0.5 + hi * 0.5
        off = 0 if c % 2 == 0 else 24
        for k in range(3):
            x0 = (off + k * 48) % T
            for xx in (x0, (x0 + 1) % T):
                img[y0:y0 + 24, xx] = mortar
    noise = rng.normal(0, 3.2, (T, T, 1))
    return np.clip(img + noise, 0, 255)


# ── текстура грунта пояса (оверлеи) ───────────────────────────────────────

def mask_of(fn):
    m = Image.new("L", (T, T), 0)
    fn(ImageDraw.Draw(m))
    return np.array(m, dtype=np.float64) / 255.0


def blend(img, mask, color, alpha):
    a = (mask * alpha)[..., None]
    img[:] = img * (1 - a) + np.array(color, dtype=np.float64) * a


def overlay(theme, img, w, rng):
    """Оверлей пояса на RGB-тайл (float). w — вес «это грунт», руда остаётся нетронутой."""
    if theme == "caves":
        # слоистость: ряды чуть светлее/темнее, крапины гальки
        rows = (np.sin(np.arange(T) * (math.tau / 24.0) + rng.uniform(0, 6.28)) * 0.035
                + rng.normal(0, 0.012, T))
        img *= (1.0 + rows[:, None, None] * w[..., None])
        for _ in range(3):
            cx, cy = rng.integers(10, T - 10), rng.integers(10, T - 10)
            m = mask_of(lambda d: d.ellipse([cx - 5, cy - 3, cx + 5, cy + 3], fill=255))
            blend(img, m * w, (110, 108, 94), 0.55)
            m2 = mask_of(lambda d: d.ellipse([cx - 5, cy + 1, cx + 5, cy + 4], fill=255))
            blend(img, m2 * w, (40, 40, 34), 0.35)
    elif theme == "crystal":
        for _ in range(int(rng.integers(3, 6))):
            cx, cy = int(rng.integers(8, T - 8)), int(rng.integers(8, T - 8))
            col = (190, 160, 255) if rng.random() < 0.6 else (130, 235, 225)
            m = mask_of(lambda d: (d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=255),
                                   d.line([cx - 5, cy, cx + 5, cy], fill=110, width=2),
                                   d.line([cx, cy - 5, cx, cy + 5], fill=110, width=2)))
            blend(img, m * w, col, 0.85)
    elif theme == "bedrock":
        for _ in range(2):
            x, y = float(rng.integers(12, T - 12)), float(rng.integers(12, T - 12))
            pts = [(x, y)]
            for _s in range(7):
                x = min(max(x + rng.uniform(-8, 8), 8), T - 8)
                y = min(max(y + rng.uniform(-8, 8), 8), T - 8)
                pts.append((x, y))
            m = mask_of(lambda d: d.line(pts, fill=255, width=2))
            blend(img, m * w, (214, 96, 38), 0.55)
    elif theme == "ruins":
        for c in range(4):
            y0 = c * 24
            off = 0 if c % 2 == 0 else 24
            tone = 1.0 + rng.uniform(-0.04, 0.04, 3)
            for k in range(3):
                x0 = (off + k * 48) % T
                tint = 1.0 + rng.uniform(-0.05, 0.05)
                xs = [(x0 + i) % T for i in range(48)]
                img[y0:y0 + 24, xs] *= (1.0 + (tint - 1.0) * w[y0:y0 + 24, xs][..., None])
        mm = mask_of(lambda d: [d.rectangle([0, c * 24, T, c * 24 + 1], fill=255) for c in range(4)]
                     + [d.rectangle([(0 if c % 2 == 0 else 24) + k * 48, c * 24, (0 if c % 2 == 0 else 24) + k * 48 + 1, c * 24 + 23], fill=255)
                        for c in range(4) for k in range(3)])
        blend(img, mm * w, (40, 32, 24), 0.5)
    elif theme == "hell":
        for _ in range(3):
            cx, cy = int(rng.integers(8, T - 8)), int(rng.integers(8, T - 8))
            m = mask_of(lambda d: d.rectangle([cx - 1, cy - 1, cx, cy], fill=255))
            glow = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)), dtype=np.float64) / 255.0
            blend(img, glow * w, (255, 90, 30), 0.65)
            blend(img, m * w, (255, 190, 90), 0.95)
        x, y = float(rng.integers(12, T - 12)), float(rng.integers(12, T - 12))
        pts = [(x, y)]
        for _s in range(6):
            x = min(max(x + rng.uniform(-9, 9), 8), T - 8)
            y = min(max(y + rng.uniform(-9, 9), 8), T - 8)
            pts.append((x, y))
        blend(img, mask_of(lambda d: d.line(pts, fill=255, width=2)) * w, (14, 4, 4), 0.6)
    elif theme == "void":
        for _ in range(int(rng.integers(3, 6))):
            cx, cy = int(rng.integers(5, T - 5)), int(rng.integers(5, T - 5))
            m = mask_of(lambda d: d.rectangle([cx, cy, cx + 1, cy + 1], fill=255))
            blend(img, m * w, (220, 230, 255) if rng.random() < 0.7 else (150, 170, 255), float(rng.uniform(0.35, 0.9)))
    elif theme == "heaven":
        for _ in range(4):
            cx, cy = int(rng.integers(5, T - 5)), int(rng.integers(5, T - 5))
            m = mask_of(lambda d: d.rectangle([cx, cy, cx + 1, cy + 1], fill=255))
            blend(img, m * w, (255, 224, 102), 0.75)
        m = mask_of(lambda d: d.line([(0, T), (T, 0)], fill=255, width=22))
        glow = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), dtype=np.float64) / 255.0
        blend(img, glow * w, (255, 240, 200), 0.10)


THEMES = {1: "caves", 2: "crystal", 3: "bedrock", 4: "ruins", 5: "hell", 6: "void", 7: "heaven"}


def retone(rgb, w, belt_soil, ref, kc, kh, strength=1.0):
    """Сдвиг грунтового кластера тайла к цели пояса; руда (малый w) остаётся как была."""
    lab = rgb2lab(rgb)
    tl = np.empty_like(lab)
    tl[..., 0] = belt_soil[0] + (lab[..., 0] - ref[0]) * kc
    tl[..., 1] = belt_soil[1] + (lab[..., 1] - ref[1]) * kh
    tl[..., 2] = belt_soil[2] + (lab[..., 2] - ref[2]) * kh
    out = lab + (w * strength)[..., None] * (tl - lab)
    return lab2rgb(out)


# ── стены-фоны (бесшовные, 96x96, тёмные) ─────────────────────────────────

def tile_noise(rng, cells, amp):
    g = rng.random((cells, cells))
    u = np.arange(T) * cells / T
    i0 = np.floor(u).astype(int)
    f = u - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    i0 = i0 % cells
    a = g[np.ix_(i0, i0)] * (1 - f)[None, :] * (1 - f)[:, None]
    b = g[np.ix_(i0, i1)] * f[None, :] * (1 - f)[:, None]
    c = g[np.ix_(i1, i0)] * (1 - f)[None, :] * f[:, None]
    d = g[np.ix_(i1, i1)] * f[None, :] * f[:, None]
    return (a + b + c + d - 0.5) * amp


def wrap_canvas():
    im = Image.new("RGB", (T * 3, T * 3))
    return im, ImageDraw.Draw(im)


def crop_center(im):
    return np.array(im.crop((T, T, 2 * T, 2 * T)), dtype=np.float64)


def paint_wall(name):
    rng = rng_for("wall", name)
    base_cols = {
        "roots": (34, 25, 19), "caves": (26, 29, 27), "crystal": (27, 20, 40), "bedrock": (34, 22, 20),
        "ruins": (42, 36, 28), "hell": (32, 13, 13), "void": (9, 10, 22), "heaven": (36, 33, 52),
    }
    base = np.array(base_cols[name], dtype=np.float64)
    n1 = tile_noise(rng, 6, 0.34)
    n2 = tile_noise(rng, 12, 0.16)
    img = base[None, None, :] * (1.0 + (n1 + n2)[..., None])
    canvas = Image.fromarray(np.clip(np.tile(img, (3, 3, 1)), 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(canvas)

    def at(fn):
        for ox in (0, 1, 2):
            for oy in (0, 1, 2):
                fn(ox * T, oy * T)

    if name == "roots":
        for _ in range(7):
            x0 = float(rng.uniform(0, T))
            amp, ph, fr = rng.uniform(3, 8), rng.uniform(0, 6.28), int(rng.integers(1, 3))
            wd = int(rng.integers(2, 4))
            col = (80 + int(rng.integers(0, 16)), 56 + int(rng.integers(0, 12)), 36)
            pts = [(x0 + amp * math.sin(ph + fr * math.tau * y / T), y) for y in range(0, T + 1, 4)]
            def strand(ox, oy, pts=pts, wd=wd, col=col):
                d.line([(x + ox, y + oy) for x, y in pts], fill=col, width=wd)
                d.line([(x + ox + 1, y + oy) for x, y in pts], fill=(col[0] - 22, col[1] - 16, col[2] - 10), width=1)
            at(strand)
            # боковые отростки
            for _k in range(int(rng.integers(2, 5))):
                yy = int(rng.integers(6, T - 6))
                xx = x0 + amp * math.sin(ph + fr * math.tau * yy / T)
                dx = rng.choice([-1, 1]) * rng.uniform(6, 14)
                def twig(ox, oy, xx=xx, yy=yy, dx=dx, col=col):
                    d.line([(xx + ox, yy + oy), (xx + dx * 0.5 + ox, yy + 4 + oy), (xx + dx + ox, yy + 9 + oy)], fill=col, width=1)
                at(twig)
        for _ in range(5):
            x, y = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            pts = [(x, y)]
            for _s in range(6):
                x += rng.uniform(-7, 7)
                y += rng.uniform(3, 9)
                pts.append((x, y))
            at(lambda ox, oy, pts=pts: d.line([(a + ox, b + oy) for a, b in pts], fill=(14, 10, 8), width=1))
    elif name == "caves":
        # сталактиты-силуэты и потёки
        for _ in range(9):
            cx = float(rng.uniform(0, T))
            top = float(rng.uniform(0, T))
            ln = float(rng.uniform(10, 30))
            wd = float(rng.uniform(3, 6))
            at(lambda ox, oy, cx=cx, top=top, ln=ln, wd=wd: d.polygon(
                [(cx - wd + ox, top + oy), (cx + wd + ox, top + oy), (cx + ox, top + ln + oy)], fill=(18, 21, 20)))
        for _ in range(14):
            x = int(rng.integers(0, T))
            y0 = int(rng.integers(0, T))
            ln = int(rng.integers(8, 28))
            at(lambda ox, oy, x=x, y0=y0, ln=ln: d.line([(x + ox, y0 + oy), (x + ox, y0 + ln + oy)], fill=(52, 60, 58), width=1))
        for _ in range(10):
            x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
            at(lambda ox, oy, x=x, y=y: d.point((x + ox, y + oy), fill=(40, 78, 52)))
    elif name == "crystal":
        for _ in range(7):
            cx, cy = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            h, w_ = float(rng.uniform(14, 28)), float(rng.uniform(4, 8))
            tilt = float(rng.uniform(-6, 6))
            pts = [(cx + tilt, cy - h), (cx + w_, cy - h * 0.55), (cx + w_, cy), (cx - w_, cy), (cx - w_, cy - h * 0.55)]
            col = (52 + int(rng.integers(0, 14)), 38 + int(rng.integers(0, 10)), 88 + int(rng.integers(0, 24)))
            def prism(ox, oy, pts=pts, col=col, cx=cx, cy=cy, h=h, w_=w_, tilt=tilt):
                d.polygon([(a + ox, b + oy) for a, b in pts], fill=col)
                d.line([(pts[0][0] + ox, pts[0][1] + oy), (cx - w_ + ox, cy + oy)], fill=(col[0] + 70, col[1] + 55, col[2] + 90), width=1)
                d.line([(pts[0][0] + ox, pts[0][1] + oy), (cx + ox, cy + oy)], fill=(col[0] - 18, col[1] - 14, col[2] - 22), width=1)
            at(prism)
        for _ in range(8):
            x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
            at(lambda ox, oy, x=x, y=y: (d.point((x + ox, y + oy), fill=(150, 235, 230)),
                                         d.point((x + ox + 1, y + oy), fill=(80, 120, 140)),
                                         d.point((x + ox - 1, y + oy), fill=(80, 120, 140))))
    elif name == "bedrock":
        # базальтовые столбы с тёмными швами и тусклыми прожилками
        cw = T // 8
        for k in range(8):
            shade = int(rng.integers(-5, 6))
            at(lambda ox, oy, k=k, shade=shade: d.rectangle([k * cw + ox, oy, k * cw + cw - 2 + ox, T - 1 + oy],
                                                            fill=(38 + shade, 25 + shade, 22 + shade)))
            at(lambda ox, oy, k=k: d.line([(k * cw + cw - 1 + ox, oy), (k * cw + cw - 1 + ox, T + oy)], fill=(16, 10, 9), width=1))
            for yy in range(int(rng.integers(4, 14)), T, int(rng.integers(14, 24))):
                at(lambda ox, oy, k=k, yy=yy: d.line([(k * cw + ox, yy + oy), (k * cw + cw - 2 + ox, yy + 1 + oy)], fill=(20, 13, 12), width=1))
        for _ in range(3):
            x, y = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            pts = [(x, y)]
            for _s in range(6):
                x += rng.uniform(-5, 5)
                y += rng.uniform(4, 10)
                pts.append((x, y))
            at(lambda ox, oy, pts=pts: d.line([(a + ox, b + oy) for a, b in pts], fill=(120, 54, 24), width=1))
    elif name == "ruins":
        bw, bh = 24, 16
        for r in range(T // bh):
            off = 0 if r % 2 == 0 else bw // 2
            for c in range(T // bw + 1):
                x0 = c * bw - off
                shade = int(rng.integers(-5, 6))
                at(lambda ox, oy, x0=x0, r=r, shade=shade: d.rectangle(
                    [x0 + ox, r * bh + oy, x0 + bw - 2 + ox, r * bh + bh - 2 + oy], fill=(50 + shade, 43 + shade, 34 + shade)))
        # арка-ниша и глифы
        ax, ay = 48, 62
        at(lambda ox, oy: (d.pieslice([ax - 17 + ox, ay - 34 + oy, ax + 17 + ox, ay + 0 + oy], 180, 360, fill=(15, 13, 10)),
                           d.rectangle([ax - 17 + ox, ay - 17 + oy, ax + 17 + ox, T + oy], fill=(15, 13, 10)),
                           d.arc([ax - 19 + ox, ay - 36 + oy, ax + 19 + ox, ay + 2 + oy], 180, 360, fill=(78, 68, 52), width=2)))
        for _ in range(7):
            x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
            at(lambda ox, oy, x=x, y=y: (d.point((x + ox, y + oy), fill=(120, 100, 56)),
                                         d.point((x + ox + 1, y + oy + 2), fill=(120, 100, 56))))
    elif name == "hell":
        for _ in range(4):
            x, y = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            ang = float(rng.uniform(0, math.tau))
            pts = [(x, y)]
            for _s in range(16):
                ang += float(rng.uniform(-0.55, 0.55))
                x += 7.0 * math.cos(ang)
                y += 7.0 * math.sin(ang)
                pts.append((x, y))
            at(lambda ox, oy, pts=pts: d.line([(a + ox, b + oy) for a, b in pts], fill=(255, 96, 28), width=2, joint="curve"))
            at(lambda ox, oy, pts=pts: d.line([(a + ox, b + oy) for a, b in pts], fill=(255, 190, 90), width=1))
        glow = canvas.filter(ImageFilter.GaussianBlur(5))
        canvas = Image.blend(canvas, glow, 0.0)
        # свечение жил: добавляем размытую копию яркой части
        arr = np.array(canvas, dtype=np.float64)
        bright = np.clip(arr - 120, 0, 255)
        halo = np.array(Image.fromarray(bright.astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), dtype=np.float64)
        canvas = Image.fromarray(np.clip(arr + halo * 0.9, 0, 255).astype(np.uint8), "RGB")
    elif name == "void":
        for _ in range(5):
            cx, cy = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            r = float(rng.uniform(10, 22))
            col = (30 + int(rng.integers(0, 24)), 14 + int(rng.integers(0, 12)), 62 + int(rng.integers(0, 28)))
            at(lambda ox, oy, cx=cx, cy=cy, r=r, col=col: d.ellipse([cx - r + ox, cy - r * 0.6 + oy, cx + r + ox, cy + r * 0.6 + oy], fill=col))
        canvas = canvas.filter(ImageFilter.GaussianBlur(6))
        d = ImageDraw.Draw(canvas)
        for _ in range(26):
            x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
            col = (230, 236, 255) if rng.random() < 0.6 else (150, 170, 255)
            at(lambda ox, oy, x=x, y=y, col=col: d.point((x + ox, y + oy), fill=col))
        for _ in range(3):
            x, y = int(rng.integers(4, T - 4)), int(rng.integers(4, T - 4))
            at(lambda ox, oy, x=x, y=y: (d.line([(x - 2 + ox, y + oy), (x + 2 + ox, y + oy)], fill=(150, 170, 255), width=1),
                                         d.line([(x + ox, y - 2 + oy), (x + ox, y + 2 + oy)], fill=(150, 170, 255), width=1)))
    elif name == "heaven":
        for _ in range(6):
            cx, cy = float(rng.uniform(0, T)), float(rng.uniform(0, T))
            r = float(rng.uniform(10, 20))
            at(lambda ox, oy, cx=cx, cy=cy, r=r: d.ellipse([cx - r + ox, cy - r * 0.45 + oy, cx + r + ox, cy + r * 0.45 + oy], fill=(60, 56, 84)))
        canvas = canvas.filter(ImageFilter.GaussianBlur(5))
        d = ImageDraw.Draw(canvas)
        # лучи
        ray = Image.new("L", (T * 3, T * 3), 0)
        rd = ImageDraw.Draw(ray)
        for k in range(4):
            xx = int(rng.uniform(0, T))
            for ox in range(-3, 4):
                # 45 градусов: сдвиг за период ровно T, поэтому лучи бесшовны по обеим осям
                rd.polygon([(xx + ox * T, 0), (xx + 14 + ox * T, 0), (xx + 14 + 3 * T + ox * T, 3 * T), (xx + 3 * T + ox * T, 3 * T)], fill=255)
        ray = ray.filter(ImageFilter.GaussianBlur(7))
        arr = np.array(canvas, dtype=np.float64)
        arr += (np.array(ray, dtype=np.float64) / 255.0 * 38.0)[..., None] * np.array([1.0, 0.92, 0.6])
        canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
        d = ImageDraw.Draw(canvas)
        for _ in range(16):
            x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
            at(lambda ox, oy, x=x, y=y: d.point((x + ox, y + oy), fill=(255, 224, 140)))
    return crop_center(canvas)


# ── сборка ────────────────────────────────────────────────────────────────

def compose_sprite_on(bg, sprite_img, w_feather=None):
    """Спрайт (RGBA 96x96) поверх фона (float RGB)."""
    s = np.array(sprite_img, dtype=np.float64)
    a = s[..., 3:4] / 255.0
    return bg * (1 - a) + s[..., :3] * a


def main():
    biomes = json.load(open(os.path.join(ROOT, "data", "world_layers.json"), encoding="utf-8"))["biomes"]["list"]
    # перерисованная земля и камень пояса 0 пишутся в art/tiles ДО чтения (дальше всё как обычно: тон поясов, руды сверху)
    for gname, gfn in _load_override("ground_tiles", "GROUND").items():
        save_rgb(np.asarray(gfn(), dtype=np.float64), os.path.join(TILES, gname + ".png"))
    dirt = [load(os.path.join(TILES, f"dirt_{i}.png")) for i in range(1, 9)]
    ref_lab = np.mean([rgb2lab(d).reshape(-1, 3).mean(0) for d in dirt], axis=0)
    print("эталон грунта пояса 0 (Lab):", ref_lab.round(1))

    # плитки пояса 0: готовые + новые (спрайты поверх тайла земли dirt_1)
    base_tiles = {}
    for n in ATLAS_NAMES:
        p = os.path.join(TILES, n + ".png")
        if os.path.exists(p) and n not in NEW_ORES and n != "ruin_brick":
            base_tiles[n] = load(p)
    sprites = {n: np.array(fn().upscale(), dtype=np.float64) for n, fn in SPRITES.items()}
    brick0 = ruin_brick_base()

    # пояс 0: отдельные файлы только для нового (остальное уже в репозитории)
    for n in NEW_ORES:
        spr = Image.fromarray(sprites[n].astype(np.uint8), "RGBA")
        save_rgb(compose_sprite_on(dirt[0], spr), os.path.join(TILES, n + ".png"))
    save_rgb(brick0, os.path.join(TILES, "ruin_brick.png"))
    print("новые руды и кладка записаны в art/tiles/")

    # веса «грунт» для готовых тайлов (не зависят от пояса)
    weights = {}
    for n, arr in base_tiles.items():
        if n.startswith("dirt_"):
            weights[n] = np.ones((T, T))
        elif n == "stone":
            weights[n] = np.full((T, T), 0.55)
        elif n == "empty":
            weights[n] = np.ones((T, T))
        elif n == "ore_peat":
            weights[n] = np.full((T, T), 0.6)
        else:
            weights[n] = soil_weights(rgb2lab(arr), ref_lab)
    # новые руды — грунт под спрайтом: берём у dirt_1, спрайт по альфе остаётся как есть
    sprite_alpha = {n: np.array(Image.fromarray(sprites[n].astype(np.uint8), "RGBA"))[..., 3] / 255.0 for n in NEW_ORES}

    os.makedirs(DEEP, exist_ok=True)
    atlas_meta = {"cell": T, "pad": PAD, "cols": COLS, "rows": ROWS, "names": ATLAS_NAMES}
    sheet_w = COLS * (T + 2 * PAD)
    sheet_h = ROWS * (T + 2 * PAD)
    total_bytes = 0
    for belt in range(1, len(biomes)):
        b = biomes[belt]
        soil = b["soil"]
        theme = THEMES[belt]
        kc = 1.10 if theme in ("hell", "void", "bedrock") else 1.0
        kh = 1.0
        sheet = Image.new("RGB", (sheet_w, sheet_h), (0, 0, 0))
        for idx, name in enumerate(ATLAS_NAMES):
            rng = rng_for("tile", belt, name)
            if name in NEW_ORES:
                w = np.ones((T, T))
                bg = retone(dirt[0], w, soil, ref_lab, kc, kh)
                overlay(theme, bg, w, rng)
                tile = compose_sprite_on(bg, Image.fromarray(sprites[name].astype(np.uint8), "RGBA"))
            elif name == "ruin_brick":
                # кладка: лёгкий оттенок пояса, чтобы не торчала цветом из чужой палитры
                lab = rgb2lab(brick0)
                tint = np.array([lab[..., 0].mean() * 0 + soil[0] * 0.25, soil[1] * 0.5, soil[2] * 0.5])
                lab[..., 0] += (soil[0] - ref_lab[0]) * 0.35
                lab[..., 1] += (soil[1] - ref_lab[1]) * 0.25
                lab[..., 2] += (soil[2] - ref_lab[2]) * 0.25
                tile = lab2rgb(lab)
            elif name == "empty":
                lab = np.zeros((T, T, 3))
                lab[..., 0] = 3.0 + soil[0] * 0.08
                lab[..., 1] = soil[1] * 0.4
                lab[..., 2] = soil[2] * 0.4 - 3
                tile = lab2rgb(lab) + rng.normal(0, 1.0, (T, T, 1))
            else:
                arr = base_tiles[name]
                w = weights[name]
                strength = 0.5 if name == "stone" else 1.0
                tile = retone(arr, w, soil, ref_lab, kc, kh, strength)
                if name != "stone" or theme in ("hell", "void"):
                    overlay(theme, tile, w if name != "stone" else w * 0.0 + 0.3, rng)
            cx = (idx % COLS) * (T + 2 * PAD) + PAD
            cy = (idx // COLS) * (T + 2 * PAD) + PAD
            tile_img = Image.fromarray(np.clip(np.rint(tile), 0, 255).astype(np.uint8), "RGB")
            ext = Image.new("RGB", (T + 2 * PAD, T + 2 * PAD))
            ext.paste(tile_img, (PAD, PAD))
            arr = np.array(ext)
            arr[:PAD, PAD:PAD + T] = arr[PAD:PAD + 1, PAD:PAD + T]
            arr[PAD + T:, PAD:PAD + T] = arr[PAD + T - 1:PAD + T, PAD:PAD + T]
            arr[:, :PAD] = arr[:, PAD:PAD + 1]
            arr[:, PAD + T:] = arr[:, PAD + T - 1:PAD + T]
            sheet.paste(Image.fromarray(arr, "RGB"), (cx - PAD, cy - PAD))
        out = os.path.join(DEEP, f"belt_{belt}.png")
        sheet.save(out, optimize=True)
        total_bytes += os.path.getsize(out)
        print(f"пояс {belt} {b['id']:12s} -> {os.path.relpath(out, ROOT)}  {os.path.getsize(out) // 1024} КБ")
    json.dump(atlas_meta, open(os.path.join(DEEP, "atlas.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("атласы поясов, всего", total_bytes // 1024, "КБ")

    os.makedirs(ENV, exist_ok=True)
    for b in biomes:
        name = b["wall"]
        wall_over = _load_override("walls_deep", "WALLS")
        wall = np.asarray(wall_over[name](), dtype=np.float64) if name in wall_over else paint_wall(name)
        save_rgb(wall, os.path.join(ENV, f"wall_{name}.png"))
    print("стены-фоны:", ", ".join(b["wall"] for b in biomes))


if __name__ == "__main__":
    main()
