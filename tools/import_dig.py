#!/usr/bin/env python3
"""import_dig.py — нарезка авторского листа анимаций копки.

Лист: три ряда по восемь кадров — работа стальной киркой, лопатой и
дедовой ржавой киркой. Раньше эти анимации собирались из одной стоячей позы
(см. import_art.anim_dig): рука разбиралась на звенья и крутилась вокруг
плеча. Нарисованные кадры лучше во всём, поэтому процедурная сборка для
копки больше не нужна.

Два момента, которые здесь важнее обычной нарезки:

  1. ОБЩИЙ масштаб и ОБЩАЯ линия земли на весь лист. Кадры нарисованы
     каждый в своей позе, и если выравнивать по собственной рамке кадра,
     герой прыгает внутри клетки. Опора — рост в спокойной позе (ряд 3,
     кадр 1) и низ содержимого ряда, то есть земля под ногами.

  1а. По ГОРИЗОНТАЛИ якорь — голова (import_art.head_x_anchored), а не клетка
     листа. Художник ставил фигуру в каждой клетке по-своему: центры
     содержимого в ряду шли 87, 195, ... — не на равномерной сетке, и
     привязка к середине клетки переносила этот разнобой в игру как дрожание
     героя вбок (до 18 px при росте 40). Рамка содержимого якорем тоже не
     годится: её растягивают кирка в замахе, куча камней и разлетающаяся
     порода. Голова же есть в каждом кадре и при работе почти не ходит в
     стороны. Голова ставится в середину кадра — туда же, куда её ставит
     import_art для всех остальных наборов, поэтому герой не прыгает вбок
     при переходе с ходьбы на копку; середина кадра — ещё и ось отражения
     при развороте.

     ВАЖНО: голову ищем не по форме силуэта кадра (import_art.head_x), а по
     антропометрическому Y — земля ряда минус рост головы над ступнями из
     спокойной позы (head_x_anchored). В позе "занёс кирку над головой"
     самый верхний плотный кусок силуэта — боёк, а не голова, и head_x на
     таких кадрах ловил именно его: герой на экране скакал на 6-9 логических
     px между кадрами замаха. Торс по ходу замаха почти не смещается — сама
     голова действительно "почти не ходит в стороны", как и сказано выше,
     просто первая реализация искала её не там.

  2. Фон вычитается заливкой от краёв, а не по порогу яркости: у персонажа
     чёрная обводка, и порог выел бы её вместе с фоном.

  3. РЕЗКА ПО КОМПОНЕНТАМ, а не по сетке колонок. Кадры на листе стоят не
     вплотную — между ними есть фон, — но отлетающий инструмент иногда
     рисуется ШИРЕ своей клетки и залезает в соседнюю (например, кирка,
     которую бросает герой на кадре 8 ряда 1, начинается ещё в клетке кадра
     7). Резка по фиксированной колонке в этом случае распиливает единый
     нарисованный предмет пополам: обрезок остаётся в чужом кадре, а в своём
     кадре предмета не хватает. Вместо этого лист режется по СВЯЗНЫМ
     КОМПОНЕНТАМ переднего плана (см. cut_row_by_component): каждый кусок
     целиком достаётся тому кадру, к чьей фигуре он ближе, и вырезается по
     СВОЕЙ рамке, а не по рамке клетки — благодаря этому кадру никогда не
     нужно ужиматься под сетку. Клетка кадра по ширине от этого не меняется:
     у восьми фигур в ряду всегда находится ровно восемь достаточно крупных
     компонент (тело+рука), мелкие обрезки (пыль, осколки) — это довесок к
     ближайшей из них.

  4. РЖАВАЯ КИРКА В СТАЛЬНОМ РЯДУ. Кадры 6-8 ряда 1 (dig_pick) нарисованы с
     той же рыжей ржавой киркой, что и в ряду 3 (dig_pick_rusty), хотя ряд —
     про стальной инструмент (кадры 1-5 в нём кирка стальная). Это огрех
     исходника, не нарезки: смотри дневник в отчёте агента. Чинится тут же,
     при вырезании — see restore_steel: ржавые пиксели в кадрах 6-8 красятся
     в стальной цвет, снятый с тех же кадров 1-5 по яркости (та же тень,
     тот же блик, другой оттенок), маска вдвойне ограничена — оттенком
     ржавчины и прямоугольником вокруг головы (волосы и кожа лежат в том же
     диапазоне оттенка, что и ржавчина, и их трогать нельзя).

  5. КАДР ШИРЕ, ЧЕМ У idle/walk. Удар о землю (кадр 4 во всех трёх рядах) —
     самая широкая поза на листе: дуга замаха и разлетающаяся порода не
     помещаются в стандартные 48 логических px (см. import_art.FRAME_W) —
     alpha_composite молча срезал бы дугу и осколки по правому краю кадра.
     Ряды копки инструментом поэтому режутся в СВОЙ, более широкий кадр —
     DIG_FRAME_W (64 логических px, с запасом) — так же, как у бурмобиля
     свой RIG_FRAME_W в tools/import_drill.py. Высота и линия земли те же,
     что у остальных наборов: перегрузки по вертикали не было. Ширину кадра
     нужно завести и в scripts/player/character_view.gd — SHEET_FRAME.

Реквизит (куча земли, камни) с кадров НЕ убирается: в игре герой копает
соседний тайл, и нарисованный обломок ложится ровно на него — это та
обратная связь, которой в копке не хватало.

Запуск:  python3 tools/import_dig.py art/_source/dig_sheet.jpg
"""

import bisect
import colorsys
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import (ART_SCALE, BODY_H, FOOT_PAD, FRAME_H,  # noqa: E402
                        tone_match,
                        head_anchor, head_x_anchored, shrink)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRAMES = 8

# Кадр рядов копки инструментом — шире стандартных 48 логических px (см.
# пункт 5 в шапке файла): удар о землю (кадр 4) не помещается в 48 px, дуга
# замаха и осколки обрезались бы правым краем кадра. Высота и линия земли —
# те же, что у остальных наборов (FRAME_H, FOOT_PAD из import_art).
DIG_FRAME_W = int(64 * ART_SCALE)

# Полосы рядов на листе: подписи «1-8» и заголовки в них не попадают.
ROWS = [
    ((30, 177), "dig_pick"),         # стальная кирка
    ((206, 338), "dig_shovel"),      # лопата
    ((357, 504), "dig_pick_rusty"),  # ржавая кирка деда
]

# Спокойная поза, по которой берётся рост: ряд 3, кадр 1.
REF = (2, 0)


def background_mask(im):
    """True там, где фон. Заливка от краёв: чёрная обводка персонажа цела."""
    px = im.load()
    w, h = im.size
    lim = 110

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
        if r + g + b > lim:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def _row_bg_color(im, y0, y1):
    """Образец цвета фона ЭТОГО ряда — угол листа внутри его полосы.

    Экспозиция на листе слегка гуляет по высоте (см. import_art.tone_match),
    поэтому усреднённый фон всего листа для одного ряда неточен — берём
    только левый и правый край в полосе самого ряда, где фигур не бывает.
    """
    px = im.load()
    w = im.size[0]
    samples = [px[x, y] for x in (list(range(2, 10)) + list(range(w - 10, w - 2)))
               for y in range(y0, min(y0 + 8, y1 + 1))]
    n = len(samples)
    return (sum(s[0] for s in samples) / n,
            sum(s[1] for s in samples) / n,
            sum(s[2] for s in samples) / n)


POCKET_TOL = 20     # допуск по цвету от образца фона ряда
POCKET_MIN_SIZE = 15  # мельче — шум JPEG или зрачок/деталь, не щель


def fill_enclosed_pockets(im, mask, y0, y1, tol=POCKET_TOL, min_size=POCKET_MIN_SIZE):
    """Дозаливает фоном щели силуэта, не достающиеся до края листа.

    background_mask находит фон заливкой ОТ КРАЁВ ЛИСТА: щель между поднятой
    рукой и головой (или между черенком и телом) со всех сторон обведена
    фигурой, и заливка до неё не доходит. cut() тогда красит такую щель
    исходным (тёмным) цветом фона как непрозрачный кусок — на кадре
    появляется сплошное пятно там, где должен просвечивать вычтенный фон
    (см. кадр 6 dig_pick_rusty).

    Щель находится по БЛИЗОСТИ ЦВЕТА к образцу фона этого ряда, а не по
    яркости: чёрная обводка персонажа темнее фона и в допуск не попадает,
    даже если общий порог яркости их не различил бы. Порог по размеру
    компоненты (min_size) бережёт зрачки и мелкие детали той же темноты —
    щель в фигуре всегда крупнее одного-двух пикселей.
    """
    bg = _row_bg_color(im, y0, y1)
    px = im.load()
    w = im.size[0]

    def close(p):
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) <= tol

    h = y1 - y0 + 1
    seen = bytearray(w * h)
    for y in range(y0, y1 + 1):
        for x in range(w):
            i = y * w + x
            li = (y - y0) * w + x
            if mask[i] or seen[li]:
                continue
            if not close(px[x, y]):
                seen[li] = 1
                continue
            stack = [(x, y)]
            seen[li] = 1
            comp = [i]
            while stack:
                cx, cy = stack.pop()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and y0 <= ny <= y1:
                        nli = (ny - y0) * w + nx
                        ni = ny * w + nx
                        if not seen[nli] and not mask[ni] and close(px[nx, ny]):
                            seen[nli] = 1
                            comp.append(ni)
                            stack.append((nx, ny))
            if len(comp) >= min_size:
                for ni in comp:
                    mask[ni] = 1


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


SLIVER_W = 14   # уже этого и с касанием края клетки — чужой кадр, не свой


def drop_slivers(img):
    """Убрать обрезки соседнего кадра.

    Кадры на листе стоят вплотную, и содержимое иногда переходит через
    границу клетки: у правого края появляется вертикальный обрывок чужой
    кирки. Выбрасываем связные куски, которые касаются левого или правого
    края клетки и при этом узкие. Широкие — свои (куча земли, камни у края),
    а мелкие крошки внутри кадра не трогаем: это разлетающаяся порода.
    """
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or not px[sx, sy][3]:
                continue
            comp = []
            stack = [(sy, sx)]
            seen[sy * w + sx] = 1
            x0 = x1 = sx
            while stack:
                y, x = stack.pop()
                comp.append((x, y))
                if x < x0: x0 = x
                if x > x1: x1 = x
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and not seen[ny * w + nx] \
                                and px[nx, ny][3]:
                            seen[ny * w + nx] = 1
                            stack.append((ny, nx))
            if (x0 == 0 or x1 == w - 1) and (x1 - x0 + 1) < SLIVER_W:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 0)
    return img


def content_box(img):
    return img.getbbox()


# ---------------------------------------------------------------------------
# Резка по связным компонентам (пункт 3 в шапке файла)
# ---------------------------------------------------------------------------

# Компонента такого размера (в пикселях исходника) — точно фигура (тело с
# рукой и инструментом), а не мусор (пыль, осколок породы). У самой мелкой
# фигуры на листе ~4100 px, у самой мелкой пыли — не больше пары сотен:
# разрыв большой, порог можно ставить с запасом.
PRIMARY_MIN_AREA = 1500

# Запас по X слева и справа от содержимого кадра. Не влияет на то, что
# рисуется (компоненты соседних кадров всё равно не копируются — см.
# cut_row_by_component), а нужен единственно для доводки якоря головы по X в
# main(): там ищется, на сколько подпикселей сдвинуть кадр влево, чтобы
# голова легла точно на ось, и для этого должен быть запас прозрачных
# пикселей слева от содержимого. Меньше половины минимального промежутка
# между фигурами на листе (~19 px) — с большим запасом.
PAD_X = 12


def _components(mask, w, y0, y1):
    """Связные компоненты переднего плана в полосе y0..y1 по всей ширине листа.

    В отличие от background_mask (весь лист), здесь достаточно одной полосы
    ряда — компоненты разных рядов заведомо не соприкасаются. Возвращает
    список словарей {bbox, size, cx, pixels}; bbox и pixels — в координатах
    ЛИСТА, а не клетки, cx — X центра масс (см. cut_row_by_component: по
    нему компонента приписывается своему кадру).
    """
    h = y1 - y0 + 1
    seen = bytearray(w * h)
    comps = []
    for y in range(y0, y1 + 1):
        row_off = (y - y0) * w
        for x in range(w):
            i = row_off + x
            if mask[y * w + x] or seen[i]:
                continue
            stack = [(x, y)]
            seen[i] = 1
            pixels = []
            minx = maxx = x
            miny = maxy = y
            sx = 0
            while stack:
                cx, cy = stack.pop()
                pixels.append((cx, cy))
                sx += cx
                if cx < minx: minx = cx
                if cx > maxx: maxx = cx
                if cy < miny: miny = cy
                if cy > maxy: maxy = cy
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and y0 <= ny <= y1:
                        ni = (ny - y0) * w + nx
                        if not seen[ni] and not mask[ny * w + nx]:
                            seen[ni] = 1
                            stack.append((nx, ny))
            comps.append({"bbox": (minx, miny, maxx, maxy), "size": len(pixels),
                          "cx": sx / float(len(pixels)), "pixels": pixels})
    return comps


def cut_row_by_component(sheet, mask, y0, y1, frames=FRAMES,
                          primary_min_area=PRIMARY_MIN_AREA, pad_x=PAD_X):
    """Режет полосу листа на кадры по связным компонентам, а не по сетке
    колонок — так отлетающий инструмент, который рисунком шире своей клетки,
    не распиливается границей соседних кадров (см. пункт 3 в шапке файла).

    Крупные компоненты (тело с рукой) сортируются по X и становятся
    кадрами 1..frames по порядку — их на ряд всегда ровно frames. Мелкие
    компоненты (пыль, обломки породы) достаются тому кадру, чей якорь
    ближе по X. Возвращает список из `frames` картинок RGBA одной высоты
    (вся полоса y0..y1 — общая система координат для всех кадров ряда,
    на ней держится общая линия земли, см. main) и своей ширины у каждой —
    точно по своему содержимому плюс pad_x с каждой стороны.
    """
    w = sheet.size[0]
    comps = _components(mask, w, y0, y1)
    primaries = sorted((c for c in comps if c["size"] >= primary_min_area),
                        key=lambda c: c["cx"])
    if len(primaries) != frames:
        raise SystemExit(f"ряд y={y0}..{y1}: нашлось {len(primaries)} "
                          f"крупных фигур вместо {frames} — поправь "
                          f"primary_min_area или проверь лист")

    owner = {}
    for i, p in enumerate(primaries):
        owner[id(p)] = i
    for c in comps:
        if id(c) in owner:
            continue
        owner[id(c)] = min(range(frames),
                            key=lambda i: abs(c["cx"] - primaries[i]["cx"]))

    h = y1 - y0 + 1
    src = sheet.load()
    out = []
    for i in range(frames):
        pixels = [p for c in comps if owner[id(c)] == i for p in c["pixels"]]
        xs = [p[0] for p in pixels]
        bx0 = max(0, min(xs) - pad_x)
        bx1 = min(w - 1, max(xs) + pad_x)
        img = Image.new("RGBA", (bx1 - bx0 + 1, h), (0, 0, 0, 0))
        dst = img.load()
        for x, y in pixels:
            r, g, b = src[x, y]
            dst[x - bx0, y - y0] = (r, g, b, 255)
        out.append(img)
    return out


# ---------------------------------------------------------------------------
# Ржавая кирка в стальном ряду (пункт 4 в шапке файла)
# ---------------------------------------------------------------------------

# Оттенок ржавчины в градусах HSV, и минимальные насыщенность/яркость, ниже
# которых цвет уже не отличить от нейтральной тени/чёрной обводки (общей у
# обоих вариантов кирки, трогать её не нужно). Кожа и волосы лежат в том же
# диапазоне оттенка, поэтому маска ОБЯЗАТЕЛЬНО дополняется прямоугольником
# вокруг головы (см. restore_steel) — без него перекрашивались бы и они.
RUST_HUE = (6.0, 46.0)
RUST_SAT_MIN = 0.42
RUST_VAL_MIN = 0.20

# Прямоугольник исключения вокруг головы, в долях роста (ref_h): половина
# ширины и высота вниз от макушки. 0.30 роста сверху — та же доля, что
# HEAD в import_art.py отводит под голову при процедурной сборке; ширины
# берём чуть шире виска, чтобы захватить растрёпанные волосы по бокам.
HEAD_EXCLUDE_HW = 0.22
HEAD_EXCLUDE_H = 0.34


def _is_rust(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    h *= 360.0
    return RUST_HUE[0] <= h <= RUST_HUE[1] and s >= RUST_SAT_MIN and v >= RUST_VAL_MIN


def restore_steel(rusty_cells, steel_cells, ref_h):
    """Красит ржавые кадры в сталь — только инструмент, не кожу и волосы.

    Кадры 6-8 ряда dig_pick нарисованы со ржавой киркой, хотя весь ряд —
    про стальную (кадры 1-5 верны). Для каждого ржавого пикселя ищется
    стальной пиксель той же ЯРКОСТИ среди кадров 1-5 (steel_cells) — так на
    перекрашенном лезвии остаются те же блики и тени, что нарисовал
    художник, просто другого оттенка, а не заливка одним плоским цветом.

    Маска вдвойне: по оттенку (_is_rust — не трогает серую сталь и синюю
    футболку) и по прямоугольнику вокруг головы (head_anchor + HEAD_EXCLUDE_*)
    — кожа и волосы попадают в тот же диапазон оттенка, что и ржавчина, и
    без второго ограничения перекрасились бы тоже.
    """
    steel_by_val = []
    for cell in steel_cells:
        px = cell.load()
        w, h = cell.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if not a:
                    continue
                _, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                if s <= 0.12:    # само лезвие — почти нейтральный серый
                    steel_by_val.append((v, (r, g, b)))
    steel_by_val.sort(key=lambda t: t[0])
    vals = [v for v, _ in steel_by_val]

    def steel_color(v):
        i = bisect.bisect_left(vals, v)
        i = max(0, min(len(vals) - 1, i))
        return steel_by_val[i][1]

    out = []
    for cell in rusty_cells:
        cell = cell.copy()
        w, h = cell.size
        hx, hy = head_anchor(cell, ref_h)
        half_w = ref_h * HEAD_EXCLUDE_HW
        band_h = ref_h * HEAD_EXCLUDE_H
        px = cell.load()
        n_recolored = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if not a:
                    continue
                if abs(x - hx) <= half_w and hy <= y <= hy + band_h:
                    continue
                if not _is_rust(r, g, b):
                    continue
                _, _, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                px[x, y] = steel_color(v) + (a,)
                n_recolored += 1
        print(f"    ржавая кирка -> сталь: {n_recolored} px")
        out.append(cell)
    return out


def main(path):
    sheet = Image.open(path).convert("RGB")
    print("лист:", sheet.size)
    mask = background_mask(sheet)
    # Щели силуэта, не достающиеся до края листа (см. fill_enclosed_pockets),
    # тоже фон — заливаем их отдельно, по образцу цвета каждого ряда.
    for (y0, y1), _ in ROWS:
        fill_enclosed_pockets(sheet, mask, y0, y1)
    # Лист снят со своей экспозицией: без приведения к эталону герой сереет,
    # стоило смениться анимации (см. import_art.tone_match).
    sheet = tone_match(sheet, mask)

    # 1. вырезаем все 24 кадра по связным компонентам (см. пункт 3 в шапке)
    cells = {}
    for r, ((y0, y1), _) in enumerate(ROWS):
        for i, img in enumerate(cut_row_by_component(sheet, mask, y0, y1)):
            cells[(r, i)] = img

    # 2. рост в спокойной позе задаёт масштаб для ВСЕГО листа
    ref = content_box(cells[REF])
    ref_h = ref[3] - ref[1]
    k = BODY_H / ref_h
    print(f"рост в спокойной позе: {ref_h} px исходника -> {BODY_H} px, масштаб {k:.4f}")

    # 2а. ряд 1 (dig_pick): кадры 6-8 нарисованы со ржавой киркой — красим
    # инструмент в сталь, снятую с кадров 1-5 (см. пункт 4 в шапке файла).
    RUSTY_IN_STEEL_ROW = (5, 6, 7)   # кадры 6, 7, 8 (0-based)
    steel_cells = [cells[(0, i)] for i in range(FRAMES)
                   if i not in RUSTY_IN_STEEL_ROW]
    print("dig_pick: чиню ржавую кирку в кадрах 6-8")
    fixed = restore_steel([cells[(0, i)] for i in RUSTY_IN_STEEL_ROW],
                           steel_cells, ref_h)
    for i, img in zip(RUSTY_IN_STEEL_ROW, fixed):
        cells[(0, i)] = img

    # Y головы над ступнями — тоже из спокойной позы (кадр без инструмента
    # над головой, голову тут точно найдёт head_anchor). Дальше используется
    # не форма силуэта кадра, а этот антропометрический отступ от земли
    # ряда — иначе занесённая над головой кирка сама становится "головой"
    # (см. head_x_anchored и отчёт агента про скачущие анимации копки).
    _, ref_head_top = head_anchor(cells[REF], ref_h)
    head_above_ground = ref[3] - ref_head_top

    # ось кадра: середина DIG_FRAME_W. Именно она — ось отражения при
    # развороте, и на ту же долю кадра (середину) import_art ставит голову
    # во всех прочих наборах — там кадр просто уже (FRAME_W, см. пункт 5 в
    # шапке файла: удар о землю в кадр 48 px не помещается).
    axis = DIG_FRAME_W / 2.0 - 0.5

    for r, ((y0, y1), name) in enumerate(ROWS):
        # 3. земля ряда — самый низ содержимого по всем кадрам ряда
        ground = max(content_box(cells[(r, i)])[3] for i in range(FRAMES))
        sheet_out = Image.new("RGBA", (DIG_FRAME_W * FRAMES, FRAME_H), (0, 0, 0, 0))
        heads = []
        clipped = []
        # Y головы для этого ряда — земля ряда минус отступ головы над
        # ступнями из спокойной позы (см. выше). Свой на ряд, а не общий на
        # весь лист: художник мог поставить ступни на чуть разную высоту
        # клетки в разных рядах.
        row_head_top = ground - head_above_ground

        for i in range(FRAMES):
            cell = cells[(r, i)]
            b = content_box(cell)
            if b is None:
                continue
            hx = head_x_anchored(cell, row_head_top, ref_h)

            # Голову надо поставить на ось кадра, а вставлять картинку можно
            # только по целому пикселю: остаток до половины пикселя и есть
            # дрожание на единицу. Гасим его фазой нарезки — левый край куска
            # сдвигаем на 0..1/k пикселей ИСХОДНИКА (шаг исходника — это k
            # игрового пикселя, то есть треть), и берём тот сдвиг, при котором
            # голова ложится на ось точнее всего.
            best = None
            for pad in range(0, max(1, round(1.0 / k)) + 1):
                x0 = max(0, b[0] - pad)
                off = (hx - x0) * k          # голова внутри уменьшенного куска
                dx = round(axis - off)
                err = abs(axis - off - dx)
                if best is None or err < best[0]:
                    best = (err, x0, dx)
            _, x0, dx = best

            piece = cell.crop((x0, b[1], b[2], b[3]))
            tw = max(1, round(piece.size[0] * k))
            th = max(1, round(piece.size[1] * k))
            small = shrink(piece, (tw, th))

            # якорь: голова на оси кадра по X, земля ряда по Y
            dy = FRAME_H - FOOT_PAD - round((ground - b[1]) * k)
            # alpha_composite молча срезает всё, что ушло за край холста —
            # сообщаем об этом вслух (см. пункт 5 в шапке файла).
            if dx < 0 or dx + tw > DIG_FRAME_W:
                clipped.append(f"кадр {i + 1}: слева {max(0, -dx)}, "
                                f"справа {max(0, dx + tw - DIG_FRAME_W)}")
            sheet_out.alpha_composite(small, (i * DIG_FRAME_W + dx, dy))
            heads.append(dx + (hx - x0) * k)

        out = os.path.join(ROOT, "art", "character", "boy", name + ".png")
        sheet_out.save(out)
        span = max(heads) - min(heads)
        print(f"  {name:16s} <- ряд {r + 1}, земля y={ground}, кадр "
              f"{DIG_FRAME_W}×{FRAME_H}, голова гуляет на {span:.2f} px")
        for c in clipped:
            print("    ОБРЕЗАНО " + c)

    # герой ищется рендерерами в art/character/
    for _, name in ROWS:
        src = os.path.join(ROOT, "art", "character", "boy", name + ".png")
        Image.open(src).save(os.path.join(ROOT, "art", "character", name + ".png"))
    print("готово")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_dig.py sheet.jpg")
    main(sys.argv[1])
