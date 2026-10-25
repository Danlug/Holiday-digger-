#!/usr/bin/env python3
"""import_sleep.py — авторский лист сна (4×2) в ленту кадров для движка.

Лист: восемь кадров, разложенных сеткой 4×2 и разделённых чёрными полосами.
Полосы ищутся ПО КАРТИНКЕ, а не забиты числами: лист перерисуют — нарезка
переживёт. Ищем их так: столбец (строка) считается разделителем, если его
средняя яркость провалена почти в ноль. У кадров фон тёплый и светлый, у
полос — чёрный, поэтому порог берётся с большим запасом.

Кадры на листе отличаются шириной на пиксель (251 против 252), поэтому все
приводятся к ОДНОМУ размеру — иначе в ленте кадр за кадром съезжает.

И второе, важнее: кадры СВОДЯТСЯ МЕЖДУ СОБОЙ. Художник рисовал каждый кадр
заново, и голова гуляет по кадру: измеренный до сведения разброс центра
причёски — 15 px из 224 по горизонтали и 9 по вертикали, причём нижний ряд
уехал влево целиком. На двух кадрах в секунду это читается не как дыхание,
а как дёрганая камера. Лечится тем же приёмом, что и копка (import_dig):
общий якорь на весь набор. Здесь якорь — не голова отдельно, а вся нижняя
часть кадра (подушка, плечо, лицо): сдвиг подбирается перебором по минимуму
суммы модулей разности с первым кадром. Верхняя треть в сравнение не входит:
там плывут овцы, и они плывут ПО ЗАМЫСЛУ — по ним равнять нельзя.

Цена сведения — поля: под сдвиг резервируется рамка в MARGIN пикселей
исходника с каждой стороны, и она в кадр не попадает.

Выход — горизонтальная лента из восьми кадров: так её читают и AnimatedSprite
через AtlasTexture, и наш собственный рендер, и не надо помнить, сколько
кадров в ряду.

Частота кадров. Анимация показывается около 10 секунд, и это не экшн, а
дыхание спящего: восемь кадров — один вдох-выдох (рот приоткрывается к
четвёртому кадру и закрывается к восьмому, овцы за это время проплывают
кадр). Спокойный вдох-выдох у человека — около четырёх секунд, отсюда
8 кадров / 4 с = 2 кадра в секунду. Больше — начинается мельтешение: герой
чавкает, овцы дёргаются. Меньше — видно слайд-шоу, овцы прыгают.
За 10 секунд показа это два с половиной круга.

Запуск:  python3 tools/import_sleep.py
"""

import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "_source", "sleep_sheet.jpg")
OUT_DIR = os.path.join(ROOT, "art", "anim")

COLS, ROWS = 4, 2
FRAME_W = 224        # ширина экрана: анимация сна занимает его целиком
SEP_LUM = 60         # ярче этого — уже не разделитель
INSET = 2            # срезать по 2 px от кромки кадра: JPEG звенит у чёрной
                     # полосы и оставляет по краю серую кайму
MARGIN = 14          # запас под сведение кадров, в пикселях исходника.
                     # Измеренный разброс — 17 px исходника по горизонтали,
                     # то есть ±9; 14 берётся с запасом на перерисовку листа.
                     # Больше брать жалко: это поля, которые уходят из кадра.
SEARCH = 12          # докуда перебирать сдвиг при сведении, в px исходника
MATCH_TOP = 0.33     # сравниваем кадры ниже этой доли высоты: выше — овцы
PALETTE_COLORS = 64
FPS = 2.0            # см. шапку
SHOW_SECONDS = 10.0


def bands(profile, limit, length):
    """Границы кадров по профилю яркости: тёмные участки — разделители."""
    dark = [i for i, v in enumerate(profile) if v < limit]
    groups = []
    for i in dark:
        if groups and i == groups[-1][1] + 1:
            groups[-1][1] = i
        else:
            groups.append([i, i])
    # разделители — только те тёмные группы, что лежат ВНУТРИ листа;
    # тёмная кромка по краю (если её дорисуют) кадром не является
    seps = [g for g in groups if g[0] > 0 and g[1] < length - 1]
    cuts, prev = [], 0
    for a, b in seps:
        cuts.append((prev, a - 1))
        prev = b + 1
    cuts.append((prev, length - 1))
    return cuts


def align(cells, margin, search, top_frac):
    """Сдвиги кадров, сводящие их к первому.

    Перебор по целым пикселям исходника: набор маленький (восемь кадров,
    окно 25×25 сдвигов), а любая хитрость вроде фазовой корреляции здесь
    только добавит зависимость и способ ошибиться молча.
    """
    import numpy as np

    ref = np.asarray(cells[0].convert("L"), dtype=np.int16)
    h, w = ref.shape
    y0 = int(h * top_frac)
    # окно сравнения — то, что гарантированно есть у любого сдвига
    ref_win = ref[y0 + margin:h - margin, margin:w - margin]

    out = []
    for cell in cells:
        a = np.asarray(cell.convert("L"), dtype=np.int16)
        best = None
        for dy in range(-search, search + 1):
            for dx in range(-search, search + 1):
                win = a[y0 + margin + dy:h - margin + dy,
                        margin + dx:w - margin + dx]
                if win.shape != ref_win.shape:
                    continue
                err = int(np.abs(win - ref_win).sum())
                if best is None or err < best[0]:
                    best = (err, dx, dy)
        out.append((best[1], best[2]))
    return out


def main():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    gray = sheet.convert("L")
    px = gray.load()

    col_lum = [sum(px[x, y] for y in range(h)) / h for x in range(w)]
    row_lum = [sum(px[x, y] for x in range(w)) / w for y in range(h)]

    xs = bands(col_lum, SEP_LUM, w)
    ys = bands(row_lum, SEP_LUM, h)
    print("лист %d×%d; колонки %s; ряды %s" % (w, h, xs, ys))
    if len(xs) != COLS or len(ys) != ROWS:
        raise SystemExit("ожидал сетку %d×%d, нашёл %d×%d — проверь лист"
                         % (COLS, ROWS, len(xs), len(ys)))

    # Ячейки листа отличаются на пиксель — берём общий размер по наименьшей,
    # иначе сведение будет считать по окнам разной формы.
    cell_w = min(x1 - x0 + 1 for x0, x1 in xs) - 2 * INSET
    cell_h = min(y1 - y0 + 1 for y0, y1 in ys) - 2 * INSET

    cells, order = [], []
    for r, (y0, y1) in enumerate(ys):
        for c, (x0, x1) in enumerate(xs):
            cells.append(sheet.crop((x0 + INSET, y0 + INSET,
                                     x0 + INSET + cell_w,
                                     y0 + INSET + cell_h)))
            order.append("r%dc%d" % (r + 1, c + 1))

    shifts = align(cells, MARGIN, SEARCH, MATCH_TOP)
    print("сдвиги при сведении (px исходника):",
          ", ".join("%s%+d%+d" % (o, d[0], d[1]) for o, d in zip(order, shifts)))

    win_w, win_h = cell_w - 2 * MARGIN, cell_h - 2 * MARGIN
    frame_h = round(win_h * FRAME_W / win_w)
    if frame_h % 2:
        frame_h += 1     # чётная высота: половинных пикселей при центровке нет

    os.makedirs(OUT_DIR, exist_ok=True)
    n = len(cells)
    strip = Image.new("RGB", (FRAME_W * n, frame_h))
    for i, (cell, (dx, dy)) in enumerate(zip(cells, shifts)):
        piece = cell.crop((MARGIN + dx, MARGIN + dy,
                           MARGIN + dx + win_w, MARGIN + dy + win_h))
        piece = piece.resize((FRAME_W, frame_h), Image.LANCZOS)
        piece = piece.quantize(colors=PALETTE_COLORS,
                               method=Image.MEDIANCUT).convert("RGB")
        strip.paste(piece, (i * FRAME_W, 0))

    out = os.path.join(OUT_DIR, "sleep_sheet.png")
    strip.save(out)

    meta = {
        "source": "art/_source/sleep_sheet.jpg",
        "source_grid": [COLS, ROWS],
        "frame_width": FRAME_W,
        "frame_height": frame_h,
        "frames": n,
        "layout": "horizontal",
        "order": order,
        "fps": FPS,
        "loop_seconds": round(n / FPS, 2),
        "show_seconds": SHOW_SECONDS,
        "loops_per_show": round(SHOW_SECONDS * FPS / n, 2),
        "_note": ("Порядок — слева направо, сверху вниз по исходному листу: "
                  "кадры 1-4 это вдох (рот приоткрывается), 5-8 выдох. "
                  "fps=2 подобрана под спокойное дыхание: восемь кадров = "
                  "один вдох-выдох за 4 секунды."),
    }
    with open(os.path.join(OUT_DIR, "sleep_sheet.json"), "w",
              encoding="utf-8") as f:
        f.write(json.dumps(meta, ensure_ascii=False, indent="\t") + "\n")

    print("sleep_sheet.png: %d кадров по %d×%d, лента %d×%d, %.1f fps"
          % (n, FRAME_W, frame_h, strip.size[0], strip.size[1], FPS))


if __name__ == "__main__":
    main()
