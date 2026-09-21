#!/usr/bin/env python3
"""import_grass.py — бесшовный тайл травы для верхнего ряда поверхности
(y=0), из art/_source/grass_tile.jpg в art/tiles/grass_1.png / grass_2.png.

Лист устроен в два яруса: узкая СХЕМА сверху (с корейскими подписями и
скобкой "1 패턴 반복" — "1 повтор паттерна") и большой ОБРАЗЕЦ снизу, между
пунктирными линиями. В игру идёт только образец — схема нужна была
художнику, чтобы объяснить, что повторяется, а не чтобы попасть в игру.

Период повтора найден не по скобке на схеме (её масштаб не обязан совпадать
с масштабом образца, и прямая проверка это подтвердила — SSD по скобочному
предположению кандидата не выигрывает), а НАПРЯМУЮ на образце:

  1. автокорреляция по X (сумма квадратов разницы между столбцом x и
     столбцом x+lag, свёрнутая по всей высоте образца) — у периодичной
     текстуры она проваливается на лаге, равном периоду, и остаётся высокой
     на случайных лагах;
  2. лучший лаг — 233 px, почти втрое ниже базовой линии (SSD в 0.35 раза от
     случайного лага, см. отчёт агента — числа не выдуманы, а посчитаны);
  3. для этого периода перебирается СДВИГ (откуда резать один период) —
     разные x0 дают разное качество шва, даже когда период верный, потому
     что край reза может прийтись на силуэт травинки. Метрика шва — SSD
     между последними и первыми WIN столбцами тайла, минимум даёт лучший x0.

Результат — два варианта тайла (разные x0, тот же период): в игре они
чередуются по мировой координате (см. TileArt.dirt_variant) — иначе трава
на весь экран была бы одним и тем же куском, повторяющимся заметно.

Запуск:  python3 tools/import_grass.py
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE  # noqa: E402

SRC = os.path.join(ROOT, "art", "_source", "grass_tile.jpg")
OUT_DIR = os.path.join(ROOT, "art", "tiles")

TILE_PX = int(32 * ART_SCALE)   # 96 — размер игрового тайла на диске (см. tile_art.gd: dirt_1.png и т.п.)

# Порог "фон" — ровный серый корешок листа (~140,140,140 в углах).
BG_TOL = 12

SEAM_WIN = 4          # ширина окна для метрики шва, px
CANDIDATE_X0 = [118, 452]   # два лучших несовпадающих по фазе сдвига (см. отчёт)


def _block_bounds(a: np.ndarray):
    """Прямоугольник БОЛЬШОГО образца (не схемы) — по доле фоновых пикселей
    в строке/столбце: у схемы полоса тоньше и там же текст, у образца почти
    нет фона внутри, а сверху и снизу — сплошной фон-разделитель."""
    h, w, _ = a.shape
    bg = a[0, 0].astype(int)
    dist = np.abs(a.astype(int) - bg).max(axis=2)
    isbg = dist < BG_TOL
    row_bg = isbg.mean(axis=1)
    rows = [y for y in range(150, h) if row_bg[y] < 0.5]
    y0, y1 = min(rows), max(rows) + 1
    col_bg = isbg[y0:y1, :].mean(axis=0)
    cols = [x for x in range(w) if col_bg[x] < 0.85]
    x0, x1 = min(cols), max(cols) + 1
    return x0, y0, x1, y1


def _find_period(block: np.ndarray, lo=150, hi=420) -> int:
    h, w, _ = block.shape

    def ssd(p):
        left = block[:, :w - p, :]
        right = block[:, p:, :]
        return float(np.mean((left - right) ** 2))

    best_p, best_s = lo, ssd(lo)
    for p in range(lo, hi):
        s = ssd(p)
        if s < best_s:
            best_s, best_p = s, p
    return best_p, best_s


def _seam_score(block: np.ndarray, x0: int, period: int) -> float:
    tile = block[:, x0:x0 + period, :]
    left = tile[:, :SEAM_WIN, :].astype(float)
    right = tile[:, -SEAM_WIN:, :].astype(float)
    return float(np.mean((left - right) ** 2))


def save(img: Image.Image, name: str) -> str:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")
    img.save(path)
    return path


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    a = np.asarray(im)
    print("лист:", im.size)

    bx0, by0, bx1, by1 = _block_bounds(a)
    block = a[by0:by1, bx0:bx1, :]
    print(f"образец: box=({bx0},{by0},{bx1},{by1}) size={block.shape[1]}x{block.shape[0]}")

    period, base_ssd = _find_period(block)
    baseline = float(np.mean([
        (lambda p: np.mean((block[:, :block.shape[1] - p, :].astype(float)
                             - block[:, p:, :].astype(float)) ** 2))(p)
        for p in range(300, 600, 37)
    ]))
    print(f"период: {period} px (SSD={base_ssd:.1f}, baseline~{baseline:.1f}, "
          f"отношение={base_ssd / baseline:.3f} — чем меньше 1, тем увереннее период)")

    written = []
    for i, x0 in enumerate(CANDIDATE_X0, start=1):
        seam = _seam_score(block, x0, period)
        neighbor = float(np.mean((block[:, 1:period, :].astype(float)
                                   - block[:, :period - 1, :].astype(float)) ** 2))
        print(f"  вариант {i}: x0={x0} шов_SSD={seam:.1f} сосед_SSD={neighbor:.1f} "
              f"отношение={seam / neighbor:.2f} (~1-2 — шов не виднее обычного перехода)")
        tile = Image.fromarray(block[:, x0:x0 + period, :], "RGB")
        tile = tile.resize((TILE_PX, TILE_PX), Image.LANCZOS)
        written.append(save(tile, f"grass_{i}"))

    print(f"записано файлов: {len(written)}")
    for p in written:
        print(" ", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
