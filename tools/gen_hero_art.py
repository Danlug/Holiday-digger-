#!/usr/bin/env python3
"""gen_hero_art.py — мальчик чётким пиксель-артом (ветка «hero-art»).

Заказ владельца: «Посмотри, где недостаточно чёткая картинка, мальчика можно
перерисовать». Почему он был мутным: кадры героя нарезаны из авторских JPEG-
листов, где у фигуры свой «пиксель» художника ~2 текселя, а нарезка уменьшала
лист с усреднением — пиксели художника легли на сетку текстуры не целым
числом и размазались; по краю осталась светлая полупрозрачная кайма от фона
листа; на экране 448 px (×2) кадр 144 текселя ещё и уменьшается в 1,5 раза
линейным фильтром. Получалась «уменьшенная фотография» среди чётких тайлов.

Что делает этот скрипт. Позы остаются авторскими (те же кадры, те же
опорные точки — ступни на линии земли, рука с инструментом там же), а
пиксели рисуются заново:

  * сетка — 2×2 текселя на пиксель рисунка (72×72 на кадр 48×48 логических
    точек; фигура ~60 пикселей ростом — ровно столько «пикселей художника»
    и было на авторских листах, подробность лица и рук не теряется);
  * цвета — только из рамп материалов (волосы, кожа, футболка, джинсы,
    кеды, сталь, дерево, ржавчина, ранец, …) по 5–8 тонов, тени холоднее,
    света теплее — как у перерисованных руд и лавы;
  * тёмный контур в один пиксель рисунка по всему силуэту, оттенка своего
    материала (не чёрный); светлой каймы нет ни одного пикселя;
  * ободок света по верхнему-левому краю силуэта, внутренние линии
    (рука на футболке, брови, глаза) — тёмные пиксели из авторских линий;
  * альфа только 0 или 255, без сглаживания.

Вход — снимок нарезки авторских листов `art/_source/hero_cut/` (там лежат
кадры ровно такими, какими их выдали tools/import_*.py; gen_hero_anim.py
читает и пишет прямо туда; папка скрыта от Godot файлом .gdignore). Выход —
те же файлы в art/character/ с теми же именами и размерами. Если авторский
лист пришлёт новую версию: прогнать нужный import_*.py (он пишет в
art/character/), затем `python3 tools/gen_hero_art.py --take <листы>` —
свежая нарезка уйдёт в hero_cut/ и сразу будет перерисована.

Запуск:  python3 tools/gen_hero_art.py            — перерисовать всё
         python3 tools/gen_hero_art.py idle walk  — только эти листы
         python3 tools/gen_hero_art.py --take walk — забрать свежую нарезку
                                                   import_*.py и перерисовать
         python3 tools/gen_hero_art.py --sheet OUT.png — лист «было/стало»
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "art", "_source", "hero_cut")
OUT_DIR = os.path.join(ROOT, "art", "character")

# Пиксель рисунка в текселях. 2 — см. шапку: подробность авторского листа.
CELL = 2

def hexc(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


# ---------------------------------------------------------------------------
# Рампы материалов: [контур, тон 0 (тень) … тон N (свет)].
# Подобраны по цветам авторского листа (characters_sheet / move_sheet): синяя
# футболка, серые джинсы, бело-серые кеды, каштановые волосы, светлая кожа.
# ---------------------------------------------------------------------------
RAMPS = {
    "skin": ["4a221c", "8a5644", "a8705a", "c4886a", "dca484", "f0c09c", "fcdcc0"],
    "hair": ["241208", "3e2416", "5a3622", "764a2e", "94623e", "b48056"],
    "shirt": ["121838", "2c3860", "34508e", "4468aa", "5a82c2", "86a8de"],
    "grey": ["1a1c26", "37383f", "4e4f58", "66676f", "818289", "9d9ea4",
             "bcc0cb", "dcdee4", "f6f7f9"],
    "rust": ["3a1406", "6a2c12", "954618", "bc6424", "da8a40", "f0b270"],
    "stone": ["3a3028", "b4a48c", "ccbea8", "e4d8c8"],
    "khaki": ["2e2812", "4c4424", "6a6036", "8c8150", "ae9f6c", "cec08e"],
    "green": ["1a2612", "2e421c", "445c28", "5c7834", "7a9646", "9cb468"],
    "red": ["3a0c10", "64161c", "922428", "bc3a34", "de624c", "f49a80"],
    "flame": ["8a2a08", "c04e10", "e8801c", "f8b438", "ffe07a", "fff6cc"],
}
RAMPS = {k: [hexc(c) for c in v] for k, v in RAMPS.items()}
# Черты лица (глаза, брови, линия рта) — тёмно-каштановые, не цвета контура
# кожи: красноватая точка вместо глаза читается как ссадина.
FEATURE = hexc("3a2018")


def _lab(rgb):
    """sRGB (…,3) 0..255 -> CIELab."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805],
                  [0.2126, 0.7152, 0.0722],
                  [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


# Плоская таблица всех тонов (без контуров) для классификации.
_MATS = list(RAMPS.keys())
_TAB_RGB = []
_TAB_MAT = []
_TAB_TONE = []
for _mi, _m in enumerate(_MATS):
    for _ti, _c in enumerate(RAMPS[_m][1:]):
        _TAB_RGB.append(_c)
        _TAB_MAT.append(_mi)
        _TAB_TONE.append(_ti)
_TAB_LAB = _lab(np.array(_TAB_RGB))
_TAB_MAT = np.array(_TAB_MAT)
_TAB_TONE = np.array(_TAB_TONE)


SKIN = _MATS.index("skin")
HAIR = _MATS.index("hair")
GREY = _MATS.index("grey")
BODY_MATS = [_MATS.index(m) for m in ("skin", "hair", "shirt", "khaki", "green", "red", "rust")]


def _luma(rgb):
    rgb = np.asarray(rgb, dtype=np.float64)
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


# ---------------------------------------------------------------------------
# Морфология на булевых масках (без scipy)
# ---------------------------------------------------------------------------

def _shift(m, dy, dx, fill=False):
    h, w = m.shape
    out = np.full_like(m, fill)
    ys0, ys1 = max(0, dy), min(h, h + dy)
    xs0, xs1 = max(0, dx), min(w, w + dx)
    out[ys0:ys1, xs0:xs1] = m[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


def _erode(m):
    r = m.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            r &= _shift(m, dy, dx, False)
    return r


def _dilate(m):
    r = m.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            r |= _shift(m, dy, dx, False)
    return r


N4 = ((-1, 0), (1, 0), (0, -1), (0, 1))
N8 = tuple((dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)


def _box(v, mask, r=1):
    """Сумма значений v (h,w,…) в окне (2r+1)² по пикселям mask."""
    acc = np.zeros_like(v)
    vm = v * mask[..., None] if v.ndim == 3 else v * mask
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if v.ndim == 3:
                sh = np.stack([_shift(vm[..., k], dy, dx, 0.0) for k in range(v.shape[2])], axis=-1)
            else:
                sh = _shift(vm, dy, dx, 0.0)
            acc += sh
    return acc


def _components(mask):
    """Связные области (8-соседство): массив меток и размеры."""
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    sizes = [0]
    cur = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                cur += 1
                stack = [(y, x)]
                lab[y, x] = cur
                n = 0
                while stack:
                    cy, cx = stack.pop()
                    n += 1
                    for dy, dx in N8:
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            stack.append((ny, nx))
                sizes.append(n)
    return lab, np.array(sizes)


# ---------------------------------------------------------------------------
# Перерисовка одного кадра
# ---------------------------------------------------------------------------

# Тексель темнее этого — авторская линия (контур, брови, глаза, складка).
INK_Y = 45.0
# Пиксель рисунка со средней яркостью ниже — тоже линия, даже если тёмных
# текселей в нём один (линия художника в 1,5 текселя ложится на сетку криво).
INK_BLOCK_Y = 54.0
# Вес светлоты при выборе материала: оттенок важнее — тень футболки и
# светлые джинсы близки по светлоте, но не по цвету.
L_WEIGHT = 0.55
# Относительная линия: тексель темнее INK_REL от светлоты заливки вокруг
# (медиана в окне LOCAL_R). INK_REL_STRONG — достаточно одного такого текселя.
INK_REL = 0.52
INK_REL_STRONG = 0.42
LOCAL_R = 4


def _local_ref(Y, op, r):
    """Медиана светлоты непрозрачных текселей в окне (2r+1)² — «заливка вокруг»."""
    H, W = Y.shape
    pad = np.pad(np.where(op, Y, np.nan), r, constant_values=np.nan)
    win = np.lib.stride_tricks.sliding_window_view(pad, (2 * r + 1, 2 * r + 1))
    win = win.reshape(H, W, -1)
    # Верхняя половина значений: сама линия не должна тянуть «заливку» вниз.
    with np.errstate(all="ignore"):
        q = np.nanpercentile(win, 70, axis=-1)
    return np.where(np.isnan(q), 255.0, q)


# ---------------------------------------------------------------------------
# Лицо
#
# Лицо авторского мальчика — 11×10 пикселей рисунка, и автоматом оно не
# переносится: бровь и глаз у автора разделены тремя текселями, на сетке 2×2
# они сливаются в тёмную полосу, а полутени щёк дробятся в пятна. Поэтому
# лицо рисуется заново по канону (бровь, глаз 1×2, нос тенью, рот 2 пикселя),
# а у авторского кадра берётся только ГДЕ: строка и столбцы глаз — по тёмным
# текселям в передней части лица. Не нашлось глаз — лицо остаётся как есть.
# ---------------------------------------------------------------------------

EYE_WHITE = hexc("f4efe8")


def _find_head(inside, mat, outline):
    """Голова кадра: (волосы, причёска, лицо, маска головы) или None.

    Причёска — самая верхняя область цвета волос, к которой прилегает лицо
    (кожа): верхние «волосы» без лица — это ржавчина на лопасти винта, комья
    земли, кожаный ранец.
    """
    h, w = inside.shape
    hair = inside & (mat == HAIR)
    lab, sizes = _components(hair)
    order = []
    for i in range(1, len(sizes)):
        if sizes[i] >= 10:
            order.append((np.where(lab == i)[0].min(), i))
    for _top, i in sorted(order):
        found = _head_from(lab == i, hair, inside, mat, outline)
        if found is not None:
            return found
    if os.environ.get("HERO_DEBUG"):
        print("  голова: лица нет")
    return None


def _head_from(hcomp, hair, inside, mat, outline):
    h, w = inside.shape
    ys, xs = np.where(hcomp)
    hy0, hy1, hx0, hx1 = ys.min(), ys.max(), xs.min(), xs.max()
    win = np.zeros_like(inside)
    win[hy0:min(h, hy1 + 9), max(0, hx0 - 1):min(w, hx1 + 4)] = True
    skin = inside & (mat == SKIN) & win
    face = skin & _dilate(hcomp)
    while True:
        grown = face.copy()
        for dy, dx in N4:
            grown |= _shift(face, dy, dx, False)
        grown &= skin
        if (grown == face).all():
            break
        face = grown
    if (face & ~outline).sum() < 20:
        return None
    # Волосы головы — только около лица: тёмная тень винта или ранец того же
    # цвета, сросшиеся с причёской, головой не считаются.
    fys, fxs = np.where(face)
    near_face = np.zeros_like(hcomp)
    near_face[max(0, fys.min() - 9):fys.max() + 1, max(0, fxs.min() - 5):fxs.max() + 4] = True
    hcomp = hcomp & near_face
    rows = np.zeros_like(face)
    rows[:min(h, hy0 + len(HEAD))] = True
    return hair, hcomp, face, hcomp | (face & rows)


def _face_pass(found, ink, fill, tone, outline, rel_full, op_full, mode):
    hair, hcomp, face, _head = found
    h, w = face.shape
    inner = face & ~outline
    # Тексели внутренней части лица.
    tm = np.zeros(op_full.shape, dtype=bool)
    big = np.repeat(np.repeat(inner, CELL, 0), CELL, 1)
    tm[:big.shape[0], :big.shape[1]] = big
    dark = tm & (rel_full < 0.45)
    ty, tx = np.where(tm)
    top, bot = ty.min(), ty.max()
    left, right = tx.min(), tx.max()
    front = dark & (np.arange(op_full.shape[1])[None, :] >= left + 0.3 * (right - left))
    upper = top + int(0.62 * (bot - top))
    rows = [r for r in range(top, upper + 1) if front[r].sum() >= 2]
    if not rows:
        return None
    er = max(rows)
    cols = np.where(front[er - 1:er + 1].any(0))[0]
    runs = []
    for c in cols:
        if runs and c - runs[-1][-1] <= 2:
            runs[-1].append(c)
        else:
            runs.append([c])
    runs = runs[-2:]
    eyes = [int((r[0] + r[-1]) / 2) // CELL for r in runs]
    ey = (er - 1) // CELL
    # Глаз должен лечь на лицо, иначе это не глаз (тень, прядь) — лицо не трогаем.
    if not all(inner[min(h - 1, ey + k), ex] for ex in eyes for k in (0, 1)):
        return None
    # Ниже подбородка (шея, ворот) — как было: линия подбородка нужна.
    rows_ok = np.zeros_like(inner)
    rows_ok[:min(h, ey + 6)] = True
    inner &= rows_ok
    ink = ink.copy()
    fill = fill.copy()
    tone = tone.copy()
    # Внутри лица — чистая кожа: тон 4, в тени под чёлкой и у затылка — 3.
    ink[inner] = False
    fill[inner] = True
    tone[inner] = 4
    hair_or_line = hair | (outline & ~face)
    shade = inner & (_shift(hair_or_line, 1, 0, False) | _shift(hair_or_line, 0, 1, False))
    tone[shade] = 3
    # Тёмные пряди внутри причёски — тёмный тон волос, а не контур: иначе
    # голова читается чёрной шапкой.
    strands = hcomp & ink & ~outline
    ink[strands] = False
    fill[strands] = True
    tone[strands] = 0
    over = {}

    def put(y, x, c, need=inner):
        if 0 <= y < h and 0 <= x < w and need[y, x]:
            over[(y, x)] = c

    can = inner | hair
    near = max(eyes)
    for ex in eyes:
        wide = (ex - 1, ex, ex + 1) if ex == near else (ex - 1, ex)
        for bx in wide:
            put(ey - 2, bx, RAMPS["hair"][1], can)
        if mode == "closed":
            put(ey + 1, ex - 1, FEATURE)
            put(ey + 1, ex, FEATURE)
        else:
            put(ey, ex, FEATURE)
            put(ey + 1, ex, FEATURE)
    put(ey + 4, near - 2, RAMPS["skin"][2])
    put(ey + 4, near - 1, RAMPS["skin"][2])
    put(ey + 2, near + 1, RAMPS["skin"][4])
    return ink, fill, tone, over


# ---------------------------------------------------------------------------
# Голова — нарисована вручную по авторскому листу персонажей (characters_sheet:
# каштановые вихры, зачёсанные вправо-вверх, чёлка до бровей, ухо у затылка,
# спокойное лицо). Ставится на место головы каждого кадра, где голова в обычном
# положении (совпадение силуэтов IoU >= HEAD_IOU): у листов ходьбы и копки
# авторское лицо мутное, и без этого мальчик в каждой анимации был бы немного
# другим. Где голова наклонена или закрыта рукой/инструментом — остаётся
# перерисовка кадра с лицом по канону (_face_pass).
# Буквы: O контур волос, 1–5 волосы от тени к свету, K контур кожи,
# s c d e кожа от тени к свету, m рот, E глаз/бровь, . пусто.
# ---------------------------------------------------------------------------
HEAD = [
    "......OOO.OOO.......",
    ".....O455O4553OO....",
    "....O45544554333O...",
    "...O3455444333332O..",
    "..O34544333332222O..",
    "..O23443332222212O..",
    "..O22332222111221O..",
    "..O122cdd1221111O...",
    "..O12sdd11dd111dK...",
    "..O1sdddddddddddK...",
    "..KcsdddEEddEEddK...",
    "..KssddddEddWEdcK...",
    "...KsdddddddeedccK..",
    "....KsddddddddddK...",
    "....KsddddddmmddK...",
    ".....KssddddddddK...",
    "......KKssddddKK....",
]
HEAD_CLOSED = HEAD[:10] + [
    "..KcsdddddddddddK...",
    "..KssdddEEddEEdcK...",
] + HEAD[12:]
# Глаза: веко (тёмная черта в два пикселя) и под ним радужка у переднего
# края — спокойный, чуть сонный взгляд, как на авторском листе; брови цвета
# волос через пиксель кожи над веком.
HEAD_IOU = 0.6


def _head_colors():
    hr, sk = RAMPS["hair"], RAMPS["skin"]
    # Волосы канона на ступень темнее рампы: иначе голова-канон светлее
    # своих голов в кадрах, где канон не ставится (руки над головой), и в
    # анимации копки причёска мигала бы светлой.
    return {"O": hr[0], "1": hr[1], "2": hr[2], "3": hr[2], "4": hr[3], "5": hr[4],
            "K": sk[0], "s": sk[3], "c": sk[4], "d": sk[5], "e": sk[6],
            "m": sk[2], "E": FEATURE, "W": EYE_WHITE}


def _head_patch(rows):
    cols = _head_colors()
    hh, ww = len(rows), len(rows[0])
    patch = np.zeros((hh, ww, 4), dtype=np.uint8)
    for y, row in enumerate(rows):
        assert len(row) == ww, (y, row)
        for x, ch in enumerate(row):
            if ch != ".":
                patch[y, x, :3] = cols[ch]
                patch[y, x, 3] = 255
    return patch


def _stamp_place(head, inside, mode):
    """Где поставить голову-канон: (ty, tx) или None, если голова не та
    (IoU < HEAD_IOU) или её загораживает что-то (руки с киркой над головой)."""
    pm = _head_patch(HEAD_CLOSED if mode == "closed" else HEAD)[..., 3] > 0
    ph, pw = pm.shape
    h, w = head.shape
    ys, xs = np.where(head)
    if len(ys) < 0.6 * pm.sum():
        return None
    # Первое приближение — совместить верх волос и центр по ширине. Сравнивается
    # только то, что в рамке шаблона (+1): ранец или тень винта рядом с головой
    # того же цвета, что волосы, совпадению не мешают и не стираются.
    y0 = ys.min()
    x0 = int(round(xs.mean() - np.where(pm)[1].mean()))
    best = (0.0, 0, 0)
    for dy in range(-3, 4):
        for dx in range(-5, 6):
            ty, tx = y0 + dy, x0 + dx
            if ty < 0 or tx < 0 or ty + ph > h or tx + pw > w:
                continue
            placed = np.zeros_like(head)
            placed[ty:ty + ph, tx:tx + pw] = pm
            frame = np.zeros_like(head)
            frame[max(0, ty - 1):ty + ph + 1, max(0, tx - 1):tx + pw + 1] = True
            local = head & frame
            iou = (placed & local).sum() / max(1, (placed | local).sum())
            if iou > best[0]:
                best = (iou, ty, tx)
    iou, ty, tx = best
    dbg = os.environ.get("HERO_DEBUG")
    if iou < HEAD_IOU:
        if dbg:
            print("  голова: IoU %.2f — своя" % iou)
        return None
    placed = np.zeros_like(head)
    placed[ty:ty + ph, tx:tx + pw] = pm
    # Перед головой что-то есть — канон закрыл бы руки. Подбородок (два нижних
    # ряда шаблона) может лечь на ворот — это не загораживание.
    covered = placed.copy()
    covered[ty + ph - 2:ty + ph] = False
    n = (covered & inside & ~head).sum()
    if n > 12:
        if dbg:
            print("  голова: закрыта (%d) — своя" % n)
        return None
    if dbg:
        print("  голова: IoU %.2f — канон" % iou)
    return ty, tx


def _stamp_head(art, head, at, mode):
    patch = _head_patch(HEAD_CLOSED if mode == "closed" else HEAD)
    pm = patch[..., 3] > 0
    ph, pw = pm.shape
    ty, tx = at
    placed = np.zeros_like(head)
    placed[ty:ty + ph, tx:tx + pw] = pm
    # Стирается старая голова в рамке шаблона (+3): иначе по краю остаются
    # кусочки авторского лица (нос, подбородок) рядом с новым.
    frame = np.zeros_like(head)
    frame[max(0, ty - 3):ty + ph + 3, max(0, tx - 3):tx + pw + 3] = True
    art[head & frame & ~placed] = 0
    region = art[ty:ty + ph, tx:tx + pw]
    region[pm] = patch[pm]


# Лицо больше этого (пикселей кожи) — к нему приросли руки: черты по канону
# не рисуются, иначе руки растворяются в лице.
FACE_MAX = 140


def redraw_art(src, gy, face_mode="open"):
    """Кадр src (H,W,4 uint8) -> (art, oy): рисунок на сетке CELL (h,w,4) и сдвиг сетки."""
    H, W = src.shape[:2]
    # Сетка 2×2 — от верха кадра на всех листах: шейдер чёткости в игре
    # (shaders/pixel_art.gdshader, cell=2) считает пиксели рисунка от края
    # текстуры. Линия земли у ходьбы и копки (138) чётная — подошва ложится
    # на границу клетки; у полёта (163, 129) — на тексель ниже, в воздухе
    # этого не видно.
    oy = 0
    h = (H - oy) // CELL
    w = W // CELL
    s = src[oy:oy + h * CELL, :w * CELL].astype(np.float64)
    op_full = s[..., 3] >= 128
    # Тонкие детали (черенок, тяга винта, искры) уже двух текселей: без них
    # порог «половина пикселя закрыта» стёр бы их целиком.
    thin_full = op_full & ~_dilate(_erode(op_full))

    def blocks(a):
        tail = a.shape[2:]
        return a.reshape((h, CELL, w, CELL) + tail).swapaxes(1, 2).reshape((h, w, CELL * CELL) + tail)

    T = blocks(s)
    op = T[..., 3] >= 128
    thin = blocks(thin_full)
    Y = _luma(T[..., :3])
    # Светлота «заливки вокруг» каждого текселя: глаз и бровь темнее лица
    # в разы, складка футболки — лишь немного темнее футболки.
    ref_full = _local_ref(_luma(s[..., :3]), op_full, LOCAL_R)
    rel_full_c = np.where(op_full, _luma(s[..., :3]) / np.maximum(ref_full, 1.0), 9.0)
    ref = blocks(ref_full)
    rel = np.where(op, Y / np.maximum(ref, 1.0), 9.0)
    # Только абсолютно тёмное: относительная темнота ловила бы границу волос
    # и лица (волосы в разы темнее кожи) — черты лица ищет _face_pass.
    ink_t = op & (Y < INK_Y)
    n_op = op.sum(-1)
    n_ink = ink_t.sum(-1)
    inside = (n_op >= 2) | ((n_op >= 1) & (thin & op).any(-1))
    meanY = np.where(n_op > 0, (Y * op).sum(-1) / np.maximum(n_op, 1), 255.0)
    minrel = rel.min(-1)
    line = inside & ((n_ink >= 2) | ((n_ink >= 1) & ((meanY < INK_BLOCK_Y) | (minrel < INK_REL_STRONG))))

    # Силуэт: внешний слой — контур. Крошки (1–2 пикселя: искры, комья) контура
    # не получают, иначе искра станет тёмной.
    labc, sizes = _components(inside)
    tiny = inside & (sizes[labc] <= 2)
    edge = np.zeros_like(inside)
    for dy, dx in N4:
        edge |= inside & ~_shift(inside, dy, dx, False)
    edge &= ~tiny
    # Тонкое (с пустотой с двух противоположных сторон) — не контур, а тёмный тон:
    # черенок в пиксель шириной иначе стал бы чёрной нитью.
    thin1 = inside & ((~_shift(inside, 0, 1, False) & ~_shift(inside, 0, -1, False)) |
                      (~_shift(inside, 1, 0, False) & ~_shift(inside, -1, 0, False)))
    # Контур — там, где он был у автора: у края или на шаг внутрь есть тёмный
    # тексель. Светлая дуга замаха и пыль контура не имели и не получают
    # (с контуром дуга читалась бы твёрдым предметом). Светлая кайма снаружи
    # авторского контура при этом сама становится контуром: тёмное — на шаг внутрь.
    darkish = (op & (Y < INK_Y + 24)).any(-1)
    near_dark = darkish.copy()
    for dy, dx in N8:
        near_dark |= _shift(darkish, dy, dx, False)
    outline_src = edge & ~thin1 & near_dark
    ink = (line | outline_src) & ~tiny

    # Цвет пикселя рисунка: среднее его НЕлинейных текселей (линия не тянет
    # заливку в грязь). У линии берётся всё, что есть, — для выбора материала.
    fill_w = op & ~ink_t
    nf = fill_w.sum(-1)
    wsel = np.where((nf > 0)[..., None], fill_w, op).astype(np.float64)
    col = (T[..., :3] * wsel[..., None]).sum(-2) / np.maximum(wsel.sum(-1), 1)[..., None]

    # Материал: расстояние до каждой рампы, сглаженное по соседям, — так одиночный
    # пиксель «джинсовой» тени посреди футболки остаётся футболкой.
    lab = _lab(col)
    d = lab[:, :, None, :] - _TAB_LAB[None, None, :, :]
    d[..., 0] *= L_WEIGHT
    dist = np.sqrt((d ** 2).sum(-1))
    M = len(_MATS)
    dmat = np.full((h, w, M), 1e9)
    for mi in range(M):
        dmat[..., mi] = dist[..., _TAB_MAT == mi].min(-1)
    fill = inside & ~ink
    sm = _box(dmat, fill, 1) + dmat * 2.0 * fill[..., None]
    cnt = _box(np.ones((h, w)), fill, 1) + 2.0 * fill
    mat = (sm / np.maximum(cnt, 1)[..., None]).argmin(-1)
    tone = np.zeros((h, w), dtype=np.int32)
    for mi in range(M):
        sel = mat == mi
        if sel.any():
            idx = np.where(_TAB_MAT == mi)[0]
            tone[sel] = _TAB_TONE[idx[dist[sel][:, idx].argmin(-1)]]

    # Тело и одежда мальчика обводятся всегда (у листа ходьбы авторский контур
    # размыт — без этого фигура теряла бы край); светлое серое (кеды, искры,
    # дуга замаха) и пламя — только там, где контур был у автора.
    body = np.isin(mat, BODY_MATS) | ((mat == GREY) & (tone <= 4))
    outline = (outline_src | (edge & ~thin1 & body)) & ~tiny
    ink = (ink | outline) & ~tiny
    fill = inside & ~ink

    # Материал линии — большинство окрестных заливок (контур своего цвета).
    votes = np.zeros((h, w, M))
    for mi in range(M):
        votes[..., mi] = _box((mat == mi).astype(np.float64), fill, 2)
    ink_mat = votes.argmax(-1)
    ink_mat[votes.max(-1) <= 0] = HAIR
    # Слабая линия внутри кожи — не черта, а тень: на лице остаются только
    # по-настоящему тёмные точки (глаза, брови), иначе лицо в пятнах.
    soft = line & ~outline & (ink_mat == SKIN) & (minrel >= INK_REL_STRONG) & (meanY >= INK_BLOCK_Y)
    ink &= ~soft
    # И наоборот: посреди кожи тексель вдвое темнее кожи вокруг — это линия
    # автора (рука поверх лица, глаз), даже если сама по себе она не чёрная.
    # Только там, где вокруг кожа со всех сторон: у границы с волосами
    # волосы и так темнее кожи вдвое.
    skin_any = inside & (np.where(ink, ink_mat, mat) == SKIN)
    n_skin = np.zeros((h, w), dtype=np.int32)
    for dy, dx in N8:
        n_skin += _shift(skin_any, dy, dx, False)
    ink |= fill & (mat == SKIN) & (minrel < INK_REL) & (n_skin >= 7)
    fill = inside & ~ink
    mat = np.where(ink, ink_mat, mat)
    # Тон: ближайший внутри выбранной рампы.
    tone = np.zeros((h, w), dtype=np.int32)
    for mi in range(M):
        sel = fill & (mat == mi)
        if sel.any():
            idx = np.where(_TAB_MAT == mi)[0]
            tone[sel] = _TAB_TONE[idx[dist[sel][:, idx].argmin(-1)]]
    tone = np.where(thin1 & fill, np.minimum(tone, 1), tone)

    # Одиночный тон среди четырёх соседей того же материала — шум, не деталь.
    t2 = tone.copy()
    for y in range(h):
        for x in range(w):
            if not fill[y, x]:
                continue
            ns = []
            for dy, dx in N4:
                ny, nx = y + dy, x + dx
                if not (0 <= ny < h and 0 <= nx < w) or not fill[ny, nx] or mat[ny, nx] != mat[y, x]:
                    ns = None
                    break
                ns.append(tone[ny, nx])
            if ns and tone[y, x] not in ns:
                t2[y, x] = int(np.median(ns))
    tone = t2

    # Ободок света: заливка, у которой сверху или слева край силуэта, а сама
    # она не в пиксель толщиной.
    out_or_edge = edge | ~inside
    lit = fill & (_shift(out_or_edge, 1, 0, True) | _shift(out_or_edge, 0, 1, True))
    rim = lit & _shift(fill, -1, 0, False) & _shift(fill, 0, -1, False)

    found = _find_head(inside, mat, outline) if face_mode != "raw" else None
    stamp_at = None
    if found is not None and face_mode in ("open", "closed"):
        stamp_at = _stamp_place(found[3], inside, face_mode)
    paint = None
    if found is not None and stamp_at is None and (found[2] & ~outline).sum() <= FACE_MAX:
        paint = _face_pass(found, ink, fill, tone, outline, rel_full_c, op_full,
                           "closed" if face_mode == "closed" else "open")
    over = {}
    if paint is not None:
        ink, fill, tone, over = paint

    # Линия внутри лица (рядом нет края силуэта) — тёмно-каштановая черта:
    # бровь, глаз; красноватая точка контура кожи читалась бы ссадиной.
    near_out = np.zeros_like(inside)
    for dy, dx in N8:
        near_out |= _shift(~inside, dy, dx, True)
    face = ink & ~near_out & (mat == SKIN)

    art = np.zeros((h, w, 4), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            if not inside[y, x]:
                continue
            ramp = RAMPS[_MATS[mat[y, x]]]
            if ink[y, x]:
                c = FEATURE if face[y, x] else ramp[0]
            else:
                t = tone[y, x] + (1 if rim[y, x] else 0)
                c = ramp[1 + min(t, len(ramp) - 2)]
            art[y, x, :3] = over.get((y, x), c)
            art[y, x, 3] = 255
    if stamp_at is not None:
        _stamp_head(art, found[3], stamp_at, face_mode)
    return art, oy


def upscale(art, oy, H, W):
    h, w = art.shape[:2]
    big = np.repeat(np.repeat(art, CELL, 0), CELL, 1)
    out = np.zeros((H, W, 4), dtype=np.uint8)
    out[oy:oy + h * CELL, :w * CELL] = big
    return out


def redraw_frame(src, gy, face_mode="open"):
    H, W = src.shape[:2]
    pad = (-W) % CELL
    if pad:
        src = np.concatenate([src, np.zeros((H, pad, 4), dtype=src.dtype)], axis=1)
    art, oy = redraw_art(src, gy, face_mode)
    out = upscale(art, oy, H, W + pad)
    return out[:, :W]


# Тёмный контур на месте светлой каймы — для листов, оставленных авторскими.
DEFRINGE_INK = hexc("221a16")


def defringe_frame(src):
    """Авторский кадр без каймы: альфа только 0/255, а светлые пиксели края
    (остаток светлой подложки листа) заменены тёмным контуром.

    Светлый край — пиксель силуэта, который светлее соседей внутри фигуры
    больше чем на 24 единицы яркости: у настоящего рисунка край — тёмная
    обводка, светлее середины он бывает только от подложки."""
    a = src.copy()
    op = a[..., 3] >= 128
    a[..., 3] = np.where(op, 255, 0)
    a[~op] = 0
    Y = _luma(a[..., :3].astype(np.float64))
    edge = np.zeros_like(op)
    for dy, dx in N4:
        edge |= op & ~_shift(op, dy, dx, False)
    inner = op & ~edge
    acc = np.zeros(Y.shape)
    cnt = np.zeros(Y.shape)
    for dy, dx in N8:
        m = _shift(inner, dy, dx, False)
        acc += np.where(m, _shift(Y * inner, dy, dx, 0.0), 0.0)
        cnt += m
    ref = np.where(cnt > 0, acc / np.maximum(cnt, 1), 0.0)
    light = edge & (cnt > 0) & (Y > ref + 24)
    a[light, :3] = DEFRINGE_INK
    return a


def redraw_sheet(src_path, dst_path, fw, gy, modes=None):
    """Перерисовать лист: кадры шириной fw, линия земли gy; modes — {кадр: режим лица}."""
    modes = modes or {}
    im = np.array(Image.open(src_path).convert("RGBA"))
    H, W = im.shape[:2]
    assert W % fw == 0, (src_path, W, fw)
    out = np.zeros_like(im)
    for i, x0 in enumerate(range(0, W, fw)):
        mode = modes.get(i, modes.get("*", "open"))
        if mode == "keep":
            out[:, x0:x0 + fw] = defringe_frame(im[:, x0:x0 + fw])
        else:
            out[:, x0:x0 + fw] = redraw_frame(im[:, x0:x0 + fw], gy, mode)
    Image.fromarray(out, "RGBA").save(dst_path)
    return W // fw


# ---------------------------------------------------------------------------
# Что перерисовывается. Путь относительно art/character/ (и hero_cut/), ширина
# кадра и линия земли — те же, что SHEET_FRAME в scripts/player/character_view.gd
# (для остальных 144/138), и режим лица по кадрам:
#   open    — голова по канону (HEAD), где силуэт головы совпал;
#   closed  — то же с закрытыми глазами (моргание, «ой», «в отключке»);
#   nostamp — лицо по канону на своей голове (дети 8–12 лет: голова другая);
#   raw     — без канона лица (лёжа: сон);
#   keep    — авторский кадр, только без светлой каймы (defringe_frame):
#             перерисовка вышла хуже авторской (экспедиционная форма — жилет,
#             ремень сумки и карманы на сетке 2×2 превращались в камуфляж).
# Кадры моргания и «ой» — индексы из character_view.gd (IDLE_X, HURT_FRAMES).
# ---------------------------------------------------------------------------
SHEETS = [
    ("idle", 144, 138, {}),
    ("idle_x", 144, 138, {0: "closed"}),
    ("walk", 144, 138, {}),
    ("fall", 144, 138, {}),
    ("jump", 144, 138, {}),
    ("hurt", 144, 138, {0: "closed", 1: "closed"}),
    ("fly", 144, 138, {}),
    ("fly_jet", 144, 138, {}),
    ("fly_1", 154, 156, {}),
    ("fly_2", 204, 163, {}),
    ("fly_3", 152, 129, {}),
    ("fly_4", 260, 123, {}),
    ("dig_pick", 192, 138, {}),
    ("dig_pick_rusty", 192, 138, {}),
    ("dig_shovel", 192, 138, {}),
    ("dig_drill_down", 144, 138, {}),
    ("dig_drill_side", 144, 138, {}),
    ("sleep", 144, 138, {"*": "raw"}),
    ("boy/walk", 144, 138, {}),
    ("boy/age_8", 47, 128, {"*": "nostamp"}),
    ("boy/age_9", 47, 128, {"*": "nostamp"}),
    ("boy/age_10", 47, 128, {"*": "nostamp"}),
    ("boy/age_11", 47, 128, {"*": "nostamp"}),
    ("boy/age_12", 47, 128, {"*": "nostamp"}),
    ("boy/age_15", 47, 128, {}),
    ("boy_gear/idle", 144, 138, {"*": "keep"}),
    ("boy_gear/walk", 144, 138, {"*": "keep"}),
    ("boy_gear/fall", 144, 138, {"*": "keep"}),
    ("boy_gear/fly", 144, 138, {"*": "keep"}),
    ("boy_gear/fly_jet", 144, 138, {"*": "keep"}),
    ("boy_gear/dig_pick", 144, 138, {"*": "keep"}),
    ("boy_gear/dig_shovel", 144, 138, {"*": "keep"}),
    ("boy_gear/sleep", 144, 138, {"*": "keep"}),
]
# Листы актёра «мальчик» в сюжете — те же файлы, что у героя (были копиями).
COPIES = {
    "boy/idle": "idle", "boy/fall": "fall", "boy/sleep": "sleep",
    "boy/dig_pick": "dig_pick", "boy/dig_pick_rusty": "dig_pick_rusty",
    "boy/dig_shovel": "dig_shovel", "boy/dig_drill_down": "dig_drill_down",
    "boy/dig_drill_side": "dig_drill_side", "boy/fly": "fly", "boy/fly_jet": "fly_jet",
}


def _png(base, rel):
    return os.path.join(base, rel + ".png")


# ---------------------------------------------------------------------------
# Лист «было/стало»: по одной позе с каждого листа в ряд — было (тёмный фон),
# стало (тёмный фон), стало на фоне игры (земля и пустая выработка в том же
# масштабе текстур, что в шахте) и стало в размере экрана 448×960 (×2/3).
# ---------------------------------------------------------------------------
SHEET_POSES = [("idle", 0), ("idle_x", 0), ("walk", 3), ("walk", 9), ("jump", 3), ("fall", 1),
               ("hurt", 0), ("fly_1", 3), ("fly_2", 3), ("fly_3", 1), ("fly_4", 1),
               ("dig_pick", 1), ("dig_pick", 4), ("dig_pick_rusty", 3), ("dig_shovel", 3),
               ("dig_drill_down", 4), ("dig_drill_side", 4), ("sleep", 0),
               ("boy_gear/idle", 0), ("boy_gear/walk", 2), ("boy/age_8", 0), ("boy/age_15", 0)]


def _frame_of(base, rel, i):
    geom = {r: (fw, gy) for r, fw, gy, _ in SHEETS}
    fw = geom[rel][0]
    im = Image.open(_png(base, rel)).convert("RGBA")
    return im.crop((i * fw, 0, (i + 1) * fw, im.height))


def _game_bg(w, h):
    """Пустая выработка (тёмная стена) сверху, земля снизу — как в шахте."""
    bg = Image.new("RGBA", (w, h), (44, 34, 30, 255))
    tile_path = os.path.join(ROOT, "art", "tiles", "dirt_1.png")
    if os.path.exists(tile_path):
        tile = Image.open(tile_path).convert("RGBA")
        for x in range(0, w, tile.width):
            bg.alpha_composite(tile, (x, h - 6))
    return bg


def before_after_sheet(out_path):
    pad = 8
    cells = []
    for rel, i in SHEET_POSES:
        cells.append((rel, _frame_of(SRC_DIR, rel, i), _frame_of(OUT_DIR, rel, i)))
    col_w = [max(b.width, a.width) for _, b, a in cells]
    row_h = max(b.height for _, b, _ in cells)
    small_h = row_h * 2 // 3
    W = sum(col_w) + pad * (len(cells) + 1) + 70
    H = row_h * 3 + small_h + pad * 6 + 14
    sheet = Image.new("RGBA", (W, H), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    font = None
    for fp in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
               "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"):
        if os.path.exists(fp):
            from PIL import ImageFont
            font = ImageFont.truetype(fp, 11)
            break
    labels = ["было", "стало", "в шахте", "экран 448"]
    ys = [14 + pad, 14 + pad * 2 + row_h, 14 + pad * 3 + row_h * 2, 14 + pad * 4 + row_h * 3]
    for k, y in enumerate(ys):
        d.text((4, y + 4), labels[k], fill=(230, 220, 160, 255), font=font)
    x = 70
    for (rel, before, after), cw in zip(cells, col_w):
        d.text((x, 0), rel, fill=(200, 200, 210, 255), font=font)
        dark = Image.new("RGBA", (cw, row_h), (36, 40, 50, 255))
        for k, im in enumerate((before, after)):
            cell = dark.copy()
            cell.alpha_composite(im, (0, row_h - im.height))
            sheet.alpha_composite(cell, (x, ys[k]))
        # Линия земли в кадре ~ на 6 текселей выше низа кадра.
        game = _game_bg(cw, row_h + 96)
        game = game.crop((0, 96 - (row_h - 6) + row_h - 6, cw, 96 + row_h))
        game = _game_bg(cw, row_h)
        cell = game.copy()
        cell.alpha_composite(after, (0, row_h - after.height))
        sheet.alpha_composite(cell, (x, ys[2]))
        small = cell.resize((cw * 2 // 3, small_h), Image.BILINEAR)
        sheet.alpha_composite(small, (x, ys[3]))
        x += cw + pad
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet.convert("RGB").save(out_path)
    return sheet.size


def main(argv):
    if "--sheet" in argv:
        out = argv[argv.index("--sheet") + 1]
        print("лист было/стало:", out, before_after_sheet(out))
        return
    only = [a for a in argv if not a.startswith("-")]
    if "--take" in argv:
        assert only, "--take без списка листов забрал бы в снимок уже перерисованное"
        for rel in only:
            Image.open(_png(OUT_DIR, rel)).save(_png(SRC_DIR, rel))
            print("%-22s нарезка -> hero_cut/" % rel)
    done = []
    for rel, fw, gy, modes in SHEETS:
        if only and rel not in only:
            continue
        n = redraw_sheet(_png(SRC_DIR, rel), _png(OUT_DIR, rel), fw, gy, modes)
        done.append(rel)
        print("%-22s %2d кадр(ов) по %d px" % (rel, n, fw))
    for dst, src in COPIES.items():
        if src in done:
            Image.open(_png(OUT_DIR, src)).save(_png(OUT_DIR, dst))
            print("%-22s = %s" % (dst, src))


if __name__ == "__main__":
    main(sys.argv[1:])
