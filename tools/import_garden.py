#!/usr/bin/env python3
"""import_garden.py — нарезка авторского ассорти объектов огорода на отдельные спрайты.

Лист (art/_source/garden_assets_sheet.jpg, 1024×572) — россыпь объектов на
ровном сером фоне (~142,142,142): три дерева/куста, капуста, томаты,
подсолнух, тыква, тачка, катушка шланга, вилы с граблями, горшки, ромашки,
васильки, хоста, лаванда, три камня, кусты травы/сорняков, бабочки и
стрекозы на цветах.

Раздельно от import_art.py, потому что там фон СВЕТЛЫЙ (217/194) и порог
подобран под него, а здесь фон СЕРЫЙ и ровный — свой порог по евклидову
расстоянию до цвета углов листа.

Сегментация — связные компоненты (4-связность с диагоналями, значит и
касание углом достаточно), а не фиксированные прямоугольники: на листе почти
тридцать предметов вперемешку, и вручную обвести каждый было бы дольше и
хрупче. Правила две:

  1. компоненты МЕНЬШЕ AREA_MIN — шум JPEG (искажение вокруг чёткого края
     фона), отбрасываются;
  2. соседние компоненты одного мотива (бабочка + цветок под ней, вилы и
     грабли, стоящие вплотную, два кочана капусты друг над другом) сведены
     вручную в группы GROUPS — их бокс-боксы найдены разбором данного листа
     и записаны числами, как CHARACTERS в import_art.py, чтобы нарезка была
     повторяемой. Чужой объект в группу не попадёт, даже если геометрически
     их прямоугольники перекрываются (тачка/катушка шланга): группировка
     идёт по ID КОМПОНЕНТЫ, а не по прямоугольнику, поэтому пиксели соседа
     не подмешиваются.

Порядок компонент детерминирован (обход растровый, сверху вниз, слева
направо) — тот же алгоритм, что напечатал их при разборе листа, поэтому
номера в GROUPS переживут повторный запуск без scipy.

Запуск:  python3 tools/import_garden.py
"""

import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, shrink  # noqa: E402

SRC = os.path.join(ROOT, "art", "_source", "garden_assets_sheet.jpg")
OUT_DIR = os.path.join(ROOT, "art", "env", "garden")

# Фон почти однородный, поэтому порог — расстояние до среднего цвета четырёх
# углов листа, а не заливка от краёв: заливка потребовала бы отдельного
# обхода на каждый предмет, а объекты друг друга не касаются (кроме вил с
# граблями — и там это как раз нужно).
BG_TOL = 18
AREA_MIN = 60   # компоненты мельче — шум ресемплинга JPEG на краю фона


def _bg_color(im):
    w, h = im.size
    px = im.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    return tuple(sum(c[i] for c in corners) / 4.0 for i in range(3))


def _fg_mask(im, bg):
    """True там, где НЕ фон: расстояние в RGB больше порога."""
    w, h = im.size
    px = im.load()
    mask = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            d2 = (r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2
            if d2 > BG_TOL * BG_TOL:
                mask[y * w + x] = 1
    return mask


def _open_1px(mask, w, h):
    """Эрозия+расширение на 1 px: сбивает одиночные шумные пиксели по краю
    фона, не давая им склеить соседние предметы через диагональ."""
    er = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            if not mask[y * w + x]:
                continue
            ok = True
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if ny < 0 or ny >= h or nx < 0 or nx >= w or not mask[ny * w + nx]:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                er[y * w + x] = 1
    out = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            if not er[y * w + x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w:
                        out[ny * w + nx] = 1
    return out


def _label(mask, w, h):
    """Связные компоненты (8-связность). Возвращает список
    {"id", "box": (x0,y0,x1,y1), "area": int} в растровом порядке первого
    вхождения — устойчивый порядок между запусками."""
    labels = [0] * (w * h)
    comps = []
    next_id = 1
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if not mask[i] or labels[i]:
                continue
            cid = next_id
            next_id += 1
            q = deque([(x, y)])
            labels[i] = cid
            area = 0
            x0 = x1 = x
            y0 = y1 = y
            while q:
                cx, cy = q.popleft()
                area += 1
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h:
                            j = ny * w + nx
                            if mask[j] and not labels[j]:
                                labels[j] = cid
                                q.append((nx, ny))
            comps.append({"id": cid, "box": (x0, y0, x1, y1), "area": area})
    comps = [c for c in comps if c["area"] >= AREA_MIN]
    return labels, comps


# ---------------------------------------------------------------------------
# Разбор листа: 27 компонент (area >= AREA_MIN) в растровом порядке — после
# _open_1px, который рвёт слабые (1 px) перемычки между соседними предметами.
# Найдены запуском этого же алгоритма и сверены глазами по contact-sheet с
# нумерацией (см. отчёт агента). Индекс — позиция в comps (0-based).
#
#   0  сосна            9  тачка            18 бабочка 2 (на цветах)
#   1  томат            10 ромашки          19 кончик крыла стрекозы (шум)
#   2  ель               11 васильки         20 камень 1
#   3  подсолнух         12 хоста            21 камень 3
#   4  куст хвойный      13 лаванда          22 стрекоза
#   5  капуста (верх)    14 катушка шланга   23 цветы под бабочками
#   6  тыква             15 горшки           24 трава/сорняки, пучок 2
#   7  капуста (низ)     16 трава/сорняки, пучок 1  25 цветок под стрекозой
#   8  вилы+грабли       17 бабочка 1        26 камень 2
#
# Имя: список индексов компонент, которые склеиваются в один спрайт (капуста
# из двух кочанов, бабочка/стрекоза со своим цветком — иначе на отдельном
# спрайте насекомое виснет в пустоте без стебля, на котором сидело; 19 —
# однопиксельный обрывок крыла стрекозы, который открытие-закрытие срезало
# от компоненты 22, приклеен туда же).
GROUPS = {
    "tree_pine":            [0],
    "tree_spruce":           [2],
    "bush_fir":              [4],
    "cabbage":               [5, 7],
    "tomato":                [1],
    "sunflower":             [3],
    "pumpkin":               [6],
    "wheelbarrow":           [9],
    "hose_reel":             [14],
    "fork_rake":             [8],
    "pots":                  [15],
    "daisies":               [10],
    "cornflowers":           [11],
    "hosta":                 [12],
    "lavender":              [13],
    "stone_1":               [20],
    "stone_2":               [26],
    "stone_3":               [21],
    "flowers_butterflies":   [17, 18, 23],
    "flowers_dragonfly":     [19, 22, 25],
    # Два пучка травы/сорняков — разошлись сами: _open_1px разорвал слабую
    # перемычку между ними, вручную резать по плотности столбцов не пришлось.
    "grass_weeds_1":         [16],
    "grass_weeds_2":         [24],
}


def _cut_by_labels(im, labels, w, ids):
    """Кусок листа с альфой ТОЛЬКО по перечисленным компонентам — сосед,
    чей прямоугольник заходит в тот же бокс (тачка/катушка шланга), не
    подмешивается, потому что маска берётся по id пикселя, а не по box."""
    id_set = set(ids)
    px = im.load()
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    h = im.size[1]
    for y in range(h):
        for x in range(w):
            if labels[y * w + x] in id_set:
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, y), max(y1, y)
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    dst = out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if labels[y * w + x] in id_set:
                dst[x - x0, y - y0] = px[x, y] + (255,)
    return out


# ---------------------------------------------------------------------------
# Высота в клетках (32 логических px), по которой предмет вписывается в
# игровую сетку. Деревья и лачуга-масштаба предметы — заметно выше героя
# (герой — 40/32 = 1.25 клетки, см. import_art.BODY_H), грядки и мелочь —
# на уровне колена или ниже, камни и травa — совсем низкие. Ширина следует
# из пропорций листа, чтобы предметы не растягивались и не сплющивались.
TILE_H = {
    "tree_pine": 2.6, "tree_spruce": 2.4, "bush_fir": 1.8,
    "cabbage": 0.55, "tomato": 1.15, "sunflower": 1.35, "pumpkin": 0.9,
    "wheelbarrow": 1.0, "hose_reel": 0.7, "fork_rake": 1.3, "pots": 0.75,
    "daisies": 0.6, "cornflowers": 0.6, "hosta": 0.55, "lavender": 0.6,
    "stone_1": 0.55, "stone_2": 0.4, "stone_3": 0.45,
    "flowers_butterflies": 0.55, "flowers_dragonfly": 0.55,
    "grass_weeds_1": 0.45, "grass_weeds_2": 0.4,
}


def _to_grid(img, name):
    """Уменьшает вырезанный кусок так, чтобы его высота в игре была
    TILE_H[name] клеток. Режем в ART_SCALE раз крупнее логических координат
    — тот же приём, что и для персонажей/тайлов (tools/import_art.py)."""
    target_h = max(2, round(TILE_H[name] * 32 * ART_SCALE))
    k = target_h / img.size[1]
    target_w = max(2, round(img.size[0] * k))
    return shrink(img, (target_w, target_h))


def save(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")
    img.save(path)
    return path


def main():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
    bg = _bg_color(sheet)
    mask = _fg_mask(sheet, bg)
    mask = _open_1px(mask, w, h)
    labels, comps = _label(mask, w, h)
    print(f"компонент (area>={AREA_MIN}): {len(comps)}")
    for i, c in enumerate(comps):
        print(f"  [{i}] box={c['box']} area={c['area']}")

    written = []
    for name, idxs in GROUPS.items():
        ids = [comps[i]["id"] for i in idxs]
        raw = _cut_by_labels(sheet, labels, w, ids)
        img = _to_grid(raw, name)
        written.append(save(img, name))

    print(f"записано файлов: {len(written)}")
    for p in written:
        print(" ", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
