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

Запуск:  python3 tools/import_art.py <путь-к-листу.jpg>
"""

import math
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TILE = 32
FRAME_W = 48          # кадр персонажа 48×48. Шире клетки намеренно: в 32 px
FRAME_H = 48          # не помещались ни замах киркой, ни винты ранца, и весь
                      # спрайт приходилось ужимать под ширину — герой худел,
                      # стоило ему начать копать
BODY_H = 40           # рост героя в игровых пикселях (авторская метка 20×40)
FOOT_PAD = 2          # отступ от низа кадра до подошвы

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


def shrink(img, size, colors=20):
    """Уменьшение с премультиплированной альфой + квантование палитры."""
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

    pm = pm.resize((tw, th), Image.BOX)
    al = al.resize((tw, th), Image.BOX)

    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    op, pp, ap = out.load(), pm.load(), al.load()
    for y in range(th):
        for x in range(tw):
            a = ap[x, y]
            if a < 116:          # порог чуть ниже половины: тонкие руки и
                continue         # ножки бура иначе осыпаются
            r, g, b = pp[x, y]
            k = 255.0 / a        # снимаем премультипликацию
            op[x, y] = (min(255, int(r * k)), min(255, int(g * k)),
                        min(255, int(b * k)), 255)

    # квантование только по непрозрачным пикселям
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
                op[x, y] = qp[x, y] + (255,)
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


def shrink_set(frames, body_src_h, fit_height=True):
    """Уменьшить набор кадров ОДНИМ масштабом и по ОБЩЕЙ рамке.

    Общая рамка обязательна: если резать каждый кадр по своему содержимому,
    персонаж прыгает внутри клетки от кадра к кадру. Масштаб тоже один на
    набор — иначе герой то толстеет, то худеет по ходу анимации.
    """
    boxes = [f.getbbox() for f in frames]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    w, h = x1 - x0, y1 - y0

    k = min(BODY_H / body_src_h, FRAME_W / w)
    if fit_height:
        k = min(k, (FRAME_H - FOOT_PAD) / h)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    return [shrink(f.crop((x0, y0, x1, y1)), size) for f in frames]


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
    torso, arm, (ax, ay) = take_arm(body)
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
    return frames


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
HERO_SHEETS = ("idle", "walk", "fall", "fly", "fly_jet", "sleep",
               "dig_shovel", "dig_pick")


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
        img = fit(raw, size)
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        out.alpha_composite(img, ((size[0] - img.size[0]) // 2,
                                  (size[1] - img.size[1]) // 2))
        written.append(save(out, name))

    # Треснувшая кирка: отдельного рисунка на листе нет, делаем из ржавой —
    # выкусываем щербину на бойке и глушим цвет.
    rusty = Image.open(os.path.join(ROOT, "art", "items", "pickaxe_rusty.png"))
    cracked = rusty.copy()
    cp = cracked.load()
    w, h = cracked.size
    for y in range(h // 4, h // 2):
        for x in range(w // 2, w):
            if cp[x, y][3] and (x + y) % 7 == 0:
                cp[x, y] = (0, 0, 0, 0)
    for y in range(h):
        for x in range(w):
            r, g, b, al = cp[x, y]
            if al:
                cp[x, y] = (int(r * 0.82), int(g * 0.78), int(b * 0.74), al)
    written.append(save(cracked, "items/pickaxe_rusty_cracked"))

    # полная поза деда с компасом — под катсцену, там он стоит, а не ходит
    written.append(save(fit(cut(sheet, mask, (1005, 19, 1170, 327)),
                           (48, BODY_H + 8)), "character/grandpa_gear/pose_compass"))

    for slug, box in CHARACTERS.items():
        body = cut(sheet, mask, box)       # исходное разрешение, не трогаем
        bh = body.size[1]

        sets = {
            "idle": anim_idle(body),
            "walk": anim_walk(body),
            "fall": anim_fall(body),
            "fly": anim_fly(body, raws["backpack_propeller"], "prop"),
            "fly_jet": anim_fly(body, raws["jetpack"], "jet"),
        }
        if slug in FULL:
            sets["dig_shovel"] = anim_dig(body, raws["shovel"])
            sets["dig_pick"] = anim_dig(body, raws["pickaxe_rusty"])

        for name, frames in sets.items():
            fit_h = not name.startswith("fly")
            written.append(save(strip(shrink_set(frames, bh, fit_h)),
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
