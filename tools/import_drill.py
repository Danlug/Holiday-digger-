#!/usr/bin/env python3
"""import_drill.py — нарезка авторского листа анимаций бура и бурмобиля.

Лист: четыре ряда по восемь кадров, ряды подписаны прямо на листе —
«Drill Down Work», «Drill Right Work», «Burmobile Down Work»,
«Burmobile Right Work». То есть на один инструмент приходится ДВА набора:
копка вниз и копка вбок рисуются по-разному, и рендереры выбирают лист по
паре «инструмент + направление» (см. character_view.gd и web/index.html).

Чем эта нарезка отличается от import_dig.py:

  1. Границы кадров ищутся ПО СОДЕРЖИМОМУ, а не делением 1024/8. Шаг кадров
     на листе ≈125.4 px, а не 128, и деление поровну резало бы соседей.

  2. У бурмобиля СВОЙ масштаб и СВОЙ размер кадра. Машина по ГДД п.5
     занимает 2 клетки в ширину — это 64 px, в кадр 48×48 она не влезает.
     Ужимать машину под 48 нельзя: вместе с ней ужимается герой в кабине, и
     он становится заметно мельче героя пешком.

  3. Ряды «вниз» бурят В КЛЕТКУ ПОД СОБОЙ: бур и выбитая порода уходят ниже
     линии земли. Поэтому кадр может быть ВЫШЕ 48 px — лишняя высота идёт
     вниз, под линию земли, а сама линия земли остаётся на том же месте
     кадра, что и у остальных наборов (GROUND_Y).

  4. Якорь по горизонтали — тело, а не рамка кадра. Художник ставит фигуру
     в клетке по-разному, и привязка к рамке шатает героя вбок. Берём ЦЕНТР
     МАСС верхней полосы содержимого (голова героя, купол кабины) и
     дополнительно подгоняем якоря прямой по методу наименьших квадратов:
     кадры стоят на листе с ровным шагом, всё отклонение от прямой — дрожь
     рисовальщика, а не задуманное движение. Сам якорь центром фигуры не
     является (купол сидит в корме машины), поэтому в середину кадра
     ставится середина первого кадра ряда, а дальше всё едет за якорем.

  5. МАЛЬЧИК В КАБИНЕ БУРМОБИЛЯ, БУРЯЩЕГО ВНИЗ. В ряду «Burmobile Down»
     купол кабины пустой (внутри только серая стойка-перископ), а в ряду
     «Burmobile Right» в куполе виден герой. Это огрех исходника — машина
     ведь одна и та же, — и чинится тут же, при нарезке (см.
     transplant_driver): силуэт героя вырезается из купола ряда «вбок»
     (кадр 1 — спокойная поза) и вклеивается в купол каждого кадра ряда
     «вниз», ПОД блик стекла купола (тот вырезается отдельно, по яркости, и
     накладывается поверх героя — так купол остаётся полупрозрачным, а не
     заслоняет пассажира). Делается это над сырым `sheet`, ДО background_mask
     и tone_match: пересаженный герой проходит общее приведение тона наравне
     со всем листом и не выделяется оттенком.

Запуск:  python3 tools/import_drill.py art/_source/drill_sheet.jpg
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import (ART_SCALE, BODY_H, FOOT_PAD, FRAME_H,  # noqa: E402
                        FRAME_W, TILE, shrink, tone_match)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRAMES = 8

# Фон листа — тёмно-серый (34, 42, 45), не чёрный. Поэтому порог по яркости
# здесь не годится вдвойне: он выел бы и чёрную обводку фигур, и не отличил
# бы фон от тёмных гусениц. Вычитаем фон заливкой от краёв, а «похоже на фон»
# считаем по сумме модулей отклонения от цвета фона. Допуск 36 взят с запасом
# на шум JPEG: от 24 до 60 доля фона на листе меняется всего на 3%.
BG_RGB = (34, 42, 45)
BG_TOL = 36

# Полосы рядов по вертикали. Найдены разбором связных компонент содержимого:
# между полосами лежат только подписи («1»..«8» и заголовок следующего ряда),
# ни один пиксель фигур в них не попадает. Числа записаны константами, чтобы
# нарезка была повторяемой.
#
# Заголовок «Drill Right Work» свисает хвостом буквы «g» до y=184, то есть
# на два ряда пикселей заходит в полосу второго ряда. Этот обрывок убирает
# drop_slivers: он узкий и упирается в край клетки.
BAND_DRILL_DOWN = (41, 150)
BAND_DRILL_SIDE = (183, 285)
BAND_RIG_DOWN = (317, 411)
BAND_RIG_SIDE = (458, 537)

# Кадр героя — 48×48, как у остальных наборов (import_art.FRAME_W/FRAME_H).
# Линия земли внутри кадра — там же, где у них: FRAME_H - FOOT_PAD. На этом
# держится вся привязка спрайта в рендерерах, её трогать нельзя.
GROUND_Y = FRAME_H - FOOT_PAD

# Кадр бурмобиля. Ширина: машина по ГДД п.5 — 2 клетки, 64 px, плюс поле под
# разлетающуюся породу и искры, которые художник рисует за габаритом машины.
# Высота: 44 px машины над землёй + запас сверху на буровую мачту ряда
# «вниз» (она выше корпуса) + 6 px ниже линии земли под бур, который уходит
# в клетку под машиной.
# Кадр машины крупнее героя и, как весь арт, режется в ART_SCALE раз
# подробнее логических координат (см. import_art.py).
RIG_FRAME_W = 80 * ART_SCALE
RIG_FRAME_H = 56 * ART_SCALE
RIG_GROUND_Y = 50 * ART_SCALE

# Ширина машины в клетках (ГДД п.5: бурмобиль занимает 2×1). По ней считается
# масштаб рядов бурмобиля — от полной ширины кадра 1 ряда «вбок».
RIG_WIDTH_CELLS = 2

# Высота полосы, по которой ищется якорь: голова героя / верх кабины.
# 12 px исходника — примерно треть головы (она около 34 px), то есть шапка
# волос без лица и плеч, у машины — верхушка купола. Полосу шире брать нельзя:
# с 16 px в неё начинают попадать отлетевшие камни и искры, и якорь уезжает
# за ними на десяток пикселей.
ANCHOR_BAND = 12

# Уже этого и с касанием края клетки — чужой кадр или хвост подписи, не своё.
SLIVER_W = 14

# Наборы: (полоса ряда, имя файла, ширина кадра, высота кадра, линия земли,
#          цветов в палитре)
ROWS = [
    (BAND_DRILL_DOWN, "dig_drill_down", FRAME_W, FRAME_H, GROUND_Y, 28),
    (BAND_DRILL_SIDE, "dig_drill_side", FRAME_W, FRAME_H, GROUND_Y, 28),
    (BAND_RIG_DOWN, "dig_rig_down", RIG_FRAME_W, RIG_FRAME_H, RIG_GROUND_Y, 32),
    (BAND_RIG_SIDE, "dig_rig_side", RIG_FRAME_W, RIG_FRAME_H, RIG_GROUND_Y, 32),
]

# Опорные кадры масштаба. Рост героя берётся с ряда «бур вниз», кадр 1: это
# единственная поза на листе, где герой стоит прямо, как в idle. В ряду
# «бур вбок» он в широком шаге и оттого на 6 px исходника ниже — привязываться
# к нему значило бы сделать героя с буром выше всех остальных наборов.
HERO_REF_ROW, HERO_REF_FRAME = 0, 0
RIG_REF_ROW, RIG_REF_FRAME = 3, 0


# ---------------------------------------------------------------------------
# Лист -> кадры
# ---------------------------------------------------------------------------

def background_mask(im):
    """True там, где фон. Заливка от краёв, чтобы уцелела чёрная обводка."""
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
        if (abs(r - BG_RGB[0]) + abs(g - BG_RGB[1])
                + abs(b - BG_RGB[2])) > BG_TOL:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def frame_columns(mask, w, y0, y1):
    """Границы восьми кадров ряда — по содержимому.

    Кадры на листе стоят с шагом ≈125.4 px, а не 1024/8=128, и деление поровну
    режет соседей. Считаем занятые столбцы, склеиваем их в куски и разрезаем
    ряд по семи САМЫМ ШИРОКИМ промежуткам: между кадрами промежуток ≥19 px,
    внутри кадра (порода отлетела от инструмента) — не больше 3 px.
    """
    used = [any(not mask[y * w + x] for y in range(y0, y1 + 1)) for x in range(w)]
    runs = []
    start = None
    for x in range(w):
        if used[x] and start is None:
            start = x
        elif not used[x] and start is not None:
            runs.append([start, x - 1]); start = None
    if start is not None:
        runs.append([start, w - 1])

    gaps = sorted(((runs[i + 1][0] - runs[i][1] - 1, i)
                   for i in range(len(runs) - 1)), reverse=True)
    cuts = sorted(i for _, i in gaps[:FRAMES - 1])
    out, s = [], 0
    for c in cuts:
        out.append((runs[s][0], runs[c][1])); s = c + 1
    out.append((runs[s][0], runs[-1][1]))
    if len(out) != FRAMES:
        raise SystemExit(f"ряд y={y0}..{y1}: нашлось {len(out)} кадров вместо {FRAMES}")
    return out


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


def drop_slivers(img):
    """Убрать обрезки чужого кадра и хвосты подписей.

    Связный кусок выбрасывается, если он касается левого или правого края
    клетки и при этом узкий. Широкие куски у края — свои (отвал породы),
    мелкие крошки ВНУТРИ кадра тоже свои: это разлетающаяся порода.
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


# ---------------------------------------------------------------------------
# Якорь по горизонтали
# ---------------------------------------------------------------------------

def anchor_x(img, box):
    """Центр масс верхней полосы содержимого — голова героя / верх кабины.

    Привязываться к рамке кадра нельзя: у кадров с отлетевшей породой рамка
    шире и её центр уезжает, отчего фигура ходит вбок. Голова же нарисована
    в каждом кадре и никуда не девается.

    Именно ЦЕНТР МАСС, а не середина между крайними пикселями: одна искра,
    залетевшая в полосу, уводит середину на десяток пикселей, а на центр масс
    десяток пикселей искры против сотен пикселей головы почти не влияет.
    """
    px = img.load()
    y0 = box[1]
    xs = [x for y in range(y0, min(y0 + ANCHOR_BAND, box[3]))
          for x in range(box[0], box[2]) if px[x, y][3]]
    return sum(xs) / float(len(xs))


def fit_line(values):
    """Подогнать якоря прямой (МНК) и вернуть точки прямой.

    Кадры стоят на листе ровным шагом, поэтому якоря должны ложиться на
    прямую. Отклонение от неё — дрожь рисовальщика в пределах пары пикселей
    исходника; если её не снять, готовая анимация шатает фигуру вбок на
    целый игровой пиксель.
    """
    n = len(values)
    sx = sum(range(n))
    sy = sum(values)
    sxx = sum(i * i for i in range(n))
    sxy = sum(i * v for i, v in enumerate(values))
    k = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - k * sx) / n
    return [b + k * i for i in range(n)]


# ---------------------------------------------------------------------------
# Мальчик в кабине бурмобиля, бурящего вниз (пункт 5 в шапке файла)
# ---------------------------------------------------------------------------

# Герой в куполе ряда «вбок», кадр 1 (спокойная поза, до толчков бурения) —
# источник силуэта для пересадки. Координаты — на листе, найдены разбором
# купола первого кадра (см. отчёт агента); нижняя граница нарочно не
# достаёт до синего борта кабины (там уже не купол, а корпус машины).
DRIVER_SRC_BOX = (40, 461, 99, 499)

# Полоса, где ищется купол кадра «вниз» — верх полосы BAND_RIG_DOWN, но с
# нижней границей ПОРАНЬШЕ её конца: ниже (глубже в кадр) уже блестит сам
# бур и искры породы — такой же светлый и голубоватый, как стекло купола, и
# без верхнего предела он попал бы в тот же поиск (см. _dome_bbox).
DOME_SCAN_Y = (317, 368)

# Блик стекла купола отличается от пассажира яркостью и нейтральным/голубым
# тоном: стекло светлое (усреднённый канал > GLASS_AVG_MIN) и не краснее
# своей синевы (b - r >= GLASS_BLUE_BIAS); кожа, волосы и футболка героя
# темнее и заметно теплее/синее по-другому — под эти пороги не попадают
# (см. образцы в отчёте агента).
GLASS_AVG_MIN = 128.0
GLASS_BLUE_BIAS = -15.0

# Кадры бурения (вибрация машины, 0-based 3..6, то есть кадры 4-7) —
# пассажира покачивает на пару пикселей вместе с корпусом.
SHAKE_FRAMES = (3, 4, 5, 6)
SHAKE_PX = (1, -1, 1, -1)


def _is_glass(r, g, b):
    avg = (r + g + b) / 3.0
    return avg > GLASS_AVG_MIN and (b - r) >= GLASS_BLUE_BIAS


def _cut_driver(sheet, mask, box):
    """Силуэт героя из купола: без фона листа и без блика стекла купола."""
    x0, y0, x1, y1 = box
    w = sheet.size[0]
    out = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    src, dst = sheet.load(), out.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if mask[y * w + x]:
                continue
            r, g, b = src[x, y]
            if _is_glass(r, g, b):
                continue
            dst[x - x0, y - y0] = (r, g, b, 255)
    return out


def _dome_bbox(sheet, fx0, fx1):
    """Купол ЭТОГО кадра — по протяжённости блика стекла (см. _is_glass) в
    верхней полосе DOME_SCAN_Y. Купол на листе не одного размера в каждом
    кадре (в кадре 1, на спокойной стоянке, машина ниже и купол чуть
    меньше — см. отчёт агента), поэтому вместо одной прибитой гвоздями
    рамки на весь ряд купол ищется в каждом кадре заново.
    """
    y0, y1 = DOME_SCAN_Y
    px = sheet.load()
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(fx0, fx1):
            r, g, b = px[x, y]
            if _is_glass(r, g, b):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


# Граница яркости между ровным тоном стекла купола и самим глянцевым бликом
# (белёсое пятно-отражение). _is_glass (GLASS_AVG_MIN=128) ловит ВЕСЬ купол
# целиком — он весь голубоватый и светлый, — а нам здесь нужно отдельно
# отличить пятно блика от заливки неба: если наложить поверх героя весь
# купол целиком, героя не станет видно вовсе. См. _dome_fill_color и
# _dome_glass_layer.
HIGHLIGHT_AVG_MIN = 205.0


def _dome_glass_layer(sheet, box):
    """Только блик-глянец купола ЭТОГО кадра (см. HIGHLIGHT_AVG_MIN) — яркое
    пятно-отражение, а не голубая заливка всего стекла: та ложится поверх
    героя ПОД блик (см. transplant_driver), а не вместо героя. Альфа растёт
    с яркостью — мягкий край блика, а не жёсткая маска."""
    x0, y0, x1, y1 = box
    out = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    src, dst = sheet.load(), out.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = src[x, y]
            avg = (r + g + b) / 3.0
            if avg >= HIGHLIGHT_AVG_MIN:
                a = max(0, min(255, int((avg - HIGHLIGHT_AVG_MIN) * 6)))
                dst[x - x0, y - y0] = (r, g, b, a)
    return out

# Насколько сжать рамку купола (bbox по блику) до вписанного эллипса, которым
# стирается нутро купола перед пересадкой (см. transplant_driver): рамка —
# ПРЯМОУГОЛЬНИК блика, а купол круглый, и в её углах уже тёмный ободок купола
# и фон — их закрашивать нельзя. 0.86 подобрано глазом по контрольному листу.
DOME_ELLIPSE_MARGIN = 0.86


def _dome_fill_color(sheet, box):
    """Ровный тон стекла купола (без блика) — по нему стирается нутро купола
    (перископ-стойка на пустом кадре, старый пассажир при повторном
    прогоне) перед тем, как усадить в купол героя."""
    x0, y0, x1, y1 = box
    px = sheet.load()
    rs = gs = bs = n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if _is_glass(r, g, b) and (r + g + b) / 3.0 < HIGHLIGHT_AVG_MIN:
                rs += r; gs += g; bs += b; n += 1
    if n == 0:
        return (150, 185, 195)   # запасной вариант — таким же тоном стекло на других кадрах
    return (rs // n, gs // n, bs // n)


def _fill_dome_ellipse(sheet, box, color, margin=DOME_ELLIPSE_MARGIN):
    """Закрашивает вписанный в box эллипс ровным цветом — стирает нутро
    купола (перископ-стойку, старого пассажира), не задевая тёмный ободок
    купола и фон в углах прямоугольной рамки box (см. пункт 5 в шапке)."""
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    rx, ry = (x1 - x0) / 2.0 * margin, (y1 - y0) / 2.0 * margin
    px = sheet.load()
    for y in range(y0, y1):
        ny = (y - cy) / ry
        for x in range(x0, x1):
            nx = (x - cx) / rx
            if nx * nx + ny * ny <= 1.0:
                px[x, y] = color


def transplant_driver(sheet, mask, w):
    """Пересаживает героя из купола ряда «вбок» в купол каждого кадра ряда
    «вниз» — см. пункт 5 в шапке файла. Меняет `sheet` НА МЕСТЕ; вызывающий
    обязан пересчитать mask после — пересаженные пиксели больше не фон.
    """
    driver = _cut_driver(sheet, mask, DRIVER_SRC_BOX)
    dw, dh = driver.size

    down_y0, down_y1 = BAND_RIG_DOWN
    cols = frame_columns(mask, w, down_y0, down_y1)
    px = sheet.load()
    for i, (fx0, fx1) in enumerate(cols):
        bbox = _dome_bbox(sheet, fx0, fx1)
        if bbox is None:
            continue   # блика не нашлось — оставляем купол как есть
        bx0, by0, bx1, by1 = bbox

        # герой вписывается в купол по большей стороне (сохраняя пропорции)
        # и чуть меньше него, чтобы не задевать тёмную рамку купола.
        margin_w, margin_h = 6, 4
        scale = min((bx1 - bx0 - margin_w) / dw, (by1 - by0 - margin_h) / dh, 1.0)
        tw, th = max(1, round(dw * scale)), max(1, round(dh * scale))
        scaled = driver.resize((tw, th), Image.LANCZOS) if (tw, th) != (dw, dh) else driver

        shake = SHAKE_PX[SHAKE_FRAMES.index(i)] if i in SHAKE_FRAMES else 0
        ox = bx0 + (bx1 - bx0 - tw) // 2 + shake
        # чуть ниже центра купола — плечи, а не макушка у самого стекла
        oy = by0 + (by1 - by0 - th) // 2 + max(1, round(0.08 * (by1 - by0)))

        # Блик стекла снимается ДО стирания нутра купола — так тем же
        # проходом убирается перископ-стойка пустой кабины (см. пункт 5 в
        # шапке файла), а блик потом ложится обратно поверх героя как был.
        glass = _dome_glass_layer(sheet, (bx0, by0, bx1, by1))
        fill = _dome_fill_color(sheet, (bx0, by0, bx1, by1))
        _fill_dome_ellipse(sheet, (bx0, by0, bx1, by1), fill)

        canvas = Image.new("RGBA", (bx1 - bx0, by1 - by0), (0, 0, 0, 0))
        canvas.alpha_composite(scaled, (ox - bx0, oy - by0))
        canvas.alpha_composite(glass, (0, 0))

        cpx = canvas.load()
        for y in range(by1 - by0):
            for x in range(bx1 - bx0):
                r, g, b, a = cpx[x, y]
                if a > 40:
                    px[bx0 + x, by0 + y] = (r, g, b)


# ---------------------------------------------------------------------------

def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
    mask = background_mask(sheet)

    # Купол кабины «вниз» пустой — пересаживаем туда героя из купола «вбок»
    # (см. пункт 5 в шапке файла). Меняет sheet на месте, поэтому маску фона
    # нужно посчитать заново: пересаженные пиксели больше не фон.
    print("dig_rig_down: подсаживаю героя в купол")
    transplant_driver(sheet, mask, w)
    mask = background_mask(sheet)

    # Лист снят со своей экспозицией: без приведения к эталону герой сереет,
    # стоило смениться анимации (см. import_art.tone_match).
    sheet = tone_match(sheet, mask)

    # 1. кадры всех рядов как есть
    cells = {}
    boxes = {}
    for r, ((y0, y1), name, _fw, _fh, _g, _c) in enumerate(ROWS):
        for i, (x0, x1) in enumerate(frame_columns(mask, w, y0, y1)):
            img = drop_slivers(cut(sheet, mask, (x0, y0, x1, y1)))
            bb = img.getbbox()
            if bb is None:
                raise SystemExit(f"{name}: кадр {i + 1} пустой")
            # координаты листа, а не клетки — так удобнее считать якоря
            cells[(r, i)] = img
            boxes[(r, i)] = (bb[0] + x0, bb[1] + y0, bb[2] + x0, bb[3] + y0)

    # 2. масштаб. Герой: рост в прямой позе -> BODY_H, как у idle.
    ref = boxes[(HERO_REF_ROW, HERO_REF_FRAME)]
    hero_src_h = ref[3] - ref[1]
    k_hero = BODY_H / hero_src_h
    print(f"рост героя: {hero_src_h} px исходника -> {BODY_H} px, масштаб {k_hero:.4f}")

    # Машина: полная ширина кадра 1 -> RIG_WIDTH_CELLS клеток.
    rref = boxes[(RIG_REF_ROW, RIG_REF_FRAME)]
    rig_src_w = rref[2] - rref[0]
    k_rig = RIG_WIDTH_CELLS * TILE / rig_src_w
    print(f"ширина машины: {rig_src_w} px исходника -> {RIG_WIDTH_CELLS * TILE} px, "
          f"масштаб {k_rig:.4f}")

    for r, ((y0, y1), name, fw, fh, ground_y, colors) in enumerate(ROWS):
        k = k_rig if name.startswith("dig_rig") else k_hero

        # 3. линия земли ряда — низ ПЕРВОГО кадра. Первый кадр — поза покоя:
        #    инструмент ещё не вгрызся, отвала и искр под ногами нет. Брать
        #    низ по всему ряду, как в import_dig, здесь нельзя: у бурмобиля
        #    порода летит ниже гусениц, и вся машина повисла бы над землёй.
        ground = boxes[(r, 0)][3] - 1

        # 4. якорь по телу, выровненный прямой (см. anchor_x и fit_line)
        anchors_raw = []
        for i in range(FRAMES):
            img = cells[(r, i)]
            bb = img.getbbox()
            # anchor_x считает в координатах вырезанной клетки; переводим в
            # координаты листа тем же сдвигом, каким получен бокс кадра
            cell_left = boxes[(r, i)][0] - bb[0]
            anchors_raw.append(anchor_x(img, bb) + cell_left)
        anchors = fit_line(anchors_raw)
        resid = max(abs(a - f) for a, f in zip(anchors_raw, anchors))

        # 5. якорь держит фигуру от дрожи, но сам он не центр фигуры: купол
        #    кабины сидит в корме машины, и если поставить его в середину
        #    кадра, вся машина уедет вправо и упрётся в край. Поэтому в
        #    середину кадра ставим середину ПЕРВОГО кадра (поза покоя, без
        #    отвала и искр), а дальше двигаемся вместе с якорем.
        first = boxes[(r, 0)]
        shift = (first[0] + first[2] - 1) / 2.0 - anchors[0]

        sheet_out = Image.new("RGBA", (fw * FRAMES, fh), (0, 0, 0, 0))
        clipped = []
        for i in range(FRAMES):
            img = cells[(r, i)]
            bb = img.getbbox()
            b = boxes[(r, i)]
            piece = img.crop(bb)
            tw = max(1, round(piece.size[0] * k))
            th = max(1, round(piece.size[1] * k))
            small = shrink(piece, (tw, th), colors=colors)

            dx = round(fw / 2.0 - (anchors[i] + shift - b[0]) * k)
            dy = round(ground_y - (ground + 1 - b[1]) * k)
            # alpha_composite молча срезает всё, что ушло за край холста при
            # отрицательном смещении, — сообщаем об этом вслух.
            if dx < 0 or dy < 0 or dx + tw > fw or dy + th > fh:
                clipped.append(f"кадр {i + 1}: "
                               f"слева {-dx if dx < 0 else 0}, сверху {-dy if dy < 0 else 0}, "
                               f"справа {max(0, dx + tw - fw)}, снизу {max(0, dy + th - fh)}")
            sheet_out.alpha_composite(small, (i * fw + dx, dy))

        out_dir = os.path.join(ROOT, "art", "character", "boy")
        sheet_out.save(os.path.join(out_dir, name + ".png"))
        # герой ищется рендерерами в art/character/
        sheet_out.save(os.path.join(ROOT, "art", "character", name + ".png"))
        bb = sheet_out.getbbox()
        print(f"  {name:15s} <- ряд {r + 1}, земля y={ground}, кадр {fw}×{fh}, "
              f"дрожь якоря {resid:.1f} px исходника, содержимое по высоте "
              f"{bb[3] - bb[1]} px")
        for c in clipped:
            print("    ОБРЕЗАНО " + c)
    print("готово")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_drill.py sheet.jpg")
    main(sys.argv[1])
