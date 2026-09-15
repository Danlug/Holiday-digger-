#!/usr/bin/env python3
"""import_tiles.py — нарезка авторского листа тайлов в игровые 32×32.

У этого листа три беды, и все три лечатся здесь, а не руками в PNG:

1. Тайлы нарисованы карточками — с тёмной каймой по краю. Для витрины это
   красиво, для тайлмапа смертельно: замощённое поле покрывается сеткой
   швов. Ровно на эти грабли проект уже наступал с генератором
   плейсхолдеров, где направленный градиент запекал полосу в каждый край.

2. Каждая руда нарисована на СВОЁМ куске грунта, и эти куски разъезжаются
   по тону: клетка с рудой то светлее, то холоднее соседней земли. В шахте
   это читается как заплатки — глаз ловит прямоугольник, а не руду.

3. Грунты первого ряда отличаются по светлоте втрое, поэтому взять их
   вариантами земли «как есть» нельзя — получается лоскутное одеяло.

Отсюда четыре шага, которых нет в обычной нарезке:

  * обрезка кромки — снимаем нарисованную рамку;
  * выравнивание поля (flat-field): усреднённый по ВСЕМ тайлам профиль
    яркости показывает систематическое затемнение к краю, его делим
    обратно. Считать профиль по одному тайлу нельзя — это выест его
    собственный рисунок;
  * подгонка крайних пикселей каждого тайла под его же внутренность —
    добивает остаток каймы там, где она нарисована толще средней;
  * приведение ФОНА к общему тону: фоновый (грунтовый) кластер каждого
    тайла сдвигается к эталону, взятому по тайлам земли. Сдвиг применяется
    с весом «насколько пиксель похож на грунт», поэтому самородки,
    кристаллы и уголь остаются как нарисованы.

Запуск:  python3 tools/import_tiles.py art/_source/tiles_sheet.jpg
"""

import math
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

# Какую долю кромки снять с каждой стороны. Мерил по профилю яркости ячеек:
# нарисованная тень карточки заходит внутрь на 5-6 пикселей при ширине ячейки
# 58-63, то есть примерно на 0.10 стороны. Было 0.07 — этого не хватало, и у
# половины тайлов оставалась тёмная полоса. Автоподбор обрезки по каждой
# ячейке пробовал и отверг: он цепляется не за кайму, а за рисунок (у урана
# и платины съедал по 15 пикселей, то есть саму руду).
TRIM = 0.11
# Фундаменту режем по-старому, меньше: его рамка — часть рисунка (см.
# KEEP_FRAME), и обрезка 0.11 съедала её до еле заметной тени.
TRIM_FRAME = 0.07
FLAT_STRENGTH = 1.0   # насколько полно компенсировать затемнение к краю

# Подгонка крайних пикселей под внутренность тайла. Двух хватает: после
# обрезки и flat-field остаточная кайма в готовом 32×32 занимает не больше
# двух пикселей, а лезть глубже — значит стирать рисунок по периметру.
EDGE_DEPTH = 2
EDGE_FADE = (1.0, 0.45)      # вес подгонки по глубине: край тянем целиком
EDGE_LIMIT = (0.65, 1.8)     # предел множителя, чтобы не выбелить угол
EDGE_MIN_MASS = 4.0          # если у края почти нет фона (руда вылезла к
                             # самому краю) — не трогаем, иначе испортим руду

# Фоновый кластер ищется как устойчивое среднее в Lab: вес пикселя падает с
# расстоянием до текущей оценки, оценка пересчитывается по весам.
BG_SIGMA = 14.0    # радиус кластера в Lab. 14 — руда (медь ~24 от грунта,
                   # серые ~17) уже заметно вне его, а тени грунта внутри
BG_L_WEIGHT = 0.35 # светлота в расстояние входит ослабленной: затенённый
                   # грунт — всё ещё грунт, а вот чужой оттенок — уже нет
BG_ITERS = 6

# Тайлы, у которых фон — свой материал, а не грунт: их тон не трогаем.
# Торф здесь потому, что он целиком торф: отдельной «руды» на нём не
# нарисовано, и сведение к эталону земли сделало бы его неотличимым от земли.
OWN_TONE = {"stone", "foundation", "empty", "ore_peat"}

# Фундамент — бетонная плита, и рамка у неё нарисована намеренно: замощённое
# поле должно читаться как плиты, а не как сплошная заливка. Поэтому края ему
# не равняем и высокую оценку шва считаем нормой.
KEEP_FRAME = {"foundation"}

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


# Земля. Раньше брались два грунта одной светлоты — поле повторялось в глаза.
# Четыре РАЗНЫХ грунта «как есть» брать тоже нельзя: по средней яркости они
# идут 40, 58, 83, 99, 71, 51, 70, 80, то есть светлее друг друга втрое, и
# поле распадается на заплатки. Правильный ход — сначала свести их к одному
# тону (это делает tone_match), и только потом ставить вариантами: рисунок
# разный, тон общий.
#
# Выбраны четыре РАЗНЫХ по рисунку грунта: мелкое ровное зерно, зерно
# покрупнее, крупная рыхлая фактура и окатанные камешки. Камней ровно один
# вариант из четырёх: с двумя (ячейки 0,5 и 0,6) поле превращается в щебень
# и начинает спорить с рудой — игроку становится труднее выцепить взглядом
# рудную клетку, а это ровно то, ради чего руда рисуется. Ячейка 0,3 не
# взята: она самая рыжая, и эталон за ней уезжает в оранжевый, а за эталоном
# пришлось бы тащить фон КАЖДОГО рудного тайла. Ячейка 0,7 не взята: её
# белая щебёнка после сведения тона читается как руда.
DIRT_SOURCES = ((0, 1), (0, 2), (0, 4), (0, 5))

# К каждому грунту добавляется поворот на 180°: рисунок меняется, тон нет.
# Именно поворот, а не отражение — у пары «тайл и его зеркало» совпадает
# кромка, и на стыке возникает бабочка, симметричный узор, который глаз
# ловит сразу. Итого 4 × 2 = 8 вариантов земли.
DIRT_TURNS = (0, 180)


# ── цвет ──────────────────────────────────────────────────────────────────
# Lab, а не RGB: в Lab «насколько пиксель похож на грунт» — это расстояние,
# а сдвиг тона не перекрашивает тени.

_LIN = [((v / 255 + 0.055) / 1.055) ** 2.4 if v > 10 else v / 255 / 12.92
        for v in range(256)]


def rgb2lab(r, g, b):
    R, G, B = _LIN[r], _LIN[g], _LIN[b]
    x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
    y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def lab2rgb(lab):
    fy = (lab[0] + 16) / 116
    fx, fz = fy + lab[1] / 500, fy - lab[2] / 200
    g = lambda t: t ** 3 if t ** 3 > 0.008856 else (t - 16 / 116) / 7.787
    x, y, z = g(fx) * 0.95047, g(fy), g(fz) * 1.08883
    out = []
    for v in (3.2406 * x - 1.5372 * y - 0.4986 * z,
              -0.9689 * x + 1.8758 * y + 0.0415 * z,
              0.0557 * x - 0.2040 * y + 1.0570 * z):
        v = max(0.0, min(1.0, v))
        v = 1.055 * v ** (1 / 2.4) - 0.055 if v > 0.0031308 else 12.92 * v
        out.append(max(0, min(255, round(v * 255))))
    return tuple(out)


def _dist2(p, m):
    return (((p[0] - m[0]) * BG_L_WEIGHT) ** 2
            + (p[1] - m[1]) ** 2 + (p[2] - m[2]) ** 2)


def background(labs, seed=None):
    """Фоновый кластер и веса «это фон» для каждого пикселя.

    Затравка важнее, чем кажется. От медианы тайла оценка уезжает туда, где
    руды много: у урана она находила ядовито-зелёный знак, у изумруда —
    камни. Поэтому для рудных тайлов затравкой служит эталон земли: тогда
    оценка садится на ближайший коричневый кластер, то есть на грунт.
    """
    if seed is None:
        seed = tuple(sorted(p[i] for p in labs)[len(labs) // 2] for i in range(3))
    m = seed
    for _ in range(BG_ITERS):
        sw, acc = 0.0, [0.0, 0.0, 0.0]
        for p in labs:
            w = math.exp(-_dist2(p, m) / (2 * BG_SIGMA * BG_SIGMA))
            sw += w
            for i in range(3):
                acc[i] += w * p[i]
        if sw < 1e-6:
            break
        m = tuple(v / sw for v in acc)
    weights = [math.exp(-_dist2(p, m) / (2 * BG_SIGMA * BG_SIGMA)) for p in labs]
    return m, weights


def tone_match(labs, weights, ref):
    """Тянем фон к эталону, руду оставляем как нарисована.

    Сдвигаем не весь тайл, а каждый пиксель с его собственным весом: грунт
    приезжает в эталон целиком, самородок — почти не двигается.
    """
    sw = sum(weights)
    if sw < 1e-6:
        return labs
    bg = [sum(w * p[i] for w, p in zip(weights, labs)) / sw for i in range(3)]
    delta = [ref[i] - bg[i] for i in range(3)]
    return [tuple(p[i] + w * delta[i] for i in range(3))
            for p, w in zip(labs, weights)]


# ── нарезка ───────────────────────────────────────────────────────────────

def cells(sheet, trim=TRIM):
    """Все ячейки листа, обрезанные от нарисованной кромки."""
    out = {}
    for r, (y0, y1) in enumerate(ROWS):
        for c, (x0, x1) in enumerate(COLS):
            w, h = x1 - x0 + 1, y1 - y0 + 1
            dx, dy = round(w * trim), round(h * trim)
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
    затемнение по горизонтали и вертикали разное.
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


def apply_flat(img, kx, ky):
    out = Image.new("RGB", (TILE, TILE))
    sp, op = img.load(), out.load()
    for y in range(TILE):
        for x in range(TILE):
            k = 1.0 + (kx[x] * ky[y] - 1.0) * FLAT_STRENGTH
            r, g, b = sp[x, y]
            op[x, y] = (min(255, round(r * k)), min(255, round(g * k)),
                        min(255, round(b * k)))
    return out


def edge_match(px, weights):
    """Подгоняет крайние пиксели по яркости под внутренность тайла.

    Общий flat-field снимает только СРЕДНЮЮ кайму; у части карточек она
    нарисована толще, и остаток вылезает швом именно там. Здесь остаток
    добирается по каждому тайлу отдельно.

    Считаем и применяем по фоновым весам: иначе у тайла, где кристалл
    дорос до самого края, подгонка стала бы гасить кристалл.
    """
    lum = lambda t: 0.299 * t[0] + 0.587 * t[1] + 0.114 * t[2]
    idx = lambda x, y: y * TILE + x
    inner = [(x, y) for y in range(TILE) for x in range(TILE)
             if EDGE_DEPTH <= x < TILE - EDGE_DEPTH
             and EDGE_DEPTH <= y < TILE - EDGE_DEPTH]
    mass = sum(weights[idx(x, y)] for x, y in inner)
    if mass < 1e-6:
        return
    target = sum(weights[idx(x, y)] * lum(px[x, y]) for x, y in inner) / mass

    for d in range(EDGE_DEPTH):
        for side in range(4):
            if side == 0:
                line = [(x, d) for x in range(TILE)]
            elif side == 1:
                line = [(x, TILE - 1 - d) for x in range(TILE)]
            elif side == 2:
                line = [(d, y) for y in range(TILE)]
            else:
                line = [(TILE - 1 - d, y) for y in range(TILE)]
            m = sum(weights[idx(x, y)] for x, y in line)
            if m < EDGE_MIN_MASS:
                continue
            cur = sum(weights[idx(x, y)] * lum(px[x, y]) for x, y in line) / m
            if cur < 1e-6:
                continue
            k = min(max(target / cur, EDGE_LIMIT[0]), EDGE_LIMIT[1])
            for x, y in line:
                w = weights[idx(x, y)] * EDGE_FADE[d]
                f = 1.0 + (k - 1.0) * w
                r, g, b = px[x, y]
                px[x, y] = (min(255, round(r * f)), min(255, round(g * f)),
                            min(255, round(b * f)))


def finish(img, colors=24):
    return img.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")


def prepare(img, name, ref):
    """Полный проход по одному тайлу: края, тон, квантование.

    Возвращает готовый тайл, его фоновый кластер ПОСЛЕ сведения тона и веса
    «это фон» — по ним потом считается шов отдельно по грунту.
    """
    px = img.load()
    labs = [rgb2lab(*px[x, y]) for y in range(TILE) for x in range(TILE)]
    own = name in OWN_TONE
    bg, weights = background(labs, None if own else ref)
    if name not in KEEP_FRAME:
        edge_match(px, weights)
        labs = [rgb2lab(*px[x, y]) for y in range(TILE) for x in range(TILE)]
        bg, weights = background(labs, None if own else ref)
    if not own:
        labs = tone_match(labs, weights, ref)
        for y in range(TILE):
            for x in range(TILE):
                px[x, y] = lab2rgb(labs[y * TILE + x])
    out = finish(img)
    op = out.load()
    labs = [rgb2lab(*op[x, y]) for y in range(TILE) for x in range(TILE)]
    bg, weights = background(labs, None if own else ref)
    return out, bg, weights


# ── отчёт ─────────────────────────────────────────────────────────────────

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


def seam_bg(img, weights):
    """Шов, посчитанный только по фоновым пикселям.

    Обычная оценка считает весь тайл, и у руды, дорисованной до самого края
    (литий, уран, рубин), она высокая просто потому, что снизу кристалл, а
    сверху грунт. Нам же важно, сходится ли ГРУНТ на стыке.
    """
    p = img.load()
    idx = lambda x, y: y * TILE + x
    def col(i):
        m = sum(weights[idx(i, j)] for j in range(TILE))
        if m < EDGE_MIN_MASS:
            return None
        return sum(weights[idx(i, j)] * sum(p[i, j]) for j in range(TILE)) / m
    def row(j):
        m = sum(weights[idx(i, j)] for i in range(TILE))
        if m < EDGE_MIN_MASS:
            return None
        return sum(weights[idx(i, j)] * sum(p[i, j]) for i in range(TILE)) / m
    def score(line):
        v = [line(i) for i in range(TILE)]
        pairs = [(v[i], v[i + 1]) for i in range(1, TILE - 2)
                 if v[i] is not None and v[i + 1] is not None]
        if not pairs or v[0] is None or v[TILE - 1] is None:
            return float("nan")
        inner = sum(abs(a - b) for a, b in pairs) / len(pairs)
        return abs(v[TILE - 1] - v[0]) / max(inner, 1e-6)
    return score(col), score(row)


def mean_lab(img):
    p = img.load()
    labs = [rgb2lab(*p[x, y]) for y in range(TILE) for x in range(TILE)]
    return [sum(v[i] for v in labs) / len(labs) for i in range(3)]


def main(sheet_path):
    sheet = Image.open(sheet_path).convert("RGB")
    print("лист:", sheet.size)
    grid = cells(sheet)
    print("ячеек найдено:", len(grid))

    kx, ky = flat_field(list(grid.values()))
    print("компенсация края по X:", round(kx[0], 2), "по Y:", round(ky[0], 2))
    flat = {k: apply_flat(v, kx, ky) for k, v in grid.items()}
    # Тайлы с намеренной рамкой берём из отдельной, щадящей нарезки; профиль
    # затемнения при этом остаётся общим — он считается по всему листу.
    framed = cells(sheet, TRIM_FRAME)
    for cell, name in MAP.items():
        if name in KEEP_FRAME and cell in framed:
            flat[cell] = apply_flat(framed[cell], kx, ky)

    # Эталон тона — по тайлам земли, а не выдуманный: усреднённый фоновый
    # кластер тех самых грунтов, которые пойдут в игру вариантами.
    ref_parts = []
    for cell in DIRT_SOURCES:
        p = flat[cell].load()
        labs = [rgb2lab(*p[x, y]) for y in range(TILE) for x in range(TILE)]
        ref_parts.append(background(labs)[0])
    ref = tuple(sum(v[i] for v in ref_parts) / len(ref_parts) for i in range(3))
    print("эталон фона (Lab): L={:.1f} a={:.1f} b={:.1f}".format(*ref))

    n = 1
    spread = []
    for cell in DIRT_SOURCES:
        img, _, _ = prepare(flat[cell].copy(), "dirt", ref)
        for turn in DIRT_TURNS:
            out = img if turn == 0 else img.rotate(180)
            out.save(os.path.join(ROOT, "art", "tiles", f"dirt_{n}.png"))
            lab = mean_lab(out)
            spread.append(lab[0])
            print(f"  dirt_{n:<12} <- ячейка {cell[0]},{cell[1]}"
                  f"{' (поворот 180°)' if turn else ''}   L={lab[0]:.1f}")
            n += 1
    print(f"вариантов земли: {len(spread)}, "
          f"разброс средней светлоты L {min(spread):.1f}..{max(spread):.1f}")

    worst = (0.0, "")
    bgs = []
    for (r, c), name in sorted(MAP.items()):
        if (r, c) not in grid:
            print(f"  !! ячейка {r},{c} пуста, {name} не записан")
            continue
        img, bg, weights = prepare(flat[(r, c)].copy(), name, ref)
        img.save(os.path.join(ROOT, "art", "tiles", name + ".png"))
        sx, sy = seam_score(img)
        gx, gy = seam_bg(img, weights)
        if max(sx, sy) > worst[0]:
            worst = (max(sx, sy), name)
        mark = ""
        if name in KEEP_FRAME:
            mark = "  (рамка оставлена намеренно)"
        elif name in OWN_TONE:
            mark = "  (свой тон)"
        else:
            bgs.append(bg)
        print(f"  {name:16s} <- ячейка {r},{c}   шов X={sx:.2f} Y={sy:.2f}"
              f"  (по грунту {gx:.2f}/{gy:.2f})"
              f"   фон L={bg[0]:.1f} a={bg[1]:.1f} b={bg[2]:.1f}{mark}")
    if bgs:
        for i, axis in enumerate("Lab"):
            v = [b[i] for b in bgs]
            print(f"  фон рудных тайлов, {axis}: "
                  f"{min(v):.1f}..{max(v):.1f} (разброс {max(v) - min(v):.1f})")
    print(f"худший шов: {worst[1]} = {worst[0]:.2f} (1.0 — шва нет)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_tiles.py sheet.jpg")
    main(sys.argv[1])
