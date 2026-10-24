#!/usr/bin/env python3
"""ground_tiles.py — перерисованные тайлы ЗЕМЛИ и КАМНЯ пояса 0 (ветка «ground-tiles»).

Контракт (читает tools/gen_tiles_deep.py при запуске, tools/import_tiles.py их не затирает):

  GROUND = {"dirt_1": fn, ..., "dirt_8": fn, "stone": fn}
      fn() -> numpy float64 (96, 96, 3), RGB 0..255: тайл 96x96 (сетка 32 x3), БЕСШОВНЫЙ по обоим краям (при мощении
      любой с любым соседом по сторонам не даёт шва), без рамки и без запечённой тёмной каймы.
  Земля — варианты ОДНОЙ светлоты (ГДД §15.1: разные по тону грунты в случайной раскладке дают лоскутное одеяло).

gen_tiles_deep.py пишет их в art/tiles/<имя>.png, затем собирает пояса 1..7 (тон пояса поверх, руды сверху).
После правки: python3 tools/gen_tiles_deep.py && python3 tools/gen_world_atlas.py && godot --headless --path . --import.

Как нарисовано. Рисунок живёт на той же сетке 32x32, что руды и лава (ART_SCALE 3, ближайший сосед): зерно и
камешки — настоящие пиксели игры, а не размытая фактура. Свет сверху-слева, как у руд.
  Земля: «высотная карта» (мягкие бугры, комочки-купола, ямки) освещается по наклону; свет переводится в лесенку из
  9 тонов упорядоченным дизерингом — получается зерно, а не плавный градиент. Поверх: галька трёх размеров (купол из
  4 тонов, блик, тень на грунт справа-снизу), корешок и светлая прожилка у части вариантов. Каждый вариант после
  сборки подгоняется под ОДНУ среднюю светлоту и цвет (чтобы не было лоскутов), крупные детали не пересекают край
  тайла (иначе у соседа с другим вариантом получился бы обрубок), а зерно и мягкий рельеф идут по тору.
  Камень: холодная порода из 8-9 глыб (бесшовный Вороной, чуть растянутый по горизонтали — плиты), у каждой глыбы своя
  грань по свету, лунка-шов между глыбами, блик по краю на свету, гранитная крапка, слюдяные искры, трещины, сколы.
Запуск: python3 tools/ground_tiles.py [--sheet f.png] [--paving f.png] [--check]  — контрольный лист, мощение 8x8, шов.
Это замена-заглушка уровня «программист нарисовал аккуратно», не работа художника владельца.
"""

import math
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ores_metals import lch  # noqa: E402  (лесенки по Lab — как у руд)

G = 32            # сетка пиксель-арта
S = 3             # ART_SCALE: пикселей текстуры на пиксель сетки
T = G * S

_YY, _XX = np.mgrid[0:G, 0:G]
_BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
BAYER = np.tile(_BAYER4, (G // 4, G // 4))

# Средний цвет прежней земли (Lab) — на него настроены пояса и проверка руд (контраст к грунту): держим тот же.
TARGET_LAB = (28.6, 6.8, 13.6)


def _rng(name):
    return np.random.default_rng(zlib.crc32(("ground/" + name).encode()))


def _up(img):
    """Сетка 32x32x3 -> тайл 96x96x3 (ближайший сосед)."""
    return np.repeat(np.repeat(np.asarray(img, dtype=np.float64), S, axis=0), S, axis=1)


def _tnoise(rng, cells):
    """Бесшовный шум значений: решётка cells x cells на торе, сглаженная интерполяция, значения ~ -1..1."""
    g = rng.random((cells, cells)) * 2 - 1
    u = (np.arange(G) + 0.5) * cells / G
    i0 = np.floor(u).astype(int)
    f = u - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    i0 = i0 % cells
    a = g[np.ix_(i0, i0)] * (1 - f)[None, :] * (1 - f)[:, None]
    b = g[np.ix_(i0, i1)] * f[None, :] * (1 - f)[:, None]
    c = g[np.ix_(i1, i0)] * (1 - f)[None, :] * f[:, None]
    d = g[np.ix_(i1, i1)] * f[None, :] * f[:, None]
    return a + b + c + d


def _lab(rgb):
    """RGB (...,3) 0..255 -> Lab (...,3)."""
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    wp = np.array([0.95047, 1.0, 1.08883])
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = (lin @ m.T) / wp
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def _unlab(lab):
    """Lab (...,3) -> RGB 0..255 (float)."""
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    wp = np.array([0.95047, 1.0, 1.08883])
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * wp
    lin = np.clip(xyz @ np.linalg.inv(m).T, 0, 1)
    c = np.where(lin > 0.0031308, 1.055 * lin ** (1 / 2.4) - 0.055, 12.92 * lin)
    return np.clip(c * 255, 0, 255)


def _equalize_edges(img, target):
    """Средняя светлота крайних рядов/столбцов тайла -> target (затухая за 3 пикселя вглубь): у вариантов с яркой деталью
    у края иначе по стыку с другим вариантом шла бы светлая или тёмная нитка. Рисунок не меняется, сдвигается только тон."""
    lab = _lab(img)
    L = lab[..., 0]
    d = np.zeros((G, G))
    for k, wk in enumerate((1.0, 0.55, 0.25)):
        d[k, :] += wk * (target - L[0, :].mean())
        d[G - 1 - k, :] += wk * (target - L[G - 1, :].mean())
        d[:, k] += wk * (target - L[:, 0].mean())
        d[:, G - 1 - k] += wk * (target - L[:, G - 1].mean())
    lab[..., 0] = np.clip(L + d, 0, 100)
    return _unlab(lab)


def _lit(h):
    """Освещённость по наклону высоты: свет сверху-слева (растёт к низу-право -> грань смотрит на свет)."""
    return np.roll(np.roll(h, -1, 0), -1, 1) - np.roll(np.roll(h, 1, 0), 1, 1)


def _wrap(d):
    return (d + G / 2) % G - G / 2


def _dome(cx, cy, rx, ry, rot=0.0, lump=0.18, rng=None, p=2.0):
    """Неровный овал-маска (на торе: деталь у края продолжается с другой стороны) и поле «выпуклости»."""
    x = _wrap(_XX + 0.5 - cx)
    y = _wrap(_YY + 0.5 - cy)
    c, s = math.cos(rot), math.sin(rot)
    u = (x * c + y * s) / rx
    v = (-x * s + y * c) / ry
    th = np.arctan2(v, u)
    r = np.ones_like(th)
    if rng is not None and lump > 0:
        for k in (2, 3, 4):
            r += lump * rng.uniform(0.3, 1.0) * np.cos(k * th + rng.uniform(0, math.tau)) / (k - 1)
    d = (np.abs(u) ** p + np.abs(v) ** p) ** (1.0 / p) / r
    return d <= 1.0, np.clip(1.0 - d, 0.0, 1.0), u, v


# ── ЗЕМЛЯ ────────────────────────────────────────────────────────────────────

SOIL_L = [12.0, 16.5, 21.0, 25.0, 29.0, 33.0, 37.5, 43.0, 49.0]
SOIL_C = [7.5, 10.5, 13.5, 16.0, 17.0, 16.5, 15.5, 14.0, 12.0]
SOIL_H = [40, 46, 52, 57, 61, 64, 68, 72, 77]
_CS = {"v": 1.0}   # общий множитель хромы (подбирается под средний цвет)


def _soil_ramp(dh=0.0, dc=0.0):
    return np.array([lch(SOIL_L[i], SOIL_C[i] * _CS["v"] + dc, SOIL_H[i] + dh) for i in range(9)], dtype=np.float64)


# Галька: свои лесенки из 4 тонов (тень, база, свет, блик) в Lab; тёплый песчаник, серая, ржавая, тёмная
PEBBLES = {
    "tan": [(23, 9, 62), (36, 11, 72), (49, 12, 80), (62, 9, 88)],
    "grey": [(22, 3, 72), (34, 3.5, 74), (47, 3.5, 78), (61, 3, 82)],   # тёплая серая: синяя читалась бы рудой
    "rust": [(18, 17, 38), (29, 21, 44), (40, 23, 50), (53, 18, 58)],
    "dark": [(13, 4, 60), (20, 5, 62), (28, 6, 66), (39, 6, 72)],
    "pale": [(31, 8, 78), (45, 9, 84), (59, 8, 90), (73, 6, 95)],
}


def _pebble_ramp(kind):
    return np.array([lch(*t) for t in PEBBLES[kind]], dtype=np.float64)


def _free(occ, mask, margin=1):
    """Место свободно (с зазором margin клеток от других деталей, на торе)?"""
    big = mask.copy()
    for _ in range(margin):
        big = big | np.roll(big, 1, 0) | np.roll(big, -1, 0) | np.roll(big, 1, 1) | np.roll(big, -1, 1)
    return not (occ & big).any()


def _sh(m, dx, dy):
    """Сдвиг маски на (dx, dy) по тору."""
    return np.roll(np.roll(m, dy, 0), dx, 1)


def _place(rng, tries=60):
    """Случайная позиция центра детали на торе (деталь у края продолжается с противоположной стороны: у кромок
    статистика та же, что внутри, — иначе верх/лево светлее, а низ/право темнее и сетка тайлов видна)."""
    for _ in range(tries):
        yield rng.uniform(0, G), rng.uniform(0, G)


VARIANTS = {   # состав: крупная галька, средняя, мелкая, корешок, прожилка; dirt_1 — спокойный фон под руды
    1: dict(big=0, mid=2, small=5, root=False, vein=False, calm=True),
    2: dict(big=1, mid=2, small=5, root=False, vein=True),
    3: dict(big=0, mid=3, small=6, root=True, vein=False),
    4: dict(big=1, mid=2, small=6, root=False, vein=False),
    5: dict(big=0, mid=3, small=5, root=False, vein=True),
    6: dict(big=1, mid=2, small=5, root=True, vein=False),
    7: dict(big=0, mid=3, small=7, root=False, vein=False),
    8: dict(big=1, mid=3, small=5, root=False, vein=True),
}


def _sphere_light(cx, cy, rx, ry, rot):
    """Нормаль полусферы под овалом и освещённость (свет сверху-слева): ndl в -1..1 на сетке."""
    x = _wrap(_XX + 0.5 - cx)
    y = _wrap(_YY + 0.5 - cy)
    c, s = math.cos(rot), math.sin(rot)
    u = (x * c + y * s) / rx
    vv = (-x * s + y * c) / ry
    nz = np.sqrt(np.clip(1 - u * u - vv * vv, 0, 1))
    nx = u * c - vv * s
    ny = u * s + vv * c
    return -0.55 * nx - 0.62 * ny + 0.56 * nz


def _dirt(v):
    spec = VARIANTS[v]
    rng = _rng("dirt%d" % v)
    occ = np.zeros((G, G), dtype=bool)        # занято деталями (галька, корешок): зазор для следующих
    clay = np.zeros((G, G))                   # лепка по уровням тона: комочки, ямки, тени

    def spot(w, h):
        return next(iter(_place(rng, tries=1)))

    def shape(rx, ry, lump=0.22):
        cx, cy = spot(2 * rx + 1.0, 2 * ry + 1.0)
        rot = rng.uniform(-0.6, 0.6)
        mask, _, _, _ = _dome(cx, cy, rx, ry, rot, lump=lump, rng=rng)
        return cx, cy, rot, mask

    def edge_ok(mask):
        return mask.sum() >= 4

    def cast(mask, k=1.0):
        # тень вправо-вниз от выпуклой детали
        out = np.zeros((G, G))
        for dx, dy, kk in ((1, 0, 1.0), (0, 1, 1.0), (1, 1, 0.85), (2, 1, 0.4), (1, 2, 0.4)):
            sh = _sh(mask, dx, dy)
            out = np.maximum(out, np.where(sh & ~mask, kk * k, 0.0))
        return out

    # комочки: выпуклые куски грунта — свет слева-сверху, тёмный серп справа-снизу и тень на землю
    n_clods = int(rng.integers(5, 8))
    for i in range(n_clods):
        rx = rng.uniform(2.0, 4.2) if i else rng.uniform(4.0, 5.2)
        ry = rx * rng.uniform(0.62, 0.95)
        for _try in range(10):
            cx, cy, rot, mask = shape(rx, ry, 0.28)
            if edge_ok(mask):
                break
        else:
            continue
        ndl = _sphere_light(cx, cy, rx, ry, rot)
        lvl = np.where(ndl > 0.62, 2.8, np.where(ndl > 0.20, 1.5, np.where(ndl > -0.25, 0.4, np.where(ndl > -0.55, -1.2, -2.4))))
        clay[:] += np.where(mask, lvl, 0.0) - 2.0 * cast(mask, 0.8)
    # ямки: наоборот — тень у верхнего-левого края, светлая кромка справа-снизу
    for _ in range(int(rng.integers(3, 5))):
        rx = rng.uniform(1.2, 2.3)
        ry = rx * rng.uniform(0.6, 0.95)
        for _try in range(10):
            cx, cy, rot, mask = shape(rx, ry, 0.25)
            if edge_ok(mask):
                break
        else:
            continue
        ndl = _sphere_light(cx, cy, rx, ry, rot)
        lvl = np.where(ndl > 0.35, -1.9, np.where(ndl > -0.2, -1.1, 0.9))
        clay[:] += np.where(mask, lvl, 0.0)

    # основа: спокойная пятнистость, по тору
    # (на стыке разных вариантов крупная пятнистость и даёт «клетку» — поэтому амплитуда малая, а кромка пятна неровная)
    m1 = 0.5 * _tnoise(rng, 3) + 0.3 * _tnoise(rng, 5) + 0.2 * _tnoise(rng, 8)
    ed = np.minimum(np.minimum(_XX, G - 1 - _XX), np.minimum(_YY, G - 1 - _YY)).astype(float)
    win = np.clip(ed / 7.0, 0, 1)
    win = win * win * (3 - 2 * win)       # у самого края пятнистость гаснет: тон на стыке вариантов одинаковый
    base = 3.4 + 1.6 * m1 * win
    r1 = rng.random((G, G))
    cl = _tnoise(rng, 10)
    grain = np.where(r1 > 0.97 - 0.02 * cl, 1.3, 0.0) - np.where(r1 < 0.02 + 0.015 * cl, 1.5, 0.0)
    # крошка: пятнышки по 2-3 пикселя по всему тайлу (в том числе у края), чтобы на стыках не было «тихой» полосы
    crumb = _tnoise(rng, 14) + 0.6 * _tnoise(rng, 22)
    grain += np.where(crumb > 0.5, 0.8, 0.0) - np.where(crumb < -0.56, 0.9, 0.0)
    soil_idx = base + clay + grain
    hue_t = np.clip(0.5 + 0.5 * (_tnoise(rng, 3) + 0.5 * _tnoise(rng, 6)) * win * 1.8, 0, 1)[..., None]
    dither = (rng.random((G, G)) - 0.5) * 0.4

    # галька: купол из 4 тонов, блик, обводка тёмным грунтом, тень вправо-вниз
    deco = []
    shadow = np.zeros((G, G))
    calm = spec.get("calm", False)
    kinds_all = ["tan", "grey", "rust", "pale", "dark", "tan", "grey", "rust"]
    kinds_calm = ["dark", "grey", "rust", "dark"]

    def add_pebble(kind, rx, ry):
        for _try in range(40):
            cx, cy = spot(2 * rx + 1.0, 2 * ry + 1.0)
            ang = rng.uniform(-0.5, 0.5)
            mask, _, _, _ = _dome(cx, cy, rx, ry, ang, lump=0.2, rng=rng)
            if not mask.any() or not edge_ok(mask) or not _free(occ, mask, 1):
                continue
            ramp = _pebble_ramp(kind)
            ndl = _sphere_light(cx, cy, rx, ry, ang)
            if rx * ry < 3.0:
                lvl = (ndl > 0.1).astype(int) + (ndl > 0.55)
            else:
                lvl = np.where(ndl > 0.72, 3, np.where(ndl > 0.30, 2, np.where(ndl > -0.10, 1, 0)))
            px = np.zeros((G, G, 3))
            px[mask] = ramp[np.clip(lvl, 0, 3)][mask]
            if rx * ry >= 5.0:
                hx, hy = int(round(cx - rx * 0.32 - 0.5)) % G, int(round(cy - ry * 0.35 - 0.5)) % G
                if mask[hy, hx]:
                    px[hy, hx] = np.array(lch(PEBBLES[kind][3][0] + 10, PEBBLES[kind][3][1] * 0.6, PEBBLES[kind][3][2]))
            deco.append((mask, px))
            occ[:] |= mask
            ring = np.zeros((G, G), dtype=bool)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ring |= _sh(mask, dx, dy)
            shadow[:] = np.maximum(shadow, np.where(ring & ~mask, 0.55, 0.0))
            shadow[:] = np.maximum(shadow, cast(mask, 1.0))
            return True
        return False

    kk = kinds_calm if calm else kinds_all
    for i in range(spec["big"]):
        add_pebble(kk[(v + i) % len(kk)], rng.uniform(2.6, 3.1), rng.uniform(2.0, 2.4))
    for i in range(spec["mid"]):
        add_pebble(kk[(v * 3 + i * 2) % len(kk)], rng.uniform(1.6, 2.1), rng.uniform(1.3, 1.8))
    for i in range(spec["small"]):
        add_pebble(kk[(v + i * 5) % len(kk)], rng.uniform(0.9, 1.3), rng.uniform(0.8, 1.1))
    soil_idx -= 2.3 * shadow

    # корешок: тонкая линия сверху вниз (вверх он уходит в соседний слой), со своей тенью; не лапша — один на тайл
    root_px = None
    hair_px = []
    if spec["root"]:
        for _ in range(40):
            # плавная S-кривая сверху вниз: на каждый шаг вниз смещение по x не больше клетки (линия связная)
            x0, y0 = rng.uniform(6, G - 7), int(rng.integers(2, 9))
            amp, ph = rng.uniform(1.0, 1.6), rng.uniform(0, math.tau)
            drift = rng.uniform(-0.25, 0.25)
            pts = []
            ok = True
            for k in range(int(rng.integers(10, 15))):
                px_ = int(round(x0 + drift * k + amp * math.sin(ph + 0.55 * k)))
                py_ = y0 + k
                if not (1 <= px_ < G - 1 and 1 <= py_ < G - 2) or occ[py_, px_]:
                    ok = False
                    break
                pts.append((px_, py_))
            if ok and len(pts) >= 8:
                root_px = pts
                for p_ in pts:
                    occ[p_[1], p_[0]] = True
                # два-три волоска: по 2-3 клетки вбок-вниз от разных мест корешка
                for k in rng.choice(np.arange(2, len(pts) - 2), size=2, replace=False):
                    dxh = 1 if rng.random() < 0.5 else -1
                    bx, by = pts[int(k)]
                    for _h in range(int(rng.integers(2, 4))):
                        bx += dxh
                        by += 1 if _h % 2 == 0 else 0
                        if 1 <= bx < G - 1 and 1 <= by < G - 2 and not occ[by, bx]:
                            hair_px.append((bx, by))
                            occ[by, bx] = True
                break
    vein_px = None
    if spec["vein"]:
        for _ in range(40):
            x, y = rng.uniform(4, G - 5), rng.uniform(4, G - 5)
            th = rng.uniform(0.15, 1.2) * (1 if rng.random() < 0.5 else -1)
            pts = []
            ok = True
            for k in range(int(rng.integers(6, 10))):
                px_, py_ = int(round(x + math.cos(th) * k)), int(round(y + math.sin(th) * k + 0.6 * math.sin(k * 0.9)))
                if not (1 <= px_ < G - 1 and 1 <= py_ < G - 2) or occ[py_, px_]:
                    ok = False
                    break
                pts.append((px_, py_))
            if ok:
                vein_px = pts
                break

    hue_a = _soil_ramp(-4.0, 1.5)    # красноватая глина
    hue_b = _soil_ramp(+5.0, -1.5)   # охристая пыль
    tiny_pos = [(int(rng.integers(0, G)), int(rng.integers(0, G)), rng.random() < 0.55) for _ in range(5 + (v % 3))]
    flecks = np.array(lch(*PEBBLES["pale"][1]), dtype=np.float64) if not calm else np.array(lch(36.0, 8.0, 76.0))
    pit_dark = np.array(lch(14.0, 7.0, 46.0))
    rl = np.array(lch(47.0, 15.0, 74.0))
    rd = np.array(lch(15.0, 8.0, 45.0))
    rh = np.array(lch(40.0, 12.0, 72.0))
    vl_ = np.array(lch(44.0, 9.0, 86.0))
    vd_ = np.array(lch(35.0, 11.0, 80.0))

    def render(off):
        idx = np.clip(np.rint(soil_idx + off + dither), 0, 8).astype(int)
        img = hue_a[idx] * (1 - hue_t) + hue_b[idx] * hue_t
        for mask, px in deco:
            img[mask] = px[mask]
        if root_px:
            body = set(root_px)
            for (x, y) in root_px:
                if (x, y + 1) not in body and not occ[y + 1, x]:
                    img[y + 1, x] = rd
                if (x + 1, y) not in body and not occ[y, x + 1] and (x, y + 1) in body:
                    img[y, x + 1] = rd
            for (x, y) in root_px:
                img[y, x] = rl
            for (x, y) in hair_px:
                img[y, x] = rh
        if vein_px:
            for k, (x, y) in enumerate(vein_px):
                img[y, x] = vl_ if k % 3 != 2 else vd_
        for (x, y, light) in tiny_pos:
            if not occ[y, x]:
                img[y, x] = flecks if light else pit_dark
        return _equalize_edges(img, TARGET_LAB[0])

    # одна светлота: подгоняем смещение тона по среднему L (бисекция)
    lo, hi = -2.5, 2.5
    for _ in range(14):
        mid_ = (lo + hi) / 2
        if _lab(render(mid_))[..., 0].mean() > TARGET_LAB[0]:
            hi = mid_
        else:
            lo = mid_
    return render((lo + hi) / 2)


def _dirt_tile(v):
    return _up(_dirt(v))


# ── КАМЕНЬ ───────────────────────────────────────────────────────────────────

STONE_L = [7.0, 13.0, 20.0, 28.0, 36.0, 44.0, 52.0, 61.0, 72.0]
STONE_FAMILY = [  # (хрома, оттенок): холодный сланец, нейтрально-фиолетовый гранит, синеватый
    (4.6, 262.0), (3.0, 292.0), (4.0, 248.0),
]


def _stone_ramp(c, h):
    out = []
    for i, L in enumerate(STONE_L):
        t = i / 8.0
        cc = c * (0.75 + 0.45 * math.sin(math.pi * min(1.0, t * 1.1)))
        out.append(lch(L, cc, h + (6 - 14 * t)))
    return np.array(out, dtype=np.float64)


def _stone():
    """Глыбы с гранями: шов в 1 пиксель, светлая фаска у верхнего-левого края, тёмная у нижнего-правого, плоскость
    грани делится сколом пополам, у части глыб слои, есть трещины с подсвеченной нижней кромкой и сколы-вмятины."""
    rng = _rng("stone")
    # сиды: 2 столбца x 3 ряда, ряды сдвинуты на треть столбца (на торе замыкается) — широкие плиты 16x11
    cols, rows = 2, 3
    pts = []
    for j in range(rows):
        for i in range(cols):
            x = (i + 0.5 + j / 3.0) * G / cols + rng.uniform(-2.2, 2.2)
            y = (j + 0.5) * G / rows + rng.uniform(-1.8, 1.8)
            pts.append((x % G, y % G))
    pts = np.array(pts)
    n = len(pts)
    sy = 1.2

    # кромки глыб слегка вихляют (грани рубленые, не булыжник)
    wx = 0.9 * _tnoise(rng, 4) + 0.5 * _tnoise(rng, 9)
    wy = 0.9 * _tnoise(rng, 4) + 0.5 * _tnoise(rng, 9)
    px = _XX + 0.5 + wx
    py = _YY + 0.5 + wy
    ds = []
    for (cx, cy) in pts:
        ds.append(np.sqrt(_wrap(px - cx) ** 2 + (_wrap(py - cy) * sy) ** 2))
    ds = np.stack(ds)
    order = np.argsort(ds, axis=0)
    d1 = np.take_along_axis(ds, order[:1], 0)[0]
    d2 = np.take_along_axis(ds, order[1:2], 0)[0]
    own, nei = order[0], order[1]
    edge = (d2 - d1) * 0.5

    vx = _wrap(pts[nei, 0] - pts[own, 0])
    vy = _wrap(pts[nei, 1] - pts[own, 1])
    vl = np.sqrt(vx * vx + (vy * sy) ** 2) + 1e-6
    facing = (-vx - vy * sy) / (vl * 1.414)    # >0: кромка смотрит вверх-влево, на свет

    tone = rng.uniform(-0.5, 0.5, n)
    fam = rng.integers(0, 3, n)
    ddx = _wrap(_XX + 0.5 - pts[own, 0])
    ddy = _wrap(_YY + 0.5 - pts[own, 1])
    idx = 4.1 + tone[own] - 0.05 * ddx - 0.06 * ddy               # грань светлеет к верху-слева
    idx += 0.25 * np.clip(edge, 0, 4.0) - 0.4
    # скол пополам: две плоскости одной глыбы чуть разной светлоты, граница — светлая линия
    for k in range(n):
        if rng.random() < 0.7:
            ang = rng.uniform(0.5, 1.15) * (1 if rng.random() < 0.5 else -1)
            nxv, nyv = -math.sin(ang), math.cos(ang)
            t = ddx * nxv + ddy * nyv
            c0 = rng.uniform(-2.0, 2.0)
            sgn = rng.choice([-1.0, 1.0])
            m = own == k
            idx += np.where(m & (t > c0), 0.85 * sgn, 0.0)
            idx += np.where(m & (np.abs(t - c0) < 0.55) & (edge > 1.6), 1.3, 0.0)
    # слои у двух глыб: тонкие тёмные полосы, чуть волнистые
    for k in rng.permutation(n)[:2]:
        yy0 = rng.uniform(0, 6.28)
        wave = np.sin(_YY * 1.05 + yy0 + 0.7 * np.sin(_XX * 0.3 + yy0))
        idx += np.where((own == k) & (wave > 0.86) & (edge > 1.6), -1.0, 0.0)
    # фаски и шов
    rim_in = (edge >= 0.6) & (edge < 1.6)
    idx += np.where(rim_in & (facing > 0.25), 2.1, 0.0)
    idx += np.where(rim_in & (facing < -0.25), -1.5, 0.0)
    idx += np.where((edge >= 1.6) & (edge < 2.3) & (facing > 0.25), 0.6, 0.0)
    idx = np.where(edge < 0.6, 0.0, idx)
    # сколы-вмятины: тёмная кромка и светлый свежий излом у кромки глыбы
    for _ in range(3):
        k = int(rng.integers(0, n))
        a = rng.uniform(0, math.tau)
        cx = pts[k, 0] + math.cos(a) * 4.3
        cy = pts[k, 1] + math.sin(a) * 3.2
        r = rng.uniform(1.5, 2.3)
        dd = np.sqrt(_wrap(_XX + 0.5 - cx) ** 2 + _wrap(_YY + 0.5 - cy) ** 2)
        fresh = (own == k) & (dd < r) & (edge > 0.9)
        idx += np.where(fresh, 1.9, 0.0)
        idx += np.where((own == k) & (dd >= r) & (dd < r + 1.0) & (edge > 0.9) & (_wrap(_XX + 0.5 - cx) + _wrap(_YY + 0.5 - cy) > 0), -1.4, 0.0)
    # гранитная крапка, слюда
    idx += rng.normal(0, 0.12, (G, G))
    cl = _tnoise(rng, 9)
    r1 = rng.random((G, G))
    idx += np.where((r1 > 0.96 - 0.02 * cl) & (edge > 1.3), 1.1, 0.0)
    idx -= np.where((r1 < 0.035 + 0.02 * cl) & (edge > 1.3), 1.1, 0.0)
    mica = (r1 > 0.995) & (edge > 1.6)
    dither = (rng.random((G, G)) - 0.5) * 0.3

    # трещины: от шва в глыбу, 1 px тёмная линия, нижняя кромка подсвечена
    cracks = []
    for k in rng.permutation(n)[:3]:
        x, y = pts[k]
        a = rng.uniform(0, math.tau)
        x += math.cos(a) * 5.0
        y += math.sin(a) * 3.6
        th = rng.uniform(0.35, 1.2) * rng.choice([-1, 1]) + (0 if rng.random() < 0.5 else math.pi)
        line = []
        for _s in range(int(rng.integers(7, 12))):
            th += rng.normal(0, 0.4)
            x += math.cos(th)
            y += math.sin(th)
            line.append((int(round(x)) % G, int(round(y)) % G))
        cracks.append(line)

    ramps = [_stone_ramp(*STONE_FAMILY[f]) for f in range(3)]
    own_fam = fam[own]
    spark = np.array(lch(88.0, 2.0, 250.0))

    def render(off):
        q = np.clip(np.rint(idx + off + dither), 0, 8).astype(int)
        img = np.zeros((G, G, 3))
        for f in range(3):
            m = own_fam == f
            img[m] = ramps[f][q][m]
        for line in cracks:
            ls = set(line)
            for (x, y) in line:
                img[y, x] = ramps[0][max(q[y, x] - 4, 0)]
            for (x, y) in line:
                xx, yy = (x + 1) % G, (y + 1) % G
                if (xx, yy) not in ls:
                    img[yy, xx] = ramps[0][min(q[yy, xx] + 2, 8)]
        img[mica] = spark
        return img

    lo, hi = -2.0, 2.0
    for _ in range(14):
        m_ = (lo + hi) / 2
        if _lab(render(m_))[..., 0].mean() > 40.0:
            hi = m_
        else:
            lo = m_
    return render((lo + hi) / 2)


def _stone_tile():
    return _up(_stone())


GROUND = {f"dirt_{i}": (lambda i=i: _dirt_tile(i)) for i in range(1, 9)}
GROUND["stone"] = _stone_tile


# ── проверки и листы ─────────────────────────────────────────────────────────

def seam_report():
    """Числа шва. Идеал для случайных соседей — шов неотличим от стыка двух ПРОИЗВОЛЬНЫХ рядов разных тайлов (базовая
    линия): отношение ~1.0. Плюс: средняя светлота крайних рядов у всех вариантов одна (нет светлой/тёмной нитки на стыке)
    и равна средней по тайлу (нет рамки)."""
    tiles = [np.asarray(GROUND[f"dirt_{i}"](), dtype=np.float64)[::S, ::S] for i in range(1, 9)]
    lum = [_lab(t)[..., 0] for t in tiles]
    rng = np.random.default_rng(1)
    base = np.mean([np.abs(lum[rng.integers(8)][rng.integers(G), :] - lum[rng.integers(8)][rng.integers(G), :]).mean()
                    for _ in range(3000)])
    seam_v = np.mean([np.abs(a[-1, :] - b[0, :]).mean() for a in lum for b in lum])
    seam_h = np.mean([np.abs(a[:, -1] - b[:, 0]).mean() for a in lum for b in lum])
    edges = [m for l in lum for m in (l[0].mean(), l[-1].mean(), l[:, 0].mean(), l[:, -1].mean())]
    lmeans = [l.mean() for l in lum]
    return {
        "шов по горизонтали / случайный стык": round(float(seam_h / base), 3),
        "шов по вертикали / случайный стык": round(float(seam_v / base), 3),
        "L крайних рядов, разброс по вариантам": round(float(max(edges) - min(edges)), 2),
        "L краёв - L тайла": round(float(np.mean(edges) - np.mean(lmeans)), 2),
        "разброс средней L вариантов": round(float(max(lmeans) - min(lmeans)), 3),
        "средний Lab": np.mean([_lab(t).reshape(-1, 3).mean(0) for t in tiles], axis=0).round(2),
        "Lstd вариантов": [round(float(l.std()), 2) for l in lum],
    }


def _main():
    from PIL import Image
    args = sys.argv[1:]

    def opt(name):
        return args[args.index(name) + 1] if name in args else None
    names = [f"dirt_{i}" for i in range(1, 9)] + ["stone"]
    tiles = {n: np.clip(np.rint(GROUND[n]()), 0, 255).astype(np.uint8) for n in names}
    if opt("--sheet"):
        z = 2
        sheet = Image.new("RGB", (5 * (T * z + 6) + 6, 2 * (T * z + 6) + 6), (20, 20, 20))
        for i, n in enumerate(names):
            im = Image.fromarray(tiles[n]).resize((T * z, T * z), Image.NEAREST)
            sheet.paste(im, (6 + (i % 5) * (T * z + 6), 6 + (i // 5) * (T * z + 6)))
        sheet.save(opt("--sheet"))
    if opt("--paving"):
        rng = np.random.default_rng(5)
        z = 2
        out = Image.new("RGB", (8 * T * z, 8 * T * z))
        for j in range(8):
            for i in range(8):
                n = names[int(rng.integers(0, 8))]
                out.paste(Image.fromarray(tiles[n]).resize((T * z, T * z), Image.NEAREST), (i * T * z, j * T * z))
        out.save(opt("--paving"))
    if "--check" in args:
        for k, v in seam_report().items():
            print(k, v)


if __name__ == "__main__":
    _main()
