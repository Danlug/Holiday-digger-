#!/usr/bin/env python3
"""import_packs.py — нарезка авторского листа летающего снаряжения.

Лист: четыре ряда по шесть кадров, сверху вниз — четыре уровня снаряжения из
магазина, ровно в том порядке, в каком они покупаются:

  1. ранец с малым пропеллером на мачте      -> fly_1  «Ранец»
  2. ранец с большим винтом                  -> fly_2  «Улучшенный ранец»
  3. механический джетпак с выхлопом         -> fly_3  «Джетпак»
  4. двойной ракетный ранец с синим пламенем -> fly_4  «Топовый джетпак»

В каждом кадре нарисован ГЕРОЙ ЦЕЛИКОМ вместе со снаряжением — это готовая
анимация полёта, а не накладка поверх спрайта героя. Поэтому здесь ничего не
компонуется: кадр вырезается, уменьшается и кладётся в ленту как есть.

Четыре вещи, на которых здесь легко ошибиться:

  1. ФОН убирается ЗАЛИВКОЙ ОТ КРАЁВ с допуском, а не по точному цвету и не
     по порогу яркости. Фон почти чёрный (31,26,23), но это JPEG: он гуляет
     на ±5 по каналу. Порог яркости выел бы вместе с фоном чёрную обводку
     персонажа, а точный цвет оставил бы по всему листу крошку.

  2. СЕТКА ищется по содержимому. Ряды на листе разной высоты (128, 128,
     112, 108 px), кадры внутри ряда стоят неравномерно — деление 1024/6
     разрезало бы и винт, и пламя. Границы находятся по пустым строкам и
     столбцам маски фона, а строка/столбец считается пустой, если в ней не
     больше NOISE пикселей: у JPEG по краям рисунка всегда есть крошка.

  3. МАСШТАБ — ОДИН на весь лист. Лицо героя во всех 24 кадрах одной ширины
     (17..20 px, разброс в пределах шума JPEG), значит художник рисовал его
     везде в одном размере, а разная высота содержимого по рядам — это поза:
     в первых двух рядах герой стоит, в двух последних висит с вытянутыми
     ногами. Считать масштаб по каждому ряду отдельно значило бы подгонять
     позу под рост и заставить героя то худеть, то толстеть при покупке
     следующего ранца.

  4. По ВЕРТИКАЛИ кадры сводятся ПО ЛИЦУ, а не по низу содержимого: под
     ногами в третьем и четвёртом ряду нарисованы выхлоп и пламя, и низ
     содержимого — уже не подошва. Лицо находится по цвету кожи, есть в
     каждом кадре и от снаряжения не зависит. По горизонтали — тоже по лицу:
     середина кадра это ось отражения при развороте (см. character_view.gd),
     и голова должна стоять на ней, как во всех остальных наборах.

Размер кадра у каждой ленты СВОЙ и печатается в конце — большой винт и
ракеты в 48×48 не помещаются. Ужимать под них героя нельзя: он станет мельче
себя же пешком. Числа из этой печати вбиты в SHEET_FRAME в
scripts/player/character_view.gd — поменяешь лист, перенеси их туда.

Запуск:  python3 tools/import_packs.py art/_source/packs_sheet.jpg
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import BODY_H, shrink, tone_match  # noqa: E402
from import_dig import drop_slivers  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG = (31, 26, 23)   # фон листа; обводка героя темнее 20 по всем каналам
BG_TOL = 12         # JPEG гоняет фон на ±5, до обводки ещё далеко
NOISE = 3           # столько пикселей в строке/столбце — ещё не рисунок
MIN_BAND = 16       # полоса уже этой — крошка, а не ряд/кадр

ROWS = 4
FRAMES = 6
OUT = ["fly_1", "fly_2", "fly_3", "fly_4"]

# Ряд, по которому берётся рост. Первый: герой стоит на ногах, над головой
# только тонкая мачта пропеллера. В остальных рядах либо диск винта прямо
# над макушкой, либо поза висящая — роста по ним не измерить.
REF_ROW = 0

# Запас вокруг содержимого ленты, в игровых пикселях. Один пиксель на
# случай, если при округлении укладки кадр вылезет за рамку.
PAD = 1


# ---------------------------------------------------------------------------
# Лист -> клетки
# ---------------------------------------------------------------------------

def background_mask(im):
    """True там, где фон. Заливка от краёв.

    Своя, а не import_art.background_mask: та настроена на светлый лист
    персонажей (217/194) и на этом тёмном листе не зацепится ни за что.
    """
    px = im.load()
    w, h = im.size

    def bg_like(p):
        return max(abs(p[i] - BG[i]) for i in range(3)) <= BG_TOL

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
        if not bg_like(px[x, y]):
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def bands(counts):
    """Полосы, где что-то нарисовано: [(начало, конец), ...]."""
    out = []
    start = None
    for i, c in enumerate(counts):
        if c > NOISE and start is None:
            start = i
        elif c <= NOISE and start is not None:
            out.append((start, i - 1)); start = None
    if start is not None:
        out.append((start, len(counts) - 1))
    return [b for b in out if b[1] - b[0] + 1 >= MIN_BAND]


def grid(mask, size):
    """Сетка листа по содержимому: [[(x0, x1), ...] x FRAMES] x ROWS + полосы."""
    w, h = size
    rows = bands([sum(1 for x in range(w) if not mask[y * w + x]) for y in range(h)])
    if len(rows) != ROWS:
        sys.exit("рядов найдено %d, а нужно %d: %s" % (len(rows), ROWS, rows))
    cols = []
    for y0, y1 in rows:
        c = bands([sum(1 for y in range(y0, y1 + 1) if not mask[y * w + x])
                   for x in range(w)])
        if len(c) != FRAMES:
            sys.exit("в ряду %s кадров найдено %d, а нужно %d: %s"
                     % ((y0, y1), len(c), FRAMES, c))
        cols.append(c)
    return rows, cols


def cut(im, mask, box):
    """Клетка листа с альфой по маске фона. Не обрезается: координаты внутри
    клетки нужны, по ним считаются лицо и линия земли."""
    x0, y0, x1, y1 = box
    w = im.size[0]
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not mask[y * w + x]:
                dst[x - x0, y - y0] = src[x, y] + (255,)
    return out


# ---------------------------------------------------------------------------
# Где в кадре герой
# ---------------------------------------------------------------------------

def is_skin(p):
    """Цвет кожи: тёплый, светлый, но не оранжевое пламя.

    Кожа (176,144,128) — R>G>B с ровным спадом. У оранжевого выхлопа третьего
    ряда спад между G и B гораздо круче, чем между R и G, у бело-синего
    пламени четвёртого B не ниже R, у серого дыма спада нет вовсе.
    """
    r, g, b = p[0], p[1], p[2]
    if not (135 <= r <= 225):
        return False
    if r - b < 22 or r - g < 8:
        return False
    return (g - b) <= (r - g) * 1.3 + 6


def face_box(cell):
    """Лицо: самый крупный связный кусок кожи. (x0, y0, x1, y1).

    Лицо — единственный крупный участок кожи в кадре: кисти рук вчетверо
    мельче, а снаряжение кожи не имеет ни в одном ряду. Ищется по цвету, а не
    сужением силуэта (import_art.head_anchor): здесь над головой то мачта, то
    диск винта, то ракеты — силуэт от сужения не рвётся, и «макушкой»
    оказывается снаряжение.
    """
    w, h = cell.size
    px = cell.load()
    seen = bytearray(w * h)
    best = None
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or not px[sx, sy][3] or not is_skin(px[sx, sy]):
                continue
            stack = [(sy, sx)]
            seen[sy * w + sx] = 1
            n = 0
            x0 = x1 = sx
            y0 = y1 = sy
            while stack:
                y, x = stack.pop()
                n += 1
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and not seen[ny * w + nx] \
                                and px[nx, ny][3] and is_skin(px[nx, ny]):
                            seen[ny * w + nx] = 1
                            stack.append((ny, nx))
            if best is None or n > best[0]:
                best = (n, x0, y0, x1, y1)
    if best is None:
        sys.exit("в кадре не нашлось лица — проверь маску фона")
    return best[1:]


def crown(cell, face):
    """Макушка: вверх от лица, пока силуэт не станет уже половины лица.

    Мачта пропеллера тоньше головы, и подъём на ней останавливается. Диск
    большого винта и ракеты — не тоньше, на них подъём уезжает вверх до
    самого верха клетки; поэтому макушка годится только там, где над головой
    ничего широкого нет, и берётся она только в REF_ROW (см. body_height).
    """
    x0, y0, x1, y1 = face
    fw = x1 - x0 + 1
    cx = (x0 + x1) / 2.0
    a = max(0, int(round(cx - fw * 0.6)))
    b = min(cell.size[0] - 1, int(round(cx + fw * 0.6)))
    px = cell.load()
    y = y0
    while y > 0:
        run = sum(1 for x in range(a, b + 1) if px[x, y - 1][3])
        if run < fw * 0.6:
            break
        y -= 1
    return y


def sole(cell, face):
    """Подошва: самый низ содержимого под головой.

    Окно — две с половиной ширины лица в каждую сторону: ноги в шаге
    расходятся, но пламя и выхлоп уносит дальше, и они в окно не попадают.
    """
    x0, y0, x1, y1 = face
    fw = x1 - x0 + 1
    cx = (x0 + x1) / 2.0
    a = max(0, int(round(cx - fw * 2.5)))
    b = min(cell.size[0] - 1, int(round(cx + fw * 2.5)))
    px = cell.load()
    for y in range(cell.size[1] - 1, -1, -1):
        for x in range(a, b + 1):
            if px[x, y][3]:
                return y
    return cell.size[1] - 1


def median(vals):
    s = sorted(vals)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def main(path):
    sheet = Image.open(path).convert("RGB")
    print("лист:", sheet.size)
    mask = background_mask(sheet)
    # Лист снят со своей экспозицией: без приведения к эталону герой сереет,
    # стоило смениться анимации (см. import_art.tone_match).
    sheet = tone_match(sheet, mask)
    rows, cols = grid(mask, sheet.size)
    print("ряды:", rows)

    cells = {}
    for r, (y0, y1) in enumerate(rows):
        print("ряд %d, кадры: %s" % (r + 1, cols[r]))
        for i, (x0, x1) in enumerate(cols[r]):
            cell = cut(sheet, mask, (x0, y0, x1, y1))
            before = cell.getchannel("A").histogram()[0]
            cell = drop_slivers(cell)
            lost = cell.getchannel("A").histogram()[0] - before
            if lost:
                print("  ! ряд %d кадр %d: выброшено %d px у края клетки"
                      % (r + 1, i + 1, lost))
            cells[(r, i)] = cell

    faces = {key: face_box(cell) for key, cell in cells.items()}
    soles = {key: sole(cells[key], faces[key]) for key in cells}

    # 1. МАСШТАБ. Рост меряется в опорном ряду: (подошва - макушка). Берётся
    #    МИНИМУМ по кадрам ряда, а не среднее: ошибиться подъём к макушке
    #    может только в одну сторону — уехать вверх по мачте, — и такой кадр
    #    даёт рост завышенный. Минимум отбрасывает ровно эти промахи.
    stands = []
    for i in range(FRAMES):
        key = (REF_ROW, i)
        stands.append(soles[key] - crown(cells[key], faces[key]))
    stand = min(stands)
    k = BODY_H / float(stand)
    print("рост в опорном ряду %d: %s -> берём %d px исходника, %d px в игре, "
          "масштаб %.4f" % (REF_ROW + 1, stands, stand, BODY_H, k))

    # 2. ЛИНИЯ ЗЕМЛИ. Расстояние «середина лица -> подошва» берётся из
    #    опорного ряда и переносится во все остальные: в рядах с выхлопом
    #    подошвы не видно, а лицо есть везде. Так голова во всех четырёх
    #    лентах висит на одной высоте, а ноги живут по-своему — это и нужно:
    #    в полёте они и должны болтаться.
    drop = median([soles[(REF_ROW, i)] - (faces[(REF_ROW, i)][1]
                                          + faces[(REF_ROW, i)][3]) / 2.0
                   for i in range(FRAMES)])
    print("лицо -> подошва: %.1f px исходника (%.1f px в игре)" % (drop, drop * k))

    geom = {}
    for r in range(ROWS):
        # земля ряда — одна на все шесть кадров, чтобы внутри ленты
        # сохранилось покачивание, а между лентами герой не прыгал
        ground = median([(faces[(r, i)][1] + faces[(r, i)][3]) / 2.0
                         for i in range(FRAMES)]) + drop

        half = up = down = 0
        for i in range(FRAMES):
            box = cells[(r, i)].getbbox()
            cx = (faces[(r, i)][0] + faces[(r, i)][2]) / 2.0
            half = max(half, (cx - box[0]) * k, (box[2] - 1 - cx) * k)
            up = max(up, (ground - box[1]) * k)
            down = max(down, (box[3] - 1 - ground) * k)
        fw = 2 * (int(half) + 1 + PAD)
        gy = int(up) + 1 + PAD
        fh = gy + max(0, int(down) + 1) + PAD

        out = Image.new("RGBA", (fw * FRAMES, fh), (0, 0, 0, 0))
        for i in range(FRAMES):
            cell = cells[(r, i)]
            box = cell.getbbox()
            piece = cell.crop(box)
            tw = max(1, round(piece.size[0] * k))
            th = max(1, round(piece.size[1] * k))
            small = shrink(piece, (tw, th))
            cx = (faces[(r, i)][0] + faces[(r, i)][2]) / 2.0
            dx = i * fw + fw // 2 - round((cx - box[0]) * k)
            dy = gy - round((ground - box[1]) * k)
            out.alpha_composite(small, (dx, dy))

        dst = os.path.join(ROOT, "art", "character", OUT[r] + ".png")
        out.save(dst)
        geom[OUT[r]] = (fw, fh, gy)
        # Ширина лица — та самая проверка, что герой не поменял размер: она
        # должна совпадать во всех четырёх лентах. «Лицо -> подошва» мерит
        # уже позу: в висячих рядах ноги вытянуты, и число там больше.
        faces_g = [(faces[(r, i)][2] - faces[(r, i)][0] + 1) * k
                   for i in range(FRAMES)]
        legs = [(soles[(r, i)] - (faces[(r, i)][1] + faces[(r, i)][3]) / 2.0) * k
                for i in range(FRAMES)]
        print("  %s <- ряд %d: кадр %dx%d, земля y=%d, лента %dx%d; "
              "ширина лица %.1f..%.1f px, лицо -> подошва %.1f..%.1f px"
              % (OUT[r], r + 1, fw, fh, gy, out.size[0], out.size[1],
                 min(faces_g), max(faces_g), min(legs), max(legs)))

    print("\nSHEET_FRAME для scripts/player/character_view.gd:")
    for name in OUT:
        fw, fh, gy = geom[name]
        print('\t"%s": [%d, %d, %d],' % (name, fw, fh, gy))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_packs.py sheet.jpg")
    main(sys.argv[1])
