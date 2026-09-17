#!/usr/bin/env python3
"""import_walk.py — нарезка авторского листа ходьбы (16 кадров).

Лист: четыре ряда по четыре кадра, один цикл шага. Прежняя ходьба была из
четырёх кадров (tools/import_move.py, вторая группа первого ряда) — этот
лист её заменяет целиком.

Три вещи, на которых легко ошибиться именно здесь:

  1. ЦИФРЫ. Художник подписал кадры номерами 1..16 прямо на листе. По
     содержимому они неотличимы от персонажа, поэтому колонки отбираются по
     ШИРИНЕ: фигура занимает 35-53 px, цифра — 9-17. Порог 25 лежит в
     середине зазора, промахнуться нечем.

  2. ЛИНИЯ ЗЕМЛИ — ОДНА на весь лист, по самой нижней подошве из всех
     кадров. Выровняешь каждый кадр по его собственной рамке — пропадёт
     покачивание корпуса (в исходнике это 4 px) и герой поедет по полу
     как на коньках. Наоборот, взять землю из каждого кадра отдельно —
     и пол начнёт ходить под ногами.

  3. Масштаб считается по САМОМУ ВЫСОКОМУ кадру: он и есть поза, ближайшая
     к спокойной стойке, а рост в спокойной стойке — это BODY_H, тот же,
     что у idle.png. Иначе герой менял бы размер, трогаясь с места.

По горизонтали кадры сводятся по голове (import_art.head_anchor): художник
ставит фигуру в клетке по-своему, и без сведения героя шатает вбок.

Запуск:  python3 tools/import_walk.py art/_source/walk_sheet.jpg
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import (BODY_H, FOOT_PAD, FRAME_H, FRAME_W,  # noqa: E402
                        head_anchor, shrink)
from import_move import background_mask  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, "art", "character", "walk.png")

BG = (29, 25, 22)   # фон этого листа темнее, чем у листа движения
BG_TOL = 16         # обводка героя почти чёрная — до неё далеко
FIGURE_MIN_W = 25   # шире — фигура, уже — подпись с номером кадра
GAP = 2             # столбец/строка считается пустой при таком числе пикселей


def _bands(counts, gap=GAP):
    out, start = [], None
    for i, n in enumerate(counts):
        if n > gap and start is None:
            start = i
        elif n <= gap and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(counts) - 1))
    return out


def _content_counts(mask, w, box):
    """Число непрозрачных пикселей по столбцам и по строкам внутри box."""
    x0, y0, x1, y1 = box
    cols = [0] * (x1 - x0 + 1)
    rows = [0] * (y1 - y0 + 1)
    for y in range(y0, y1 + 1):
        row = y * w
        for x in range(x0, x1 + 1):
            if not mask[row + x]:
                cols[x - x0] += 1
                rows[y - y0] += 1
    return cols, rows


def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    mask = background_mask(sheet, BG, BG_TOL)

    cols_all, rows_all = _content_counts(mask, w, (0, 0, w - 1, h - 1))
    row_bands = [b for b in _bands(rows_all) if b[1] - b[0] >= 40]
    if len(row_bands) != 4:
        sys.exit(f"ожидались 4 ряда, найдено {len(row_bands)}: {row_bands}")

    boxes = []
    for r0, r1 in row_bands:
        cols, _ = _content_counts(mask, w, (0, r0, w - 1, r1))
        wide = [b for b in _bands(cols) if b[1] - b[0] + 1 >= FIGURE_MIN_W]
        if len(wide) != 4:
            sys.exit(f"в ряду {r0}-{r1} ожидались 4 фигуры, найдено {len(wide)}")
        for c0, c1 in wide:
            boxes.append((c0, r0, c1, r1))

    # Рамка содержимого каждого кадра: верх — макушка, низ — подошва.
    figs = []
    for x0, y0, x1, y1 in boxes:
        cell = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
        src, dst = sheet.load(), cell.load()
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if not mask[y * w + x]:
                    dst[x - x0, y - y0] = src[x, y] + (255,)
        bb = cell.getbbox()
        figs.append({"img": cell, "bb": bb, "x0": x0, "y0": y0})

    tallest = max(f["bb"][3] - f["bb"][1] for f in figs)
    # Всё считается ВНУТРИ КЛЕТКИ: кадры лежат в четырёх рядах, и общая на
    # лист координата подошвы означала бы, что кадры первого ряда стоят на
    # полу четвёртого. Художник ставил фигуру в клетке ровно (верх гуляет на
    # 2 px), поэтому клетка — надёжная система отсчёта.
    ground_cell = max(f["bb"][3] for f in figs)            # самая нижняя подошва
    k = BODY_H / tallest
    print(f"кадров {len(figs)}, самый высокий {tallest} px исходника -> {BODY_H} px "
          f"(масштаб {k:.4f}), подошва в клетке y={ground_cell}")

    # Якорь по голове: голова каждого кадра встаёт в середину своего кадра.
    heads = [head_anchor(f["img"], tallest)[0] for f in figs]

    out = Image.new("RGBA", (FRAME_W * len(figs), FRAME_H), (0, 0, 0, 0))
    for n, f in enumerate(figs):
        bb = f["bb"]
        piece = f["img"].crop(bb)
        small = shrink(piece, (max(1, round(piece.width * k)),
                               max(1, round(piece.height * k))))
        # x: по голове. y: от ОБЩЕЙ земли листа, поэтому покачивание корпуса
        # переносится в игру как есть, а пол под ногами стоит на месте.
        dx = n * FRAME_W + FRAME_W // 2 - round((heads[n] - bb[0]) * k)
        dy = FRAME_H - FOOT_PAD - round((ground_cell - bb[1]) * k)
        out.alpha_composite(small, (max(0, dx), max(0, dy)))

    out.save(DST)
    bottoms = sorted({FRAME_H - FOOT_PAD - round((ground_cell - f["bb"][1]) * k)
                      + round((f["bb"][3] - f["bb"][1]) * k) for f in figs})
    print(f"{os.path.relpath(DST, ROOT)}: {out.size[0]}×{out.size[1]}, "
          f"подошва в кадре y={bottoms}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         os.path.join(ROOT, "art", "_source", "walk_sheet.jpg"))
