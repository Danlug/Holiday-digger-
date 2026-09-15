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


def shrink_set(frames, body_src_h):
    """Уменьшить набор кадров ОДНИМ масштабом и по ОБЩЕЙ рамке.

    Общая рамка обязательна: если резать каждый кадр по своему содержимому,
    персонаж прыгает внутри клетки от кадра к кадру. Масштаб тоже один на
    набор — иначе герой то толстеет, то худеет по ходу анимации.
    """
    boxes = [f.getbbox() for f in frames]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    w, h = x1 - x0, y1 - y0

    k = min(BODY_H / body_src_h, TILE / w, (FRAME_H - FOOT_PAD) / h)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    return [shrink(f.crop((x0, y0, x1, y1)), size) for f in frames]


def strip(frames, frame_w=TILE, frame_h=FRAME_H, bottom_pad=FOOT_PAD):
    """Горизонтальная полоса кадров 32×48 — формат, который читают оба рендерера."""
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

# Снаряжение на спине: (ширина в долях тела, где низ ранца по росту).
# Персонаж нарисован анфас, поэтому ранец целиком за спиной не виден вообще —
# читаются только те части, что выходят за силуэт. Ранцу дана ширина больше
# тела, чтобы винты торчали по бокам на уровне плеч; джетпак опущен к ногам,
# чтобы из-за них были видны сопла.
GEAR_FIT = {
    "backpack_propeller": (1.45, 0.62),
    "jetpack": (1.25, 0.78),
}


def anim_fly(body, gear=None, gear_name=""):
    """Ранец или джетпак виден за спиной: без него персонаж просто висит в
    воздухе без всякой причины."""
    poses = [
        compose_src(body, dy_body=-1, legs=(0.05, -0.04, -0.05, -0.04)),
        compose_src(body, dy_body=-3, legs=(0.06, -0.06, -0.06, -0.06)),
        compose_src(body, dy_body=-2, legs=(0.05, -0.05, -0.05, -0.05)),
    ]
    if gear is None:
        return poses

    w, body_h = body.size
    pad_top = (poses[0].size[1] - body_h) // 2
    frames = []
    for i, pose in enumerate(poses):
        wide, bottom = GEAR_FIT.get(gear_name, (1.2, 0.70))
        g = gear.copy()
        k = (w * wide) / g.size[0]
        g = g.resize((max(1, round(g.size[0] * k)), max(1, round(g.size[1] * k))),
                     Image.LANCZOS)
        out = Image.new("RGBA", pose.size, (0, 0, 0, 0))
        gx = (pose.size[0] - g.size[0]) // 2
        gy = pad_top + round(body_h * bottom) - g.size[1] - (i % 2)
        out.alpha_composite(g, (gx, gy))
        out.alpha_composite(pose)
        frames.append(out)
    return frames


# --- копка -----------------------------------------------------------------
#
# Инструмент держит РУКА. Раньше кирка висела в воздухе рядом с телом и
# проворачивалась сама по себе. Теперь рука вырезается из тела, дыра на её
# месте затягивается цветом туловища, а рука вместе с инструментом
# поворачивается вокруг плеча как одно целое.

SWING = (-55, -30, 0, 25, 45, 15)    # градусы от вертикали вниз
SWING_LEAN = (0, 0, 0, -1, -2, -1)   # корпус подаётся вперёд на ударе


def take_arm(body):
    """Снять рабочую руку с тела, следуя силуэту.

    Рука — это крайние пиксели силуэта, а не прямоугольник: если резать
    прямоугольником, вместе с рукой уходит край туловища и тело выглядит
    разрезанным. Идём по строкам и забираем последние ARM_W ширины тела
    непрозрачных пикселей. Тело после этого честно становится у́же на руку.
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
        start = max(0, right - arm_w + 1)
        left_edge = min(left_edge, start)
        for i, x in enumerate(range(start, right + 1)):
            ap[i, y - y0] = tp[x, y]
            tp[x, y] = (0, 0, 0, 0)
    return torso, arm, (left_edge, y0)


def limb_with_tool(arm, tool, body_w):
    """Рука + инструмент как одна деталь. Черенок ложится в кисть."""
    k = (body_w * 0.75) / max(tool.size)
    t = tool.resize((max(1, round(tool.size[0] * k)),
                     max(1, round(tool.size[1] * k))), Image.LANCZOS)

    pad_x = t.size[0]
    pad_y = t.size[1]
    out = Image.new("RGBA", (arm.size[0] + pad_x * 2, arm.size[1] + pad_y),
                    (0, 0, 0, 0))
    ax = pad_x
    out.alpha_composite(arm, (ax, 0))
    # кисть — низ руки; инструмент от неё вниз-вперёд
    hx = ax + arm.size[0] // 2 - t.size[0] // 2 + round(arm.size[0] * 0.2)
    hy = arm.size[1] - round(t.size[1] * 0.25)
    out.alpha_composite(t, (max(0, hx), max(0, hy)))
    # плечо — верх исходной руки, в координатах получившейся детали
    pivot = (ax + arm.size[0] // 2, round(arm.size[1] * 0.08))
    return out, pivot


def anim_dig(body, tool):
    torso, arm, (ax, ay) = take_arm(body)
    limb, pivot = limb_with_tool(arm, tool, body.size[0])

    frames = []
    for ang, lean in zip(SWING, SWING_LEAN):
        # поворот вокруг плеча: сдвигаем деталь так, чтобы плечо было в
        # центре холста, крутим, возвращаем на место
        big = Image.new("RGBA", (limb.size[0] * 3, limb.size[1] * 3), (0, 0, 0, 0))
        cx, cy = big.size[0] // 2, big.size[1] // 2
        big.alpha_composite(limb, (cx - pivot[0], cy - pivot[1]))
        big = big.rotate(-ang, resample=Image.BICUBIC, center=(cx, cy))

        pose = compose_src(torso, dy_body=lean)
        pad = (pose.size[0] - torso.size[0]) // 2
        # плечо в координатах кадра
        sx = pad + ax + arm.size[0] // 2
        sy = pad + ay + round(arm.size[1] * 0.08) + lean
        out = pose.copy()
        out.alpha_composite(big, (sx - cx, sy - cy))
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
            "fly": anim_fly(body, raws["backpack_propeller"], "backpack_propeller"),
            "fly_jet": anim_fly(body, raws["jetpack"], "jetpack"),
        }
        if slug in FULL:
            sets["dig_shovel"] = anim_dig(body, raws["shovel"])
            sets["dig_pick"] = anim_dig(body, raws["pickaxe_rusty"])

        for name, frames in sets.items():
            written.append(save(strip(shrink_set(frames, bh)),
                                f"character/{slug}/{name}"))

        # сон — отдельным масштабом: лежачая поза шире стоячей
        lying = anim_sleep(body)[0]
        k = BODY_H / bh
        lw = min(TILE, max(1, round(lying.size[0] * k)))
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
