#!/usr/bin/env python3
"""import_rig_jump_fly.py — нарезка авторского листа прыжка/полёта бурмобиля.

Лист (art/_source/rig_jump_fly_sheet.jpg, 1024×312): два ряда по восемь
кадров, каждый кадр подписан номером художником прямо на листе.

Ряд 1 (кадры 1-8) — втягивание бура при прыжке: от «бур торчит» (кадр 1) до
«полностью закрытый обтекаемый корпус» (кадр 5); кадры 6-8 подписаны
«Retraction Complete (Frame 6-8 copy Frame 5)» — художник нарисовал их как
буквальные копии кадра 5, но каждый в своей клетке листа, отдельным
рисунком, а не общей заливкой, — поэтому здесь они просто вырезаются как
обычные кадры (тем же кодом, что и 1-5), без явного копирования пикселей:
результат совпадает.

Ряд 2 (кадры 9-16) — розжиг и полный ход турбины снизу: 9-11 закрытый
корпус (опоры турбины выезжают), 12 подписан «Ignition» (первая вспышка),
13-14 растущая струя, 15-16 подписаны «Full Thrust» (кадр 16 — почти копия
15, что видно и по пикселям: тот же силуэт струи с лёгкой разницей в форме
языка пламени, изображённой отдельно).

Отличия от import_drill.py/import_rig_exit.py (тот же стиль листа, тот же
приём вычитания фона и tone_match):

  1. НОМЕРА КАДРОВ НА ЛИСТЕ — ПОДПИСИ ХУДОЖНИКА ("1".."16"), НЕ 0-based
     индексы. В коде везде индексы 0-based (кадр 1 листа = индекс 0 набора
     rig_jump, кадр 9 листа = индекс 0 набора rig_fly) — как их читает
     character_view.gd (RIG_MOVE_PHASES, см. отчёт агента).

  2. ГРАНИЦЫ КАДРОВ НЕ ПЕРЕСЧИТЫВАЮТСЯ «умным» подбором самых широких
     разрывов (как frame_columns в import_drill.py): на ЭТОМ листе все
     восемь кадров каждого ряда УЖЕ разделены чистыми промежутками в полосе
     БЕЗ подписей/текста (см. ROW1_BAND/ROW2_BAND ниже) — обычный
     purun-разбор по связным диапазонам столбцов сразу даёт восемь кусков,
     без нужды выбирать N-1 самых широких разрывов из большего числа. Если
     бы лист сменили и разбор снова дал не восемь кусков — скрипт сам
     откажет (см. `_columns`), чем тихо съест кадр.

  3. ПОДПИСИ ПОД РЯДОМ 2 ЛЕЖАТ ВНУТРИ СИЛУЭТА ПЛАМЕНИ, а не под ним:
     цифры «15»/«16» нарисованы поверх широкой части полной струи (см.
     отчёт агента — при подписи «Full Thrust» пламя и цифра делят одни и
     те же пиксели, JPEG-сглаживание сливает их с самим пламенем). Отделить
     точно нельзя, поэтому нижняя граница кадров ряда 2 просто ОБЩАЯ ДЛЯ
     ВСЕХ восьми кадров (ROW2_BAND[1] = 276) — на кадрах 12/13 это ровно
     естественный пробел перед цифрой (проверено разбором пикселей), на
     14-16 отрезает лишь самый кончик языка пламени (пара пикселей на
     исходнике, то есть меньше одного игрового пикселя после уменьшения) —
     дешевле потерять кончик пламени, чем нарисовать на кадре цифру.

  4. Машина ЗАКРЫТА на обоих рядах (бур либо втягивается, либо уже спрятан)
     — единственное исключение кадр 1 (бур ещё торчит, поза сравнима с
     "рабочим" кадром drill_sheet.jpg/dig_rig_side.png), поэтому масштаб
     машины считается ТЕМ ЖЕ способом, что в import_drill.py/
     import_rig_exit.py: ширина силуэта кадра 1 (с бура остриём) -> целимся
     в RIG_WIDTH_CELLS*TILE, тот же приём, никакого сравнения пиксельных
     чисел с drill_sheet.jpg впрямую не требуется — обе нарезки используют
     одну и ту же формулу с одной и той же целью, значит масштаб машины на
     экране совпадёт.

  5. ЛИНИЯ ЗЕМЛИ ОБЩАЯ ДЛЯ ВСЕГО ЛИСТА, НЕ ПО РЯДАМ: кадр 1-8 (rig_jump) и
     кадр 9-16 (rig_fly) рисуют ОДНУ И ТУ ЖЕ машину в одном и том же
     масштабе (проверено: рост силуэта кадра 1 ряда 1 и кадра 1 ряда 2 —
     73/74 px исходника, в пределах дрожи руки художника) — поэтому оба
     листа выходят с ОДНИМ И ТЕМ ЖЕ GROUND_Y, тем же, что у dig_rig_side.png
     (см. RIG_GROUND_Y в import_drill.py) — иначе машина скакала бы по
     вертикали при переходе копка/прыжок/полёт.

Запуск:  python3 tools/import_rig_jump_fly.py art/_source/rig_jump_fly_sheet.jpg
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, TILE, shrink, tone_match  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Фон листа — тёмно-серый (45, 47, 51), собственная экспозиция ЭТОГО листа
# (см. отчёт агента: замерено по углам изображения) — не (34, 42, 45), как у
# drill_sheet.jpg/rig_exit_sheet.jpg. Приём вычитания заливкой от краёв —
# тот же, допуск 40 взят по аналогии с import_drill.py (запас на шум JPEG).
BG_RGB = (45, 47, 51)
BG_TOL = 40

FRAMES = 8

# Полосы рядов по вертикали — БЕЗ подписей "1".."16" и подписей-пояснений
# ("Retraction Complete"/"Ignition"/"Full Thrust"), найдены разбором
# профиля содержимого по строкам (см. отчёт агента):
#   ряд 1: машина y=23..103, разрыв 104-109, цифры 110-125, ещё разрыв,
#          "Retraction Complete" y~130-145;
#   ряд 2: машина+пламя y=166..276 (по кадр 14-16 пламя доходит вплотную к
#          цифре — граница общая для всех восьми кадров, см. пункт 3 в
#          шапке файла), цифры и подписи начинаются заметно позже 276.
ROW1_BAND = (0, 103)
ROW2_BAND = (150, 276)

RIG_WIDTH_CELLS = 2  # ГДД п.5 — машина 2×1, как в import_drill.py

# Кадр итогового листа. Ширина — как у dig_rig_side.png/rig_exit.png (машина
# та же, тот же масштаб, см. пункт 4 в шапке) с запасом по бокам под
# центровку кадров разной ширины (бур то торчит, то втянут). Высота и линия
# земли — ТЕ ЖЕ числа, что RIG_FRAME_H/RIG_GROUND_Y в import_drill.py: не
# копируем импорт, чтобы не тянуть его в зависимости, но должны совпасть
# буквально (см. пункт 5 в шапке) — если тут когда-то разъедется с
# dig_rig_side.png, машина скакнёт по вертикали при переходе в прыжок.
JUMP_FRAME_W = 240
JUMP_FRAME_H = 168
GROUND_Y = 150

# Кадр ряда 2 (полёт) — тот же GROUND_Y (см. пункт 5), но выше: под машину
# снизу уходит хвост реактивной струи (до ~48 px после масштабирования на
# самом длинном кадре, см. печать скрипта при запуске) — с запасом на случай,
# если лист когда-нибудь поправят и струя станет чуть длиннее.
FLY_FRAME_W = 220
FLY_FRAME_H = 220


def background_mask(im):
    px = im.load()
    w, h = im.size
    mask = bytearray(w * h)
    seen = bytearray(w * h)
    stack = []
    for x in range(w):
        stack.append((0, x)); stack.append((h - 1, x))
    for y in range(h):
        stack.append((y, 0)); stack.append((y, w - 1))
    while stack:
        y, x = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b = px[x, y]
        if (abs(r - BG_RGB[0]) + abs(g - BG_RGB[1]) + abs(b - BG_RGB[2])) > BG_TOL:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def _columns(mask, w, y0, y1):
    """Границы восьми кадров ряда — по связным диапазонам столбцов внутри
    полосы БЕЗ подписей (см. ROW1_BAND/ROW2_BAND). На этом листе, в отличие
    от drill_sheet.jpg, кадры внутри такой полосы уже разделены чистыми
    промежутками — ищем ровно восемь кусков и отказываем, если вышло не
    восемь: значит лист поменялся, и подгонять числа руками здесь нельзя.
    """
    used = [any(not mask[y * w + x] for y in range(y0, y1 + 1)) for x in range(w)]
    runs = []
    start = None
    for x in range(w):
        if used[x] and start is None:
            start = x
        elif not used[x] and start is not None:
            runs.append((start, x - 1)); start = None
    if start is not None:
        runs.append((start, w - 1))
    if len(runs) != FRAMES:
        raise SystemExit(f"полоса y={y0}..{y1}: нашлось {len(runs)} кадров вместо {FRAMES} "
                          f"(лист поменялся — числа в скрипте надо пересчитать)")
    return runs


def content_bbox(mask, w, x0, x1, y0, y1):
    xs, ys = [], []
    for y in range(y0, y1 + 1):
        row = y * w
        for x in range(x0, x1 + 1):
            if not mask[row + x]:
                xs.append(x); ys.append(y)
    if not xs:
        raise SystemExit(f"кадр x={x0}..{x1}, y={y0}..{y1}: содержимое не найдено")
    return min(xs), min(ys), max(xs), max(ys)


def cut(im, mask, box):
    x0, y0, x1, y1 = box
    w = im.size[0]
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not mask[y * w + x]:
                dst[x - x0, y - y0] = src[x, y] + (255,)
    return out


def _build_row(sheet, mask, w, band, frame_w, frame_h, out_name, k_rig):
    """Вырезает восемь кадров одного ряда в горизонтальную полосу
    frame_w×frame_h. Все кадры ряда выравниваются по СВОЕЙ ОБЩЕЙ линии
    земли — низ кадра 0 этого же ряда (тот же приём, что dig_rig_down в
    import_drill.py: верх содержимого у всех кадров ряда одинаковый, вниз
    от него растёт то, что нарисовано длиннее — драже бура или струя),
    иначе у ряда 2 (переменная длина пламени) кадры разъехались бы по
    вертикали.
    """
    y0, y1 = band
    cols = _columns(mask, w, y0, y1)
    boxes = [content_bbox(mask, w, c[0], c[1], y0, y1) for c in cols]
    ground = boxes[0][3]  # низ кадра 0 — общая линия земли ряда

    sheet_out = Image.new("RGBA", (frame_w * FRAMES, frame_h), (0, 0, 0, 0))
    clipped = []
    for i, b in enumerate(boxes):
        piece = cut(sheet, mask, b)
        tw = max(1, round(piece.size[0] * k_rig))
        th = max(1, round(piece.size[1] * k_rig))
        small = shrink(piece, (tw, th), colors=32)
        dx = round(frame_w / 2.0 - tw / 2.0)
        dy = round(GROUND_Y - (ground - b[1] + 1) * k_rig)
        if dx < 0 or dy < 0 or dx + tw > frame_w or dy + th > frame_h:
            clipped.append(f"кадр {i + 1}: слева {-dx if dx < 0 else 0}, сверху {-dy if dy < 0 else 0}, "
                            f"справа {max(0, dx + tw - frame_w)}, снизу {max(0, dy + th - frame_h)}")
        sheet_out.alpha_composite(small, (i * frame_w + dx, dy))

    out_path = os.path.join(ROOT, "art", "character", out_name + ".png")
    sheet_out.save(out_path)
    print(f"записано art/character/{out_name}.png, {sheet_out.size}, "
          f"кадр {frame_w}×{frame_h}, машина ~{round(boxes[0][2]-boxes[0][0]+1)}..."
          f"{round(max(b[2]-b[0]+1 for b in boxes))} px исходника -> масштаб {k_rig:.4f}")
    for c in clipped:
        print("  ОБРЕЗАНО " + c)
    return out_path


def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
    mask = background_mask(sheet)
    sheet = tone_match(sheet, mask)

    # Масштаб машины — ширина силуэта кадра 1 (бур ещё торчит, поза
    # сравнима с "рабочим" кадром drill_sheet.jpg, см. пункт 4 в шапке) ->
    # целимся в RIG_WIDTH_CELLS*TILE, та же формула, что в
    # import_drill.py/import_rig_exit.py.
    cols1 = _columns(mask, w, *ROW1_BAND)
    frame1_box = content_bbox(mask, w, cols1[0][0], cols1[0][1], *ROW1_BAND)
    rig_src_w = frame1_box[2] - frame1_box[0] + 1
    k_rig = RIG_WIDTH_CELLS * TILE / rig_src_w
    print(f"машина (кадр 1): {rig_src_w} px исходника -> {RIG_WIDTH_CELLS * TILE} px, "
          f"масштаб {k_rig:.4f}")

    _build_row(sheet, mask, w, ROW1_BAND, JUMP_FRAME_W, JUMP_FRAME_H, "rig_jump", k_rig)
    _build_row(sheet, mask, w, ROW2_BAND, FLY_FRAME_W, FLY_FRAME_H, "rig_fly", k_rig)
    print("готово")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_rig_jump_fly.py sheet.jpg")
    main(sys.argv[1])
