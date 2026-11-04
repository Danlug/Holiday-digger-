#!/usr/bin/env python3
"""gen_front_lawn.py — травяная кромка перед домом: art/env/front_lawn.png.

Владелец (26.10): «хочу чтобы перед домом показывали травку, а не землю». На
огороде верхний ряд поверхности (y=0) — тайл травы (tools/import_grass.py), а у
дома этот ряд целиком занят фасадом, и под ногами героя сразу начинается
разрез земли. Кромка — невысокая полоса той же травы, которую дом рисует ПЕРЕД
своим цоколем (scripts/house/front_lawn.gd): у дома, как и на огороде, герой
стоит на фоне травы, а земля остаётся там же, где её копают.

Текстура травы берётся из самих тайлов grass_1/grass_2 (нижние строки — те же,
что у огорода над землёй), поэтому тон и рисунок совпадают; новый здесь только
верхний силуэт — пучки травинок с осветлёнными кончиками и тонкой тёмной
кромкой по краю (без полупрозрачности и сглаживания). Полоса бесшовна по X:
травинки у краёв заворачиваются на другую сторону.

Запуск:  python3 tools/gen_front_lawn.py
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE  # noqa: E402

TILES = [os.path.join(ROOT, "art", "tiles", n) for n in ("grass_1.png", "grass_2.png")]
OUT = os.path.join(ROOT, "art", "env", "front_lawn.png")

TILE_PX = int(32 * ART_SCALE)          # 96
H = int(13 * ART_SCALE)                # 39 px = 13 логических: до колена герою
BASE = int(5 * ART_SCALE)              # сплошной дёрн снизу, 5 логических
W = TILE_PX * len(TILES)               # период повтора — два тайла травы
SEED = 2610

TIP = np.array([128, 150, 104], float)   # светлый кончик — самый светлый тон тайла
RIM = np.array([30, 44, 32], float)      # тёмная кромка силуэта — тёмный тон тайла


def _texture() -> np.ndarray:
    """Нижние H строк обоих тайлов травы подряд: то же, что видно на огороде."""
    parts = []
    for p in TILES:
        a = np.asarray(Image.open(p).convert("RGB"), dtype=float)
        parts.append(a[TILE_PX - H:TILE_PX, :, :].copy())
    t = np.concatenate(parts, axis=1)
    # Последняя строка тайла — светлый серый шов исходника (край образца на
    # листе); у кромки на её месте — притенённый дёрн, трава уходит в землю.
    t[-1] = t[-2] * 0.8
    return t


def _mask(rng: np.random.Generator) -> np.ndarray:
    """Силуэт: сплошной дёрн + травинки-клинья разной высоты, бесшовно по X."""
    m = np.zeros((H, W), bool)
    m[H - BASE:, :] = True
    # Огибающая пучков: травинки не одного роста, а кочками — две гармоники
    # периода полосы, чтобы стык повторов не читался ровной гребёнкой.
    xs = np.arange(W)
    clump = (0.55 + 0.25 * np.sin(2 * np.pi * xs / W * 3 + 0.7)
             + 0.20 * np.sin(2 * np.pi * xs / W * 7 + 2.1))
    x = 0.0
    while x < W:
        cx = int(x)
        tall = clump[cx % W]
        hb = int(BASE + (H - BASE - 2) * np.clip(tall + rng.uniform(-0.35, 0.3), 0.15, 1.0))
        half = rng.integers(2, 4)                  # полуширина у основания, px
        lean = rng.integers(-3, 4)                 # наклон кончика, px
        top = H - hb
        for y in range(top, H - BASE + 1):
            t = (y - top) / max(1, (H - BASE) - top)   # 0 у кончика, 1 у дёрна
            c = cx + lean * (1.0 - t)
            w = 0.5 + half * t
            for xx in range(int(np.floor(c - w)), int(np.ceil(c + w)) + 1):
                if abs(xx - c) <= w:
                    m[y, xx % W] = True
        x += rng.uniform(2.0, 4.0)
    return m


def main() -> None:
    rng = np.random.default_rng(SEED)
    tex = _texture()
    m = _mask(rng)
    out = np.zeros((H, W, 4), float)
    out[..., :3] = tex
    out[..., 3] = np.where(m, 255, 0)

    up = np.zeros_like(m)
    up[1:, :] = m[:-1, :]
    left = np.roll(m, 1, axis=1)
    right = np.roll(m, -1, axis=1)
    top_edge = m & ~up                       # верхняя кромка каждой травинки
    side_edge = m & (~left | ~right) & ~top_edge
    # Кончик и пиксель под ним — светлее (свет сверху), бока — тёмная кромка:
    # на сером камне цоколя травинка читается отдельно, а не зелёной кашей.
    below_tip = np.zeros_like(m)
    below_tip[1:, :] = top_edge[:-1, :]
    below_tip &= m
    for sel, col, k in ((top_edge, TIP, 0.55), (below_tip, TIP, 0.25), (side_edge, RIM, 0.45)):
        out[sel, :3] = out[sel, :3] * (1 - k) + col * k

    img = Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8), "RGBA")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(f"{os.path.relpath(OUT, ROOT)}: {W}x{H} (период {W // int(ART_SCALE)} логических px, "
          f"высота {H // int(ART_SCALE)})")


if __name__ == "__main__":
    main()
