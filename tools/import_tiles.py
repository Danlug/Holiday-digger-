#!/usr/bin/env python3
"""import_tiles.py — нарезка авторского листа тайлов в игровые 32×32.

Главная проблема этого листа: тайлы нарисованы как карточки — с тёмной
каймой по краю. Для витрины это красиво, для тайлмапа смертельно: замощённое
поле покрывается сеткой тёмных швов. Ровно на эти грабли проект уже
наступал с генератором плейсхолдеров, где направленный градиент запекал
полосу в каждый край.

Поэтому здесь два шага, которых нет в обычной нарезке:
  1. обрезка кромки — снимаем нарисованную рамку;
  2. выравнивание поля (flat-field): усреднённый по ВСЕМ тайлам профиль
     яркости показывает систематическое затемнение к краю; его делим обратно.
     Считать профиль по одному тайлу нельзя — это выест его собственный
     рисунок.

Запуск:  python3 tools/import_tiles.py art/_source/tiles_sheet.jpg
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE = 32

# Сетка листа: границы ячеек по осям, найдены по яркостному профилю и
# записаны числами, чтобы нарезка была повторяемой.
COLS = [(13, 74), (99, 156), (184, 242), (269, 327), (355, 413), (440, 497),
        (523, 585), (609, 671), (695, 754), (781, 839), (866, 927), (951, 1010)]
ROWS = [(15, 68), (106, 161), (200, 253), (296, 345), (388, 439), (482, 532)]

TRIM = 0.07           # какую долю кромки снять с каждой стороны
FLAT_STRENGTH = 1.0   # насколько полно компенсировать затемнение к краю

# Что куда идёт. Ключ — (строка, столбец) на листе, значение — имя файла в
# art/tiles. На листе есть лишние варианты и опечатки в подписях (часть
# подписана латиницей неверно), поэтому выбор сделан по русской подписи и
# по тому, как тайл выглядит.
MAP = {
    (1, 1): "stone",        # stone_base
    (2, 0): "foundation",   # concrete_base
    (3, 0): "empty",        # void_base
    # руды
    (0, 8): "ore_copper",
    (0, 10): "ore_gold",
    (1, 5): "ore_iron",
    (1, 7): "ore_silver",
    (1, 8): "ore_lead",
    (2, 8): "ore_scrap",
    (2, 10): "ore_diamond",
    (3, 5): "ore_nickel",
    (3, 6): "ore_platinum",
    (4, 0): "ore_aluminium",
    (4, 2): "ore_titanium",
    (4, 3): "ore_peat",
    (4, 5): "ore_coal",
    (4, 6): "ore_lithium",
    (4, 9): "ore_uranium",
    (4, 10): "ore_ruby",
    (5, 2): "ore_mercury",
    (5, 6): "ore_emerald",
}


# Земля: движок разбрасывает четыре варианта по миру случайно, и если взять
# четыре РАЗНЫХ грунта с листа, поле превращается в лоскутное одеяло — они
# отличаются по светлоте втрое. Поэтому берём два грунта одной светлоты
# (58 и 51 по средней яркости) и добавляем к каждому поворот на 180°:
# рисунок меняется, тон — нет. Именно поворот, а не отражение — у пары
# «тайл и его зеркало» совпадает кромка, и на стыке возникает бабочка,
# симметричный узор, который глаз ловит сразу.
DIRT_SOURCES = ((0, 5), (0, 1))


def cells(sheet):
    """Все ячейки листа, обрезанные от нарисованной кромки."""
    out = {}
    for r, (y0, y1) in enumerate(ROWS):
        for c, (x0, x1) in enumerate(COLS):
            w, h = x1 - x0 + 1, y1 - y0 + 1
            dx, dy = round(w * TRIM), round(h * TRIM)
            box = (x0 + dx, y0 + dy, x1 + 1 - dx, y1 + 1 - dy)
            img = sheet.crop(box).resize((TILE, TILE), Image.BOX)
            # пустые ячейки в конце листа пропускаем
            if sum(img.getpixel((TILE // 2, TILE // 2))) > 40:
                out[(r, c)] = img
    return out


def flat_field(tiles):
    """Систематический профиль затемнения, усреднённый по всем тайлам.

    Возвращает две таблицы множителей — по X и по Y, нормированные на
    середину. Раздельные оси, а не одна карта: кайма нарисована рамкой, и
    затемнение по горизонтали и вертикали разное (46% против 65%).
    """
    n = len(tiles)
    px = [0.0] * TILE
    py = [0.0] * TILE
    for img in tiles:
        p = img.load()
        for i in range(TILE):
            px[i] += sum(sum(p[i, j]) for j in range(TILE)) / TILE
            py[i] += sum(sum(p[j, i]) for j in range(TILE)) / TILE
    px = [v / n for v in px]
    py = [v / n for v in py]
    mid = TILE // 2
    # опора — середина: к ней приводим края
    kx = [px[mid] / v if v > 1 else 1.0 for v in px]
    ky = [py[mid] / v if v > 1 else 1.0 for v in py]
    # чрезмерное усиление на самом краю даёт шум, поэтому потолок
    kx = [min(k, 2.2) for k in kx]
    ky = [min(k, 2.2) for k in ky]
    return kx, ky


def correct(img, kx, ky, colors=24):
    out = Image.new("RGB", (TILE, TILE))
    sp, op = img.load(), out.load()
    for y in range(TILE):
        for x in range(TILE):
            k = 1.0 + (kx[x] * ky[y] - 1.0) * FLAT_STRENGTH
            r, g, b = sp[x, y]
            op[x, y] = (min(255, round(r * k)), min(255, round(g * k)),
                        min(255, round(b * k)))
    return out.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")


def seam_score(img):
    """Насколько тайл выдаёт себя швом при замощении: разница яркости между
    парой соседних столбцов/строк на стыке и внутри тайла. 1.0 — шва нет."""
    p = img.load()
    def col(i):
        return sum(sum(p[i, j]) for j in range(TILE)) / TILE
    def row(j):
        return sum(sum(p[i, j]) for i in range(TILE)) / TILE
    inner_x = sum(abs(col(i) - col(i + 1)) for i in range(1, TILE - 2)) / (TILE - 3)
    inner_y = sum(abs(row(j) - row(j + 1)) for j in range(1, TILE - 2)) / (TILE - 3)
    return (abs(col(TILE - 1) - col(0)) / max(inner_x, 1e-6),
            abs(row(TILE - 1) - row(0)) / max(inner_y, 1e-6))


def main(sheet_path):
    sheet = Image.open(sheet_path).convert("RGB")
    print("лист:", sheet.size)
    grid = cells(sheet)
    print("ячеек найдено:", len(grid))

    kx, ky = flat_field(list(grid.values()))
    print("компенсация края по X:", round(kx[0], 2), "по Y:", round(ky[0], 2))

    n = 1
    for cell in DIRT_SOURCES:
        img = correct(grid[cell], kx, ky)
        for turn in (0, 180):
            out = img if turn == 0 else img.rotate(180)
            out.save(os.path.join(ROOT, "art", "tiles", f"dirt_{n}.png"))
            print(f"  dirt_{n:<12} <- ячейка {cell[0]},{cell[1]}"
                  f"{' (поворот 180°)' if turn else ''}")
            n += 1

    worst = (0.0, "")
    for (r, c), name in sorted(MAP.items()):
        if (r, c) not in grid:
            print(f"  !! ячейка {r},{c} пуста, {name} не записан")
            continue
        img = correct(grid[(r, c)], kx, ky)
        img.save(os.path.join(ROOT, "art", "tiles", name + ".png"))
        sx, sy = seam_score(img)
        if max(sx, sy) > worst[0]:
            worst = (max(sx, sy), name)
        print(f"  {name:16s} <- ячейка {r},{c}   шов X={sx:.2f} Y={sy:.2f}")
    print(f"худший шов: {worst[1]} = {worst[0]:.2f} (1.0 — шва нет)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_tiles.py sheet.jpg")
    main(sys.argv[1])
