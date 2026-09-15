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

import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TILE = 32
FRAME_H = 48          # кадр персонажа 32×48 — под него написаны оба рендерера
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
# Тело режется на три полосы. Границы — доли роста, а не пиксели: у деда и у
# внука разные пропорции, а доли работают для обоих.
HEAD = 0.00, 0.30
TORSO = 0.30, 0.64
LEGS = 0.64, 1.00


def band(img, lo, hi):
    h = img.size[1]
    return img.crop((0, round(h * lo), img.size[0], round(h * hi)))


def compose(body, dx_head=0, dy_head=0, dx_torso=0, dy_torso=0,
            legs_parts=None, dy_all=0):
    """Собрать кадр из смещённых полос. legs_parts — (dxL, dyL, dxR, dyR)."""
    w, h = body.size
    pad = 3
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))

    head = band(body, *HEAD)
    torso = band(body, *TORSO)
    legs = band(body, *LEGS)
    y_head = round(h * HEAD[0])
    y_torso = round(h * TORSO[0])
    y_legs = round(h * LEGS[0])

    out.alpha_composite(head, (pad + dx_head, pad + y_head + dy_head + dy_all))
    out.alpha_composite(torso, (pad + dx_torso, pad + y_torso + dy_torso + dy_all))

    if legs_parts is None:
        out.alpha_composite(legs, (pad, pad + y_legs + dy_all))
    else:
        dxl, dyl, dxr, dyr = legs_parts
        mid = legs.size[0] // 2
        left = legs.crop((0, 0, mid, legs.size[1]))
        right = legs.crop((mid, 0, legs.size[0], legs.size[1]))
        out.alpha_composite(left, (pad + dxl, pad + y_legs + dyl + dy_all))
        out.alpha_composite(right, (pad + mid + dxr, pad + y_legs + dyr + dy_all))
    return out


def strip(frames, frame_w=TILE, frame_h=FRAME_H, bottom_pad=FOOT_PAD):
    """Горизонтальная полоса кадров 32×48 — формат, который читают оба рендерера."""
    sheet = Image.new("RGBA", (frame_w * len(frames), frame_h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        x = i * frame_w + (frame_w - f.size[0]) // 2
        y = frame_h - bottom_pad - f.size[1]
        sheet.alpha_composite(f, (x, y))
    return sheet


def anim_idle(body):
    # Дыхание: корпус и голова на пиксель вверх. Ноги стоят.
    return [compose(body), compose(body, dy_head=-1, dy_torso=-1)]


def anim_walk(body):
    # Четыре фазы: нога вперёд — обе вместе — другая вперёд — обе вместе.
    # Корпус качается в противофазе, иначе шаг читается как скольжение.
    return [
        compose(body, legs_parts=(-1, 0, 1, -1), dx_torso=1),
        compose(body, legs_parts=(0, 0, 0, 0), dy_all=-1),
        compose(body, legs_parts=(1, -1, -1, 0), dx_torso=-1),
        compose(body, legs_parts=(0, 0, 0, 0), dy_all=-1),
    ]


def anim_fall(body):
    # Ноги врозь, корпус запрокинут назад — поза «не успел сгруппироваться».
    return [compose(body, legs_parts=(-2, 0, 2, 0), dx_torso=-1, dy_torso=-1,
                    dx_head=-1, dy_head=-1)]


def anim_fly(body):
    # Ноги подобраны, тело покачивается от тяги.
    return [
        compose(body, legs_parts=(1, -1, -1, -1), dy_all=-1),
        compose(body, legs_parts=(1, -2, -1, -2), dy_all=-2),
    ]


def anim_sleep(body):
    # Лежит: поворот всего тела на 90°, отдельной позы для сна в листе нет.
    lying = body.rotate(90, expand=True)
    return [lying]


# Замах: угол, смещение от руки и наклон корпуса на кадр. Инструмент должен
# идти по дуге, а не просто проворачиваться на месте — иначе на 20 px кадр
# читается как «стоит с лопатой», а не «бьёт лопатой».
SWING = (
    (-65, -1, -7, 0),   # занёс над плечом
    (-20, 1, -3, 0),    # пошёл вниз
    (25, 2, 2, -1),     # разгон, корпус подаётся вперёд
    (60, 3, 6, -1),     # удар у самой земли
)


def anim_dig(body, tool_src):
    """Поворачиваем крупный исходник и только потом уменьшаем — поворот уже
    готового мелкого спрайта разваливает пиксели."""
    frames = []
    tool_h = round(BODY_H * 0.42)
    for ang, dx, dy, lean in SWING:
        rot = tool_src.rotate(ang, expand=True, resample=Image.BICUBIC)
        k = tool_h / max(rot.size)
        tool = shrink(rot, (max(1, round(rot.size[0] * k)),
                            max(1, round(rot.size[1] * k))), colors=8)
        f = compose(body, dx_torso=lean, dx_head=lean)
        # точка хвата — у пояса со стороны взгляда (спрайт смотрит вправо)
        hx = round(f.size[0] * 0.70) + dx
        hy = round(f.size[1] * 0.58) + dy
        f.alpha_composite(tool, (max(0, hx - tool.size[0] // 2),
                                 max(0, hy - tool.size[1] // 2)))
        frames.append(f)
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


def main(sheet_path):
    sheet = Image.open(sheet_path).convert("RGB")
    print("лист:", sheet.size)
    mask = background_mask(sheet)

    # предметы — сначала, инструменты нужны для кадров копки
    tools_src = {}
    written = []
    for name, (box, size) in ITEMS.items():
        raw = cut(sheet, mask, box)
        if name in ("items/shovel", "items/pickaxe_rusty", "items/pickaxe_iron"):
            tools_src[name.split("/")[1]] = raw
        img = fit(raw, size)
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        out.alpha_composite(img, ((size[0] - img.size[0]) // 2,
                                  (size[1] - img.size[1]) // 2))
        written.append((save(out, name), out.size))

    # полная поза деда с компасом сохраняется целиком: в катсцене он стоит,
    # а не ходит, и обрезать ему руку там незачем
    pose = cut(sheet, mask, (1005, 19, 1170, 327))
    written.append((save(fit(pose, (48, BODY_H + 8)),
                         "character/grandpa_gear/pose_compass"), None))

    for slug, box in CHARACTERS.items():
        raw = cut(sheet, mask, box)
        k = BODY_H / raw.size[1]
        body = shrink(raw, (max(1, round(raw.size[0] * k)), BODY_H))
        # ширину держим в пределах кадра: у деда с компасом рука торчит вбок
        if body.size[0] > TILE - 4:
            body = body.crop(body.getbbox())
            k2 = (TILE - 4) / body.size[0]
            body = shrink(body, (TILE - 4, max(1, round(body.size[1] * k2))))

        sets = {
            "idle": anim_idle(body),
            "walk": anim_walk(body),
            "fall": anim_fall(body),
            "fly": anim_fly(body),
            "sleep": anim_sleep(body),
        }
        if slug in FULL:
            sets["dig_shovel"] = anim_dig(body, tools_src["shovel"])
            sets["dig_pick"] = anim_dig(body, tools_src["pickaxe_rusty"])

        for name, frames in sets.items():
            pad = 0 if name == "sleep" else FOOT_PAD
            written.append((save(strip(frames, bottom_pad=pad),
                                 f"character/{slug}/{name}"), None))

    # Треснувшая кирка: отдельного рисунка на листе нет, делаем из ржавой —
    # выкусываем щербину на бойке и глушим цвет.
    rusty = Image.open(os.path.join(ROOT, "art", "items", "pickaxe_rusty.png"))
    cracked = rusty.copy()
    cp = cracked.load()
    w, h = cracked.size
    notch = [(x, y) for y in range(h // 4, h // 2) for x in range(w // 2, w)
             if cp[x, y][3] and (x + y) % 7 == 0]
    for x, y in notch:
        cp[x, y] = (0, 0, 0, 0)
    for y in range(h):
        for x in range(w):
            r, g, b, al = cp[x, y]
            if al:
                cp[x, y] = (int(r * 0.82), int(g * 0.78), int(b * 0.74), al)
    written.append((save(cracked, "items/pickaxe_rusty_cracked"), None))

    # герой по умолчанию лежит там, где его ищут оба рендерера
    for name in ("idle", "walk", "fall", "fly", "sleep", "dig_shovel", "dig_pick"):
        src = Image.open(os.path.join(ROOT, "art", "character", "boy", name + ".png"))
        save(src, f"character/{name}")

    print(f"записано файлов: {len(written) + 7}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_art.py sheet.jpg")
    main(sys.argv[1])
