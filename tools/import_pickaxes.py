#!/usr/bin/env python3
"""import_pickaxes.py — авторский ряд из шести кирок в предметы 32×32.

Лист: шесть кирок в ряд на светло-сером фоне, под каждой подпись
(rusty / Iron / Titanium / Platinum / Almond(Diamond) / Obsidian) и заявленный
размер бойка — от 7×7 до 10×10 пикселей. Подписи в кадр не берутся: полоса с
текстом отделена от рисунков чистым фоном и отрезается по этому пропуску,
а не по константе.

ГЛАВНОЕ ЗДЕСЬ — ОДИН МАСШТАБ НА ВЕСЬ РЯД. Подписи говорят, что боёк растёт
от 7×7 у ржавой до 10×10 у обсидиановой, и художник этот рост выдержал:
измеренная ширина рисунков идёт 120, 132, 155, 151, 144, 173 px, то есть
обсидиан шире ржавой в 1.44 раза при заявленных 10/7 = 1.43. Значит, ничего
подгонять не надо — достаточно НЕ выравнивать кирки по отдельности. Масштаб
считается один раз, по самой крупной кирке (обсидиановой) так, чтобы она
заняла кадр 32×32 целиком; остальные уменьшаются тем же числом и выходят
мельче ровно настолько, насколько мельче нарисованы.

ПОЧЕМУ КИРКИ СТОЯТ ПРЯМО, А НЕ ПО ДИАГОНАЛИ. Прежние pickaxe_rusty и
pickaxe_iron лежали в кадре наискось. Для длинной тонкой вещи диагональ —
выигрыш: в квадрат 32×32 по диагонали влезает 45 px. Но у кирки широкий
боёк, и прямоугольник рисунка почти квадратный (173×233 у обсидиановой),
а у такого поворот не помогает, а мешает: габарит после поворота на 45°
становится 287×287, и масштаб падает с 0.137 до 0.111 — кирка выходит на
пятую часть МЕЛЬЧЕ. Ставить наискось только новые четыре тоже нельзя: тогда
обсидиановая окажется мельче старой ржавой, и весь смысл ряда — «чем дороже,
тем крупнее» — перевернётся. Поэтому весь ряд, включая rusty и iron,
переснимается с листа прямо и одним масштабом.

Колотая ржавая кирка собирается из новой ржавой тем же приёмом, что и
раньше (import_art.main): в бойке выкусывается щербина, цвет глушится. Иначе
она осталась бы наискось и мельче, чем целая, — то есть выглядела бы не
сломанной, а чужой.

Запуск:  python3 tools/import_pickaxes.py
"""

import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import shrink  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "_source", "pickaxes_sheet.jpg")
OUT_DIR = os.path.join(ROOT, "art", "items")

BOX = 32              # предмет 32×32 — как все прочие в art/items
COLORS = 20           # столько же, сколько у соседей по папке
BG_TOL = 22           # допуск на «это фон»: серый 215 плывёт от JPEG на
                      # единицы, а самый светлый контур кирки — 92, так что
                      # порог можно брать с запасом
MIN_RUN = 12          # уже этой полосы по горизонтали — не кирка, а буква

# Нижняя полоса HUD — #16120E, её яркость 18. Предмет, у которого самый
# тёмный пиксель темнее этого, на кнопке пропадает силуэтом: проверено на
# превью — обсидиановая кирка (самый тёмный пиксель 16, середина 39) на
# полосе читалась как пятно без формы. Поэтому у таких предметов поднимается
# точка чёрного. 38 — вдвое ярче полосы: край уже видно, а «обсидиан всё ещё
# чёрный» сохраняется. Остальных пяти кирок правило не касается: у самой
# тёмной из них (алмазной) низ на 21, но середина 68 — она видна и так.
HUD_LUM = 18
MIN_LUM = 38

# Порядок слева направо по листу. Almond на подписи — это Diamond, так в
# скобках и написано; в игре руда и предмет зовутся diamond.
NAMES = ["rusty", "iron", "titanium", "platinum", "diamond", "obsidian"]


def background_mask(im):
    """True там, где фон. Заливка от краёв, как в import_dig.

    Порогом по яркости здесь нельзя: у платиновой кирки рукоять почти белая
    (215..247) и по светлоте неотличима от фона (215). Спасает то, что она
    обведена тёмным контуром, — заливка до неё не доходит.
    """
    px = im.load()
    w, h = im.size
    br, bg_, bb = px[0, 0]

    mask = bytearray(w * h)
    seen = bytearray(w * h)
    stack = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
    stack += [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    while stack:
        y, x = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b = px[x, y]
        if max(abs(r - br), abs(g - bg_), abs(b - bb)) > BG_TOL:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def runs(flags, min_len):
    """Границы непрерывных True-участков длиннее min_len."""
    out, start = [], None
    for i, v in enumerate(list(flags) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= min_len:
                out.append((start, i - 1))
            start = None
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


def lift_blacks(img):
    """Поднять точку чёрного, если предмет темнее полосы HUD.

    Кривая мягкая: c' = c + (MIN_LUM - lmin)·(1 - c/255). Самый тёмный
    пиксель приходит ровно в MIN_LUM, светлые почти не двигаются — иначе
    вместо чёрного обсидиана получится серый камень. Сдвиг одинаков по трём
    каналам, поэтому синева обсидиана остаётся синевой.
    """
    p = img.load()
    w, h = img.size
    dark = min((r + g + b) / 3.0
               for y in range(h) for x in range(w)
               for r, g, b, a in [p[x, y]] if a)
    if dark >= MIN_LUM:
        return img, 0.0
    boost = MIN_LUM - dark
    for y in range(h):
        for x in range(w):
            r, g, b, a = p[x, y]
            if not a:
                continue
            p[x, y] = tuple(min(255, round(c + boost * (1.0 - c / 255.0)))
                            for c in (r, g, b)) + (a,)
    return img, boost


def crack(img):
    """Колотая ржавая кирка из целой: отбитый угол бойка + глухой цвет.

    Рецепт унаследован от import_art.main, но переделан. Там скол делался
    сыпью по маске (x + y) % 7 в правой верхней четверти кадра. На прежней
    диагональной кирке это ещё читалось; на нынешней прямой боёк занимает
    семь строк в высоту, и сыпь по ним выглядит не сколом, а грязью —
    проверено на превью в масштабе кнопки.

    Поэтому скол теперь ОДИН и компактный: у ПРАВОГО КРЫЛА бойка отбит
    кончик. Срез идёт от самой правой точки бойка внутрь на depth столбцов,
    через строку на один меньше — край выходит ступенчатым, как отломанный
    металл, а не отрезанным по линейке. Боёк после этого несимметричен, и
    это видно даже в 26 px.

    Важно, что режется именно крыло, а не «верхняя треть» кадра: наверху у
    прямой кирки не крыло, а узкая шейка под рукоятью, и съеденная шейка
    читается как обломанная рукоять, а не как разбитый боёк.
    """
    out = img.copy()
    p = out.load()
    x0, y0, x1, y1 = img.getbbox()
    x1 -= 1
    y1 -= 1
    head_rows = max(2, (y1 - y0 + 1) // 3)
    band = range(y0, y0 + head_rows)
    tip = max((x for y in band for x in range(x0, x1 + 1) if p[x, y][3]),
              default=x1)
    head_w = max(sum(1 for x in range(x0, x1 + 1) if p[x, y][3]) for y in band)
    depth = max(2, round(head_w * 0.25))
    for i, y in enumerate(band):
        d = depth - (i % 2)
        for x in range(tip - d + 1, tip + 1):
            if p[x, y][3]:
                p[x, y] = (0, 0, 0, 0)
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            r, g, bl, a = p[x, y]
            if a:
                p[x, y] = (int(r * 0.82), int(g * 0.78), int(bl * 0.74), a)
    return out


def main():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    mask = background_mask(sheet)
    fg = [[not mask[y * w + x] for x in range(w)] for y in range(h)]

    # 1. полоса с кирками: первая сверху полоса непустых строк. Ниже, через
    #    чистый фон, идут подписи — они в эту полосу не попадают.
    row_has = [any(r) for r in fg]
    bands = runs(row_has, MIN_RUN)
    if not bands:
        raise SystemExit("на листе ничего не нашлось")
    top, bottom = bands[0]

    # 2. шесть колонок внутри полосы
    col_has = [any(fg[y][x] for y in range(top, bottom + 1)) for x in range(w)]
    cols = runs(col_has, MIN_RUN)
    print("полоса с кирками: строки %d..%d; колонки %s" % (top, bottom, cols))
    if len(cols) != len(NAMES):
        raise SystemExit("ожидал %d кирок, нашёл %d" % (len(NAMES), len(cols)))

    # 3. вырезаем и меряем
    pieces, sizes = [], []
    for x0, x1 in cols:
        piece = cut(sheet, mask, (x0, top, x1, bottom))
        piece = piece.crop(piece.getbbox())
        pieces.append(piece)
        sizes.append(piece.size)
    for name, size in zip(NAMES, sizes):
        print("  %-9s %d×%d px исходника" % (name, size[0], size[1]))

    # 4. ОДИН масштаб на ряд — по самой крупной кирке
    k = min(BOX / max(s[0] for s in sizes), BOX / max(s[1] for s in sizes))
    print("общий масштаб %.4f (самая крупная занимает кадр целиком)" % k)

    os.makedirs(OUT_DIR, exist_ok=True)
    meta = {"source": "art/_source/pickaxes_sheet.jpg", "box": BOX,
            "scale": round(k, 5), "items": {}}
    rusty = None
    for name, piece in zip(NAMES, pieces):
        tw = max(1, round(piece.size[0] * k))
        th = max(1, round(piece.size[1] * k))
        small = shrink(piece, (tw, th))
        img = Image.new("RGBA", (BOX, BOX), (0, 0, 0, 0))
        # по центру кадра: в ряду кнопок предметы должны стоять на одной оси,
        # а разница в размере — читаться как разница в размере, а не как
        # разное положение в кнопке
        img.alpha_composite(small, ((BOX - tw) // 2, (BOX - th) // 2))
        img, boost = lift_blacks(img)
        img.save(os.path.join(OUT_DIR, "pickaxe_%s.png" % name))
        if name == "rusty":
            rusty = img
        meta["items"]["pickaxe_%s" % name] = {
            "source_px": list(piece.size), "px": [tw, th],
            "relative": round(tw / (max(s[0] for s in sizes) * k), 3),
        }
        if boost:
            meta["items"]["pickaxe_%s" % name]["black_lift"] = round(boost, 1)
        print("  pickaxe_%-9s -> %d×%d в кадре %d×%d%s"
              % (name, tw, th, BOX, BOX,
                 "" if not boost else ", чёрный поднят на %.0f" % boost))

    cracked = crack(rusty)
    cracked.save(os.path.join(OUT_DIR, "pickaxe_rusty_cracked.png"))
    meta["items"]["pickaxe_rusty_cracked"] = {"from": "pickaxe_rusty",
                                              "note": "щербина в бойке, цвет глуше"}
    print("  pickaxe_rusty_cracked <- из ржавой")

    with open(os.path.join(OUT_DIR, "pickaxes.json"), "w",
              encoding="utf-8") as f:
        f.write(json.dumps(meta, ensure_ascii=False, indent="\t") + "\n")


if __name__ == "__main__":
    main()
