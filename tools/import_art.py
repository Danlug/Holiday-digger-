#!/usr/bin/env python3
"""import_art.py — нарезка авторского листа персонажей и предметов в игровые спрайты.

Лист нарисован крупно (персонаж ~306 px в высоту) и сохранён в JPEG, поэтому
прямая нарезка даёт грязь по краям. Порядок здесь такой:

  1. фон заливается от краёв, а не отсекается по цвету — иначе седые волосы
     бабки и стальной бур, которые сами серые, выгрызаются вместе с фоном;
  2. цвет усредняется с премультиплированной альфой, иначе по контуру
     появляется серая кайма от фона;
  3. альфа режется по порогу, палитра квантуется — спрайт снова становится
     пиксель-артом, а не уменьшенной фотографией.

Анимации собираются из одной стоячей позы: спрайт делится на полосы
(голова / корпус / ноги) и полосы смещаются покадрово. Для 20×40 этого
достаточно: на таком размере читается сам факт шага, а не его анатомия.

У ГЕРОЯ так собирается только покой: движение (ходьба, падение, оба полёта)
нарезается из авторского листа в tools/import_move.py, копка — в
tools/import_dig.py. Нарисованные кадры лучше собранных, и там, где они
есть, процедурная сборка не запускается вовсе.

Запуск:  python3 tools/import_art.py <путь-к-листу.jpg>
"""

import math
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Во сколько раз текстуры подробнее игровых координат.
#
# Игра считает мир в клетках по 32 «логических» пикселя, но рисует их на
# телефоне, где на такую клетку приходится полторы сотни настоящих. Пока арт
# нарезался ровно в логический размер, экран растягивал его впятеро ближайшим
# соседом — отсюда «пацан в клеточку». Художник присылает фигуры по 100-290 px
# высотой, то есть подробностей у нас в разы больше, чем мы брали.
#
# Теперь текстуры режутся в ART_SCALE раз крупнее, а рисуются во столько же
# раз уменьшенными (см. ART_SCALE в scripts/player/character_view.gd и
# scripts/world/world_view.gd). Координаты игры при этом не меняются вовсе.
# Тройка — потому что столько реальной подробности есть в самых бедных листах
# (ходьба, полёт: фигура ~105 px при росте 120); больше было бы растягиванием
# пустоты.
ART_SCALE = 3

# Ниже этого значения альфа считается шумом ресемплинга, а не краем рисунка.
ALPHA_FLOOR = 8

TILE = 32 * ART_SCALE
FRAME_W = 48 * ART_SCALE   # кадр персонажа 48×48 логических. Шире клетки
FRAME_H = 48 * ART_SCALE   # намеренно: в 32 px не помещались ни замах киркой,
                           # ни винты ранца, и спрайт приходилось ужимать под
                           # ширину — герой худел, стоило ему начать копать
BODY_H = 40 * ART_SCALE    # рост героя (авторская метка 20×40 логических)
FOOT_PAD = 2 * ART_SCALE   # отступ от низа кадра до подошвы

# Прямоугольники на листе. Найдены заливкой фона и разбором компонент,
# записаны числами, чтобы нарезка была повторяемой.
CHARACTERS = {
    "boy":            (57, 40, 155, 327),      # внук, 16 лет
    "boy_gear":       (1241, 37, 1354, 327),   # он же в экспедиционной форме
    "grandpa":        (765, 22, 895, 327),     # дед дома
    # Рука с компасом обрезана намеренно: вытянутая вбок рука делает спрайт
    # в полтора раза шире тела, и при вписывании в кадр 32 px дед становится
    # приземистым. Полная поза сохраняется отдельно — под катсцену.
    "grandpa_gear":   (1005, 19, 1120, 327),   # дед в форме
    "grandma_poor":   (288, 45, 412, 327),     # бабка до богатства
    "grandma_rich":   (526, 19, 639, 327),     # бабка после смерти деда
}

# Кирки с ЭТОГО листа больше не сохраняются: весь ряд из шести приходит с
# отдельного авторского листа через tools/import_pickaxes.py, одним масштабом
# и в одной ориентации (см. его шапку). Вырезать их отсюда всё равно надо —
# ржавая кирка идёт реквизитом в процедурную сборку копки (anim_dig), — а вот
# записывать поверх нельзя: запуск import_art.py затёр бы ряд и сломал
# «чем дороже, тем крупнее».
SUPERSEDED_ITEMS = {"items/pickaxe_rusty", "items/pickaxe_iron"}

ITEMS = {
    # имя файла: (бокс на листе, размер результата)
    "items/pickaxe_rusty":      ((58, 376, 132, 450), (32, 32)),
    "items/shovel":             ((213, 376, 285, 450), (32, 32)),
    "items/pickaxe_iron":       ((357, 376, 428, 450), (32, 32)),
    "items/backpack_propeller": ((490, 378, 636, 492), (32, 32)),
    "items/jetpack":            ((669, 383, 766, 499), (32, 32)),
    "items/hand_drill":         ((832, 408, 944, 591), (32, 32)),
    "ui/icon_inventory":        ((525, 520, 599, 595), (32, 32)),
    "ui/icon_dollar":           ((649, 521, 707, 593), (32, 32)),
    "env/workbench":            ((747, 648, 849, 739), (32, 32)),
    "env/bed":                  ((877, 640, 954, 739), (32, 32)),
    "env/drill_mobile":         ((505, 625, 727, 740), (64, 32)),
}


# ---------------------------------------------------------------------------
# Вырезание из листа
# ---------------------------------------------------------------------------

def background_mask(im):
    """True там, где фон. Заливка от краёв: серое внутри спрайта остаётся."""
    px = im.load()
    w, h = im.size

    def bg_like(p):
        r, g, b = p
        if abs(r - g) > 10 or abs(g - b) > 10:
            return False
        return abs(r - 217) <= 12 or abs(r - 194) <= 12

    mask = [[False] * w for _ in range(h)]
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if seen[y][x]:
            continue
        seen[y][x] = True
        if not bg_like(px[x, y]):
            continue
        mask[y][x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny][nx]:
                q.append((ny, nx))
    return mask


def cut(im, mask, box):
    """Кусок листа с альфой по маске фона, обрезанный по содержимому."""
    x0, y0, x1, y1 = box
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not mask[y][x]:
                r, g, b = src[x, y]
                dst[x - x0, y - y0] = (r, g, b, 255)
    return out.crop(out.getbbox())



# ---------------------------------------------------------------------------
# Приведение тона листа к эталону
# ---------------------------------------------------------------------------
#
# Листы сняты с разной экспозицией. Замер по одинаковым деталям — синей
# футболке и коже лица — показывает разброс, который видно невооружённым
# глазом: кожа в листе ходьбы 152,125,111 против 204,161,133 в стойке. В игре
# это читается так, будто герой сереет, стоило ему пойти.
#
# Поэтому каждый лист приводится к эталону — к тому, из которого взята
# спокойная поза (characters_sheet). Две опорные детали дают на канал две
# точки, через них проводится прямая: одна только яркость разброс не
# выпрямляет, потому что светлая кожа просела сильнее тёмной футболки — то
# есть у листов разный контраст, а не только экспозиция.
SKIN_REF = (203.6, 160.8, 132.8)
SHIRT_REF = (72.1, 96.4, 137.4)


def _anchor_pixels(px, w, h, is_fg):
    """Пиксели кожи и футболки среди фигуры — по ним и сверяются листы.

    Именно эти две детали есть на каждом листе и ни разу не меняются по
    замыслу. Считать по всей фигуре нельзя: на листе бура половина кадра —
    машина, на листе ранцев — снаряжение, и среднее поехало бы за ними.
    """
    out = []
    for y in range(h):
        for x in range(w):
            if not is_fg(x, y):
                continue
            r, g, b = px[x, y][:3]
            if (b > r * 1.15 and b > 60) or (r > g * 1.05 and g > b * 1.05 and r > 110):
                out.append((r, g, b))
    return out


def _lum_sat(pixels):
    """Средняя яркость и средняя насыщенность набора пикселей."""
    if not pixels:
        return None
    lum = 0.0
    sat = 0.0
    for r, g, b in pixels:
        l = 0.299 * r + 0.587 * g + 0.114 * b
        mx = max(r, g, b)
        lum += l
        sat += 0.0 if mx == 0 else (mx - min(r, g, b)) / mx
    n = float(len(pixels))
    return lum / n, sat / n


# Эталон — тот лист, из которого взята спокойная поза (characters_sheet):
# яркость и насыщенность кожи с футболкой на нём.
REF_LUM = 121.2
REF_SAT = 0.416


def tone_match(sheet, mask):
    """Приводит тон листа к эталону. Возвращает новый RGB-образ.

    Правятся ровно две величины — общая яркость и насыщенность, — и обе одним
    числом на весь лист. Оттенки при этом не двигаются вовсе: подкрутка
    каналов порознь красиво ложится на эталон и переворачивает цвета на
    остальных листах (футболка уходила в фиолетовый), потому что «кожа» и
    «футболка» на разных листах набираются из чуть разных пикселей, и половина
    разницы между опорами — от детектора, а не от экспозиции.

    mask — маска фона от заливки (1 = фон): опорные цвета берутся только по
    фигуре. Мало опорных пикселей (лист без персонажа) — лист не трогаем.
    """
    w, h = sheet.size
    px = sheet.load()
    stat = _lum_sat(_anchor_pixels(px, w, h, lambda x, y: not mask[y * w + x]))
    if stat is None:
        return sheet
    lum, sat = stat
    k_lum = min(max(REF_LUM / max(1.0, lum), 0.7), 1.7)
    k_sat = min(max(REF_SAT / max(0.01, sat), 0.7), 1.8)

    out = Image.new("RGB", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            l = 0.299 * r + 0.587 * g + 0.114 * b
            # Насыщенность тянется ОТ СОБСТВЕННОЙ яркости пикселя, поэтому
            # серое остаётся серым, а цветное набирает цвет, не меняя тона.
            nr = l + (r - l) * k_sat
            ng = l + (g - l) * k_sat
            nb = l + (b - l) * k_sat
            op[x, y] = (max(0, min(255, int(round(nr * k_lum)))),
                        max(0, min(255, int(round(ng * k_lum)))),
                        max(0, min(255, int(round(nb * k_lum)))))
    return out


# Подрезкость после уменьшения: насколько её добавлять и с какого запаса
# подробностей она уже не нужна.
SHARPEN_RADIUS = 1.2
SHARPEN_MAX_PERCENT = 100
SHARPEN_THRESHOLD = 2
SHARPEN_RICH_RATIO = 2.0    # исходник вдвое крупнее цели — резкости и так вдоволь
SHARPEN_POOR_RATIO = 1.2    # почти впритык — добавляем на полную


def _restore_bite(img, src_h, dst_h):
    """Вернуть кадру резкость, потерянную при масштабировании.

    Сила зависит от того, сколько подробностей было в исходнике. Лист
    персонажей даёт фигуру в 287 px на кадр в 120 — там после уменьшения край
    и так звонкий, и подрезать его значит получить ореолы. Листы анимаций
    дают 106-150 px, то есть почти впритык, и после масштабирования картинка
    мягкая — вот там подрезкость и нужна.

    Ничего не выдумывает: подчёркивает то, что в кадре уже есть. Разницу в
    подробности исходников это не отменяет — см. docs/BUILD.md.
    """
    ratio = src_h / max(1.0, float(dst_h))
    t = (SHARPEN_RICH_RATIO - ratio) / (SHARPEN_RICH_RATIO - SHARPEN_POOR_RATIO)
    t = max(0.0, min(1.0, t))
    if t <= 0.0:
        return img
    percent = int(round(SHARPEN_MAX_PERCENT * t))
    if percent <= 0:
        return img
    rgb = img.convert("RGB").filter(ImageFilter.UnsharpMask(
        radius=SHARPEN_RADIUS, percent=percent, threshold=SHARPEN_THRESHOLD))
    return Image.merge("RGBA", rgb.split() + (img.getchannel("A"),))


def shrink(img, size, colors=0):
    """Уменьшение с премультиплированной альфой.

    Две вещи здесь делались ради «пиксельного» вида и обе били по качеству,
    которого владелец как раз и ждал от присланных рисунков:

      1. КВАНТОВАНИЕ палитры в 20-32 цвета. Именно от него лицо и одежда
         распадались на плоские пятна. Теперь по умолчанию выключено
         (colors=0); параметр оставлен для случаев, где палитра нужна
         намеренно.

      2. ЖЁСТКИЙ ПОРОГ альфы: всё полупрозрачное либо становилось
         непрозрачным, либо исчезало. На уменьшении это давало рваный контур
         и осыпавшиеся тонкие места — те самые «артефакты и плохая обрезка».
         Теперь край сглажен: альфа переносится как есть, а цвет берётся из
         премультиплированного изображения, поэтому по краю не лезет чёрный.
    """
    w, h = img.size
    tw, th = size

    pm = Image.new("RGB", (w, h), (0, 0, 0))
    al = Image.new("L", (w, h), 0)
    ip, pp, ap = img.load(), pm.load(), al.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = ip[x, y]
            if a:
                pp[x, y] = (r, g, b)
                ap[x, y] = 255

    # LANCZOS, а не BOX: на уменьшении в 2-7 раз он держит мелочи (глаза,
    # пряжки, зубья кирки), которые усреднение площадью просто смывает.
    resample = Image.LANCZOS if (tw < w or th < h) else Image.BICUBIC
    pm = pm.resize((tw, th), resample)
    al = al.resize((tw, th), resample)

    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    op, pp, ap = out.load(), pm.load(), al.load()
    for y in range(th):
        for x in range(tw):
            a = ap[x, y]
            if a < ALPHA_FLOOR:   # совсем призрачное — это шум ресемплинга
                continue
            r, g, b = pp[x, y]
            k = 255.0 / a         # снимаем премультипликацию
            op[x, y] = (min(255, int(r * k)), min(255, int(g * k)),
                        min(255, int(b * k)), a)

    out = _restore_bite(out, h, th)

    if colors > 0:
        rgb = Image.new("RGB", (tw, th), (0, 0, 0))
        rp = rgb.load()
        op = out.load()
        for y in range(th):
            for x in range(tw):
                rp[x, y] = op[x, y][:3]
        q = rgb.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        qp = q.load()
        for y in range(th):
            for x in range(tw):
                if op[x, y][3]:
                    op[x, y] = qp[x, y] + (op[x, y][3],)
    return out


def fit(img, size):
    """Вписать по большей стороне, не искажая пропорции."""
    w, h = img.size
    tw, th = size
    k = min(tw / w, th / h)
    return shrink(img, (max(1, round(w * k)), max(1, round(h * k))))


def paste_center(body, size, bottom_pad=0):
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - body.size[0]) // 2
    y = size[1] - bottom_pad - body.size[1]
    out.alpha_composite(body, (x, y))
    return out


# ---------------------------------------------------------------------------
# Анимация из одной позы
# ---------------------------------------------------------------------------
#
# Всё собирается в РАЗРЕШЕНИИ ИСХОДНИКА и уменьшается только готовым кадром.
# Если двигать и поворачивать уже уменьшенный спрайт, куски рвутся по швам и
# анимация выглядит рубленой — именно так выглядела первая версия.
#
# Тело режется на полосы. Границы — доли роста, а не пиксели: у деда и у
# внука разные пропорции, а доли работают для обоих.
HEAD = 0.00, 0.30
TORSO = 0.30, 0.64
LEGS = 0.64, 1.00

# Рука, которой персонаж работает. Берём ту, что справа — спрайт по умолчанию
# смотрит вправо. Ширина в долях тела: рука вырезается не прямоугольником, а
# по силуэту, иначе вместе с ней выкусывается край туловища и тело выглядит
# разрезанным.
ARM_W = 0.15
ARM_Y0, ARM_Y1 = 0.31, 0.60


def band(img, lo, hi):
    h = img.size[1]
    return img.crop((0, round(h * lo), img.size[0], round(h * hi)))


def compose_src(body, dy_body=0, legs=None, pad=None):
    """Кадр в разрешении исходника.

    Корпус и голова по горизонтали НЕ разъезжаются: любой сдвиг полосы вбок
    оставляет ступеньку на шве и читается как разрыв спрайта. Двигаются
    только ноги (они и так отдельные) и всё тело по вертикали.

    legs — (dxL, dyL, dxR, dyR) в долях ширины тела.
    """
    w, h = body.size
    if pad is None:
        pad = max(4, w // 5)
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))

    upper = body.crop((0, 0, w, round(h * LEGS[0])))
    legs_img = body.crop((0, round(h * LEGS[0]), w, h))
    y_legs = round(h * LEGS[0])

    out.alpha_composite(upper, (pad, pad + dy_body))
    if legs is None:
        out.alpha_composite(legs_img, (pad, pad + y_legs + dy_body))
    else:
        dxl, dyl, dxr, dyr = (round(v * w) if abs(v) < 1 else v for v in legs)
        mid = w // 2
        left = legs_img.crop((0, 0, mid, legs_img.size[1]))
        right = legs_img.crop((mid, 0, w, legs_img.size[1]))
        out.alpha_composite(left, (pad + dxl, pad + y_legs + dyl + dy_body))
        out.alpha_composite(right, (pad + mid + dxr, pad + y_legs + dyr + dy_body))
    return out


# ---------------------------------------------------------------------------
# Якорь кадра: голова
# ---------------------------------------------------------------------------
#
# Кадры набора сводятся ПО ГОЛОВЕ, а не по рамке содержимого. Рамку
# растягивают инструмент в замахе, лопасти винта, мачта ранца и разлетающаяся
# порода, причём в каждом кадре по-своему: её середина гуляет сама по себе, и
# персонаж, собранный по рамке, шатается вправо-влево. Голова же есть в
# каждом кадре, компактна и при работе почти не ходит в стороны — ноги для
# этого не годятся (они и должны двигаться), а рамка тем более.

HEAD_ERODE = 0.03     # насколько сужать силуэт, в долях роста
HEAD_BAND = 0.10      # высота головы, в долях роста
HEAD_MIN_AREA = 0.25  # доля от самого крупного массива, ниже — не тело


def _rows_of_runs(img):
    """Горизонтальные пробеги непрозрачных пикселей по строкам."""
    w, h = img.size
    data = img.tobytes()
    rows = []
    for y in range(h):
        line = data[y * w:(y + 1) * w]
        rr, x = [], 0
        while True:
            a = line.find(b"\xff", x)
            if a < 0:
                break
            b = line.find(b"\x00", a)
            if b < 0:
                b = w
            rr.append((a, b - 1))
            x = b
        rows.append(rr)
    return rows


def _blobs(rows):
    """Связные массивы из пробегов. Возвращает список (площадь, верх, пробеги)."""
    parent = []

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[b] = a

    ids, prev, prev_ids = [], [], []
    for rr in rows:
        cur = []
        for a, b in rr:
            parent.append(len(parent))
            i = len(parent) - 1
            for j, (pa, pb) in enumerate(prev):
                if pa <= b + 1 and a <= pb + 1:      # касаются, в том числе углом
                    union(prev_ids[j], i)
            cur.append(i)
        ids.append(cur)
        prev, prev_ids = rr, cur

    out = {}
    for y, (rr, cur) in enumerate(zip(rows, ids)):
        for (a, b), i in zip(rr, cur):
            g = out.setdefault(find(i), [0, y, []])
            g[0] += b - a + 1
            g[2].append((y, a, b))
    return list(out.values())


def head_x(img, body_src_h):
    """X-координата середины головы в координатах img."""
    return head_anchor(img, body_src_h)[0]


def head_anchor(img, body_src_h):
    """Голова в координатах img: (X середины, Y макушки).

    Y макушки нужен там, где кадры сводятся по вертикали не по низу
    содержимого: в кадрах полёта ниже ступней нарисовано пламя, и низ
    содержимого — уже не подошва.

    Силуэт сужается на HEAD_ERODE роста — отваливается всё тонкое: черенок
    инструмента, мачта ранца, лопасть винта, крошка породы. Остаются плотные
    массивы: тело и, отдельно, крупный реквизит (боёк кирки, куча камней).
    Из них берётся самый ВЕРХНИЙ среди достаточно крупных — боёк после
    сужения мелкий и отсеивается по площади, а камни лежат ниже головы.
    Верхние строки выбранного массива и есть голова.
    """
    box = img.getbbox()
    if box is None:
        return img.size[0] / 2.0, 0
    r = max(1, round(body_src_h * HEAD_ERODE))
    band = max(1, round(body_src_h * HEAD_BAND))

    solid = img.getchannel("A").point(lambda v: 255 if v else 0)
    for _ in range(r):                    # сужение на 1 px, r раз: одно большое
        solid = solid.filter(ImageFilter.MinFilter(3))   # ядро PIL считает долго
    blobs = _blobs(_rows_of_runs(solid))
    if not blobs:
        return (box[0] + box[2] - 1) / 2.0, box[1]

    big = max(b[0] for b in blobs)
    body = min((b for b in blobs if b[0] >= big * HEAD_MIN_AREA),
               key=lambda b: b[1])
    top = body[1]
    xs = [(a, b) for y, a, b in body[2] if y < top + band]
    n = sum(b - a + 1 for a, b in xs)
    return sum((a + b) * (b - a + 1) / 2.0 for a, b in xs) / n, top


def head_x_anchored(img, top_y, body_src_h, pad=2):
    """X головы, когда её Y УЖЕ известен антропометрически, а не выводится
    из формы силуэта (см. head_anchor).

    head_anchor берёт САМЫЙ ВЕРХНИЙ достаточно крупный массив силуэта — и
    ошибается ровно тогда, когда над головой оказывается что-то ещё
    крупное: инструмент в замахе "занёс за голову" (см. tools/import_dig.py
    — покадровая копка, где рисованные кадры дают именно такую позу).
    Тогда "голова" алгоритма — боёк кирки, и он гуляет по кадрам замаха
    вместе с рукой на добрый десяток логических px — герой на экране
    буквально прыгает. Здесь вместо поиска головы по силуэту берём Y
    заранее — рост в спокойной позе стоя известен (голова всегда на одной
    высоте над ступнями, торс почти не наклоняется даже во время замаха,
    см. shrink_set) — и просто ищем плотную заливку в узкой полосе вокруг
    этого Y. Инструмент, поднятый ВЫШЕ головы, лежит выше этой полосы и в
    неё не попадает вообще — там его просто нет.
    """
    w, h = img.size
    r = max(1, round(body_src_h * HEAD_ERODE))
    band = max(1, round(body_src_h * HEAD_BAND))
    y0 = max(0, int(round(top_y)) - pad)
    y1 = min(h, int(round(top_y + band)) + pad)
    if y1 <= y0:
        return w / 2.0

    solid = img.getchannel("A").point(lambda v: 255 if v else 0)
    for _ in range(r):
        solid = solid.filter(ImageFilter.MinFilter(3))
    px = solid.load()
    total = 0
    wsum = 0.0
    for y in range(y0, y1):
        for x in range(w):
            if px[x, y]:
                total += 1
                wsum += x
    if total == 0:
        return head_x(img, body_src_h)   # полоса пуста — откат на старый поиск
    return wsum / total


def shrink_set(frames, body_src_h, fit_height=True, heads=None):
    """Уменьшить набор кадров ОДНИМ масштабом, сведя их по голове.

    Масштаб один на набор — иначе персонаж то толстеет, то худеет по ходу
    анимации.

    По ГОРИЗОНТАЛИ кадры сводятся по голове (см. head_x выше) и кладутся на
    симметричный относительно неё холст. Симметричный — чтобы strip(), который
    центрирует картинку в клетке, ставил голову ровно в середину кадра: тогда
    наборы не разъезжаются между собой (герой не прыгает вбок при переходе с
    ходьбы на копку), а при развороте по facing голова не уезжает — середина
    кадра и есть ось отражения.

    По ВЕРТИКАЛИ кадры сводятся по низу своего холста: сборщики поз
    (compose_src, anim_dig, anim_fly) кладут тело на низ холста, так что это
    общая линия земли. По низу СОДЕРЖИМОГО равнять нельзя — тогда пропадут
    приседание, подскок и шаг.

    heads — готовый список X-координат головы по кадрам, если он уже
    известен точнее, чем даёт head_x() (см. anim_dig: замах поднимает
    инструмент ВЫШЕ головы, и "самый верхний плотный массив силуэта" —
    уже не голова, а боёк. Раньше это качало собранного циркулярной сборкой
    деда/бабку на 6-8 логических px между кадрами замаха — ровно то, что
    владелец увидел как "анимации скачут"). Без heads каждый кадр
    выравнивается по своей собственной оценке головы, как раньше.
    """
    boxes = [f.getbbox() for f in frames]
    heads = heads if heads is not None else [head_x(f, body_src_h) for f in frames]

    # полуширина: как далеко содержимое уходит от головы в самую дальнюю сторону
    half = max(1, math.ceil(max(max(hx - b[0], b[2] - hx)
                                for b, hx in zip(boxes, heads))))
    tops = [f.size[1] - b[1] for f, b in zip(frames, boxes)]
    top = max(tops)
    bot = min(f.size[1] - b[3] for f, b in zip(frames, boxes))
    w, h = half * 2, top - bot

    k = min(BODY_H / body_src_h, FRAME_W / w)
    if fit_height:
        k = min(k, (FRAME_H - FOOT_PAD) / h)
    # ширина ЧЁТНАЯ: только тогда центрирование в strip() попадает в середину
    # кадра ровно, а не на полпикселя вбок — а полпикселя после округления
    # и есть дрожание на единицу
    size = (max(2, 2 * round(half * k)), max(1, round(h * k)))

    out = []
    for f, b, hx, t in zip(frames, boxes, heads, tops):
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.alpha_composite(f.crop(b), (half - round(hx - b[0]), top - t))
        out.append(shrink(canvas, size))
    return out


def strip(frames, frame_w=FRAME_W, frame_h=FRAME_H, bottom_pad=FOOT_PAD):
    """Горизонтальная полоса кадров 48×48 — формат, который читают оба рендерера."""
    sheet = Image.new("RGBA", (frame_w * len(frames), frame_h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        x = i * frame_w + (frame_w - f.size[0]) // 2
        y = frame_h - bottom_pad - f.size[1]
        sheet.alpha_composite(f, (x, y))
    return sheet


# --- походка и покой -------------------------------------------------------

def anim_idle(body):
    # Дыхание на четыре кадра: вверх — держим — вниз — держим. На двух кадрах
    # это дёргалось, потому что смена шла каждые полкадра анимации.
    return [compose_src(body, dy_body=d) for d in (0, -1, -2, -1)]


# Шаг: шесть фаз вместо четырёх. Четырёх мало — из них две одинаковые
# («ноги вместе»), и цикл читается как три позы вместо походки.
WALK = (
    (-0.10, 0.00, 0.10, -0.03),
    (-0.05, -0.02, 0.05, -0.01),
    (0.00, 0.00, 0.00, 0.00),
    (0.10, -0.03, -0.10, 0.00),
    (0.05, -0.01, -0.05, -0.02),
    (0.00, 0.00, 0.00, 0.00),
)
WALK_BOB = (0, -1, 0, 0, -1, 0)


def anim_walk(body):
    return [compose_src(body, dy_body=b, legs=l) for l, b in zip(WALK, WALK_BOB)]


def anim_fall(body):
    # Ноги разъезжаются и подрагивают — «не успел сгруппироваться».
    return [
        compose_src(body, dy_body=0, legs=(-0.09, 0, 0.09, 0)),
        compose_src(body, dy_body=-1, legs=(-0.12, -0.02, 0.12, 0.01)),
        compose_src(body, dy_body=0, legs=(-0.07, 0.01, 0.10, -0.01)),
    ]


def anim_sleep(body):
    # Лежит: поворот всего тела на 90°, отдельной позы для сна в листе нет.
    return [body.rotate(90, expand=True)]


# --- полёт со снаряжением --------------------------------------------------
#
# Персонаж нарисован анфас: ранец, положенный целиком за спину, не виден
# вовсе — туловище закрывает его полностью. Поэтому ранец разбирается на две
# части. Мешок уходит за спину, а винты поднимаются НАД ГОЛОВОЙ на мачте:
# только так сразу понятно, что герой висит на пропеллерах, а не сам по себе.

BAR_SHARE = 0.28      # какая доля высоты ранца сверху — это винты
BAG_WIDE = 1.35       # мешок в долях ширины тела (уже тела — и его не
                      # видно вовсе: спрятан за корпусом)
BLADE_SPAN = 2.4      # размах винта в долях ширины тела
BAR_ABOVE = 0.15      # насколько винт выше макушки, в долях роста
MAST_W = 0.09         # толщина мачты в долях ширины тела


def _split_pack(gear):
    h = gear.size[1]
    cut_y = round(h * BAR_SHARE)
    return gear.crop((0, 0, gear.size[0], cut_y)), gear.crop((0, cut_y, gear.size[0], h))


def _dark_of(img):
    """Самый тёмный непрозрачный цвет — им красим мачту, чтобы она читалась
    как часть ранца, а не как посторонняя палка."""
    p = img.load()
    best, score = (60, 48, 38, 255), 1e9
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            c = p[x, y]
            if c[3] and sum(c[:3]) < score:
                score, best = sum(c[:3]), c
    return best


def _scaled(img, w):
    k = w / img.size[0]
    return img.resize((max(1, round(w)), max(1, round(img.size[1] * k))), Image.LANCZOS)


def _bar(w, h, color):
    return Image.new("RGBA", (max(1, round(w)), max(1, round(h))), color)


def anim_fly_poses(body):
    return [
        compose_src(body, dy_body=-1, legs=(0.05, -0.04, -0.05, -0.04)),
        compose_src(body, dy_body=-3, legs=(0.06, -0.06, -0.06, -0.06)),
        compose_src(body, dy_body=-2, legs=(0.05, -0.05, -0.05, -0.05)),
    ]


def anim_fly(body, gear, kind):
    """kind: 'prop' — мешок за спиной и винт над головой на мачте;
             'jet'  — баки по бокам корпуса, сопла из-за ног."""
    poses = anim_fly_poses(body)
    w, body_h = body.size
    pad_top = (poses[0].size[1] - body_h) // 2
    frames = []

    if kind == "jet":
        for i, pose in enumerate(poses):
            g = _scaled(gear, w * 1.25)
            out = Image.new("RGBA", pose.size, (0, 0, 0, 0))
            gy = pad_top + round(body_h * 0.78) - g.size[1] - (i % 2)
            out.alpha_composite(g, ((pose.size[0] - g.size[0]) // 2, gy))
            out.alpha_composite(pose)
            frames.append(out)
        return frames

    # Винт рисуется сплошными прямоугольниками, а НЕ берётся картинкой из
    # листа. Нарисованные лопасти шириной в пиксель после уменьшения до 40 px
    # роста осыпаются в редкие точки — вместо винта получается сор над
    # головой. Сплошная планка переживает уменьшение.
    bar_src, bag_src = _split_pack(gear)
    metal = _dark_of(bag_src)
    # Лопасти — светлая сталь: умножать тёмный цвет ранца бесполезно, он
    # так и остаётся чёрной палкой на тёмном фоне пещеры.
    blade = tuple(round(c * 0.25 + s * 0.75) for c, s in zip(metal[:3], (198, 202, 208))) + (255,)

    mast_w = max(3, round(w * MAST_W))
    blade_h = max(3, round(body_h * 0.022))
    hub = max(4, round(w * 0.14))

    for i, pose in enumerate(poses):
        bob = -(i % 2)
        bag = _scaled(bag_src, w * BAG_WIDE)
        # лопасти «крутятся»: размах то полный, то поджатый — на 40 px роста
        # это единственный читаемый способ показать вращение
        span = round(w * BLADE_SPAN * (1.0, 0.45, 0.78)[i])

        # Холст расширяется и вверх: винт уходит выше макушки, а PIL молча
        # обрезает всё, что вышло за край — из-за этого лопасти пропадали
        # целиком, оставляя торчать один хаб.
        bar_y0 = pad_top - round(body_h * BAR_ABOVE) + bob
        up = max(0, blade_h - bar_y0 + round(body_h * 0.02))
        extra = max(0, (span - pose.size[0]) // 2 + 3)
        size = (pose.size[0] + extra * 2, pose.size[1] + up)
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        cx = size[0] // 2

        bag_y = up + pad_top + round(body_h * 0.56) - bag.size[1] + bob
        bar_y = up + bar_y0

        mast_top = bar_y + blade_h
        mast_bot = bag_y + round(bag.size[1] * 0.35)
        if mast_bot > mast_top:
            out.alpha_composite(_bar(mast_w, mast_bot - mast_top, metal),
                                (cx - mast_w // 2, mast_top))
        out.alpha_composite(bag, (cx - bag.size[0] // 2, bag_y))
        out.alpha_composite(pose, (extra, up))
        out.alpha_composite(_bar(span, blade_h, blade), (cx - span // 2, bar_y))
        out.alpha_composite(_bar(hub, blade_h * 2, metal),
                            (cx - hub // 2, bar_y - blade_h // 2))
        frames.append(out)
    return frames


# --- копка -----------------------------------------------------------------
#
# Рука из ДВУХ звеньев. Одно жёсткое звено, повёрнутое от плеча, выглядит как
# палка с киркой на конце: человек так не машет. Плечо поворачивается от
# плечевого сустава, предплечье — от локтя, а инструмент закреплён в кисти и
# едет вместе с предплечьем.
#
# Углы отсчитываются от «рука висит вниз», по часовой стрелке (вперёд).
# Предплечье задано ОТНОСИТЕЛЬНО плеча — так поза читается как сгиб локтя,
# а не как два независимых поворота.
SWING = (
    # (плечо, локоть относительно плеча, наклон корпуса)
    (-95, -65, 0),    # занёс за голову, локоть сложен
    (-70, -45, 0),    # начал разгон
    (-25, -15, 0),    # рука распрямляется
    (8, -5, -1),      # идёт вниз
    (38, 0, -2),      # удар: рука прямая, кирка в земле
    (-20, -50, -1),   # отвод назад, локоть снова сгибается
)

ELBOW = 0.46          # где локоть по длине руки
TOOL_LEN = 0.40       # длина инструмента в долях РОСТА


def take_arm(body):
    """Снять рабочую руку с тела, следуя силуэту.

    Рука — это крайние пиксели силуэта, а не прямоугольник: если резать
    прямоугольником, вместе с рукой уходит край туловища и тело выглядит
    разрезанным.
    """
    w, h = body.size
    y0, y1 = round(h * ARM_Y0), round(h * ARM_Y1)
    arm_w = max(2, round(w * ARM_W))

    torso = body.copy()
    arm = Image.new("RGBA", (arm_w, y1 - y0), (0, 0, 0, 0))
    tp, ap = torso.load(), arm.load()
    left_edge = w

    for y in range(y0, y1):
        right = None
        for x in range(w - 1, -1, -1):
            if tp[x, y][3]:
                right = x
                break
        if right is None:
            continue
        start_x = max(0, right - arm_w + 1)
        left_edge = min(left_edge, start_x)
        for i, x in enumerate(range(start_x, right + 1)):
            ap[i, y - y0] = tp[x, y]
            tp[x, y] = (0, 0, 0, 0)
    return torso, arm, (left_edge, y0)


def normalize_tool(tool):
    """Поставить инструмент черенком вверх, бойком вниз.

    На листе инструменты нарисованы по диагонали и каждый под своим углом.
    Чтобы класть их в кисть одинаково, находим главную ось по облаку
    непрозрачных пикселей и разворачиваем её вертикально. Тяжёлый конец
    (боёк, полотно лопаты) уводим ВНИЗ — в замахе он должен смотреть от
    тела, а не в лицо.
    """
    p = tool.load()
    pts = [(x, y) for y in range(tool.size[1]) for x in range(tool.size[0])
           if p[x, y][3]]
    n = len(pts)
    mx = sum(q[0] for q in pts) / n
    my = sum(q[1] for q in pts) / n
    sxx = sum((q[0] - mx) ** 2 for q in pts) / n
    syy = sum((q[1] - my) ** 2 for q in pts) / n
    sxy = sum((q[0] - mx) * (q[1] - my) for q in pts) / n
    ang = 0.5 * math.atan2(2 * sxy, sxx - syy)     # главная ось
    out = tool.rotate(math.degrees(ang) - 90, expand=True,
                      resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0))
    out = out.crop(out.getbbox())

    op = out.load()
    half = out.size[1] // 2
    top = sum(1 for y in range(half) for x in range(out.size[0]) if op[x, y][3])
    bot = sum(1 for y in range(half, out.size[1]) for x in range(out.size[0])
              if op[x, y][3])
    if top > bot:                      # тяжёлый конец оказался сверху
        out = out.rotate(180, expand=True)
    return out


def _rotate_about(img, pivot, deg, canvas):
    """Повернуть деталь вокруг её точки pivot. Возвращает холст, в центре
    которого остался pivot."""
    big = Image.new("RGBA", canvas, (0, 0, 0, 0))
    c = (canvas[0] // 2, canvas[1] // 2)
    big.alpha_composite(img, (c[0] - pivot[0], c[1] - pivot[1]))
    return big.rotate(deg, resample=Image.BICUBIC, center=c), c


def anim_dig(body, tool):
    """Возвращает (frames, heads): кадры замаха и X головы для каждого.

    heads — НЕ head_x() по каждому готовому кадру: в позе "занёс над
    головой" инструмент оказывается выше головы, и "самый верхний плотный
    массив силуэта" (см. head_anchor) — это боёк, а не голова. Голова
    гуляла на 6-8 логических px между кадрами замаха, и это выглядело как
    раз тем "скачет", что заметил владелец. Торс по ходу замаха не
    сдвигается вбок вообще (двигается только рука — см. compose_src), так
    что голову достаточно найти ОДИН раз на голом торсе (без руки, значит
    без инструмента над ней) и переиспользовать эту X для всех кадров.
    """
    torso, arm, (ax, ay) = take_arm(body)
    ref_hx, _ = head_anchor(compose_src(torso, dy_body=0), body.size[1])
    aw, ah = arm.size
    el = round(ah * ELBOW)

    upper = arm.crop((0, 0, aw, el))
    fore = arm.crop((0, el, aw, ah))

    t = normalize_tool(tool)
    t_h = max(6, round(body.size[1] * TOOL_LEN))
    t = t.resize((max(2, round(t.size[0] * t_h / t.size[1])), t_h), Image.LANCZOS)

    # предплечье + инструмент как одна деталь; локоть — верх детали
    lw = max(fore.size[0], t.size[0]) * 3
    lh = fore.size[1] + t.size[1] + 4
    limb = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    limb.alpha_composite(fore, (lw // 2 - fore.size[0] // 2, 0))
    # черенок заходит под кисть, чтобы было видно, что инструмент в руке
    limb.alpha_composite(t, (lw // 2 - t.size[0] // 2,
                             max(0, fore.size[1] - round(t.size[1] * 0.12))))
    elbow_pivot = (lw // 2, 0)

    canvas = (max(lw, lh) * 2 + 8,) * 2
    up_canvas = (upper.size[0] * 6 + 8, upper.size[1] * 6 + 8)
    shoulder_pivot = (upper.size[0] // 2, 0)

    frames = []
    heads = []
    for a_up, a_fore, lean in SWING:
        rot_up, c_up = _rotate_about(upper, shoulder_pivot, a_up, up_canvas)
        rot_limb, c_lb = _rotate_about(limb, elbow_pivot, a_up + a_fore, canvas)

        pose = compose_src(torso, dy_body=lean)
        # Холст с запасом: замах уводит руку с инструментом далеко за габарит
        # тела, а PIL молча обрезает всё, что вышло за край. Именно поэтому
        # на кадре удара инструмент пропадал целиком.
        bw = torso.size[0] * 4
        bh = torso.size[1] * 2
        out = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        px = (bw - pose.size[0]) // 2
        py = bh - pose.size[1]
        out.alpha_composite(pose, (px, py))

        pad = (pose.size[0] - torso.size[0]) // 2
        sx = px + pad + ax + aw // 2             # плечо в координатах холста
        sy = py + pad + ay + lean
        # локоть = плечо плюс повёрнутый вектор длины el, смотрящий вниз
        r = math.radians(a_up)
        ex = sx + round(math.sin(r) * el)
        ey = sy + round(math.cos(r) * el)

        out.alpha_composite(rot_up, (sx - c_up[0], sy - c_up[1]))
        out.alpha_composite(rot_limb, (ex - c_lb[0], ey - c_lb[1]))
        frames.append(out)
        heads.append(px + ref_hx)
    return frames, heads


# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------

def save(img, rel):
    path = os.path.join(ROOT, "art", rel + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


# Кому что нужно: герой и дед копают, бабки — нет.
FULL = ("boy", "boy_gear", "grandpa", "grandpa_gear")

# Полоса героя дублируется в art/character/ — там её ищут оба рендерера.
# Только то, что собирается здесь: ходьбу, падение и оба полёта кладёт туда
# import_move.py, копку — import_dig.py, каждый со своего листа.
HERO_SHEETS = ("idle", "sleep")


def main(sheet_path):
    sheet = Image.open(sheet_path).convert("RGB")
    print("лист:", sheet.size)
    mask = background_mask(sheet)

    # предметы — сначала: инструменты и снаряжение нужны для кадров анимации
    raws = {}
    written = []
    for name, (box, size) in ITEMS.items():
        raw = cut(sheet, mask, box)
        raws[name.split("/")[1]] = raw
        if name in SUPERSEDED_ITEMS:
            continue
        img = fit(raw, size)
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        out.alpha_composite(img, ((size[0] - img.size[0]) // 2,
                                  (size[1] - img.size[1]) // 2))
        written.append(save(out, name))

    # Колотая кирка переехала в tools/import_pickaxes.py — туда же, где
    # делается целая ржавая, и по тем же координатам её бойка. Здесь она
    # собиралась из ДИАГОНАЛЬНОЙ ржавой, которой больше нет.

    # полная поза деда с компасом — под катсцену, там он стоит, а не ходит.
    # Ширина цели — в ART_SCALE, как и весь остальной арт: раньше стояло
    # (48, BODY_H + 8) — высота уже была не логической (BODY_H сам в
    # ART_SCALE), а ширина осталась логической. Спрайт выходил втрое
    # мельче остальных листов персонажа при одинаковом "scale" в катсцене
    # (см. отчёт агента про cutscene_player.CHAR_FRAME).
    written.append(save(fit(cut(sheet, mask, (1005, 19, 1170, 327)),
                           (48 * ART_SCALE, BODY_H + 8)), "character/grandpa_gear/pose_compass"))

    for slug, box in CHARACTERS.items():
        body = cut(sheet, mask, box)       # исходное разрешение, не трогаем
        bh = body.size[1]

        sets = {"idle": anim_idle(body)}
        # Движение и копка героя приходят с отдельных листов
        # (tools/import_move.py и tools/import_dig.py) — там они нарисованы
        # покадрово и лучше во всём: в ходьбе видна работа корпуса, в полёте
        # винт нарисован, а не собран из прямоугольников. Процедурная сборка
        # остаётся для тех, у кого нарисованных кадров нет, — для деда и
        # бабок; для них она и писалась.
        if slug != "boy":
            sets["walk"] = anim_walk(body)
            sets["fall"] = anim_fall(body)
            sets["fly"] = anim_fly(body, raws["backpack_propeller"], "prop")
            sets["fly_jet"] = anim_fly(body, raws["jetpack"], "jet")
        if slug in FULL and slug != "boy":
            sets["dig_shovel"] = anim_dig(body, raws["shovel"])
            sets["dig_pick"] = anim_dig(body, raws["pickaxe_rusty"])

        for name, frames in sets.items():
            fit_h = not name.startswith("fly")
            heads = None
            if isinstance(frames, tuple):
                frames, heads = frames
            written.append(save(strip(shrink_set(frames, bh, fit_h, heads=heads)),
                                f"character/{slug}/{name}"))

        # сон — отдельным масштабом: лежачая поза шире стоячей
        lying = anim_sleep(body)[0]
        k = BODY_H / bh
        lw = min(FRAME_W, max(1, round(lying.size[0] * k)))
        lh = max(1, round(lying.size[1] * lw / lying.size[0]))
        written.append(save(strip([shrink(lying, (lw, lh))], bottom_pad=FOOT_PAD),
                            f"character/{slug}/sleep"))

    for name in HERO_SHEETS:
        src = Image.open(os.path.join(ROOT, "art", "character", "boy", name + ".png"))
        save(src, f"character/{name}")

    print(f"записано файлов: {len(written) + len(HERO_SHEETS)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_art.py sheet.jpg")
    main(sys.argv[1])
