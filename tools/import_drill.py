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

def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
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
