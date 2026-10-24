#!/usr/bin/env python3
"""import_ages.py — развёртка пацана по возрастам (8/9/10/11/12/15 лет) в
шесть отдельных поз art/character/boy/age_<N>.png.

Лист (art/_source/hero_ages_sheet.jpg, 1408×334) — шесть колонок на светло-
сером фоне в две чередующиеся тени (~201 и ~217 — видно на самом листе как
шахматный порядок), над каждой фигурой подпись "N YEARS".

Подпись вырезается ПО BBOX, А НЕ ПО ЦВЕТУ (см. пункт "ловушки" в задании):
буквы чёрные и заливкой фона не снимаются — заливка обходит их стороной, и
без явной обрезки строки они остались бы плавать чёрными кляксами над
головой. Строка текста найдена разбором (много тёмных пикселей в y=12..33,
ниже — ни одного до самих волос), поэтому обрезаем всё выше TEXT_BOTTOM.

Масштаб — ОДИН на весь набор, не по фигуре: иначе рост в игре не читается,
и мальчик "прыгает" в размере между кадрами вместо того, чтобы расти.
Опорная точка — самый старший (15 лет, самая высокая фигура на листе).
Кадры сведены по НИЖНЕМУ краю (по ступням) на общем холсте — единая линия
земли обязательна для катсцены, которая рисует персонажей ногами на land.

Запуск:  python3 tools/import_ages.py
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, BODY_H, shrink, tone_match  # noqa: E402

SRC = os.path.join(ROOT, "art", "_source", "hero_ages_sheet.jpg")
OUT_DIR = os.path.join(ROOT, "art", "character", "boy")

# Границы колонок — найдены разбором (см. отчёт агента): в строке y=5 (чисто
# фоновая, выше фигур) ровно шесть скачков яркости.
COL_CUTS = [0, 238, 480, 722, 963, 1205, 1408]
AGES = [8, 9, 10, 11, 12, 15]

# Строка подписи — плотность тёмных пикселей (luminance < 90) ненулевая
# ровно в y=12..33, потом ноль до самих волос. Обрезаем с запасом в 6 px.
TEXT_BOTTOM = 40

# Фон — два чередующихся оттенка ровного серого (~201 и ~217, см. заголовок
# файла). Порог по МАКСИМАЛЬНОЙ разнице канала от среднего серого уровня, а
# не по конкретному оттенку: тогда одна проверка годится для всей полосы,
# а не только для "своей" колонки.
BG_LEVELS = (201, 217, 203, 218, 202, 217)
BG_TOL = 16

# Итоговая высота самого старшего (15 лет, эталон масштаба) в ART_SCALE —
# столько же, сколько у одиночной сюжетной позы деда с компасом
# (art/character/grandpa_gear/pose_compass.png, BODY_H + 8): рост героев
# на сцене должен читаться единым языком масштаба, а не подбираться на
# глаз под каждую позу заново.
TARGET_H_OLDEST = BODY_H + 8


def _bg_like(p, level):
    return max(abs(p[0] - level), abs(p[1] - level), abs(p[2] - level)) <= BG_TOL


def _col_mask(col_img, level):
    """Заливка фона от краёв ОДНОЙ колонки (уже без строки подписи)."""
    w, h = col_img.size
    px = col_img.load()
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
        if not _bg_like(px[x, y], level):
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def _cut(col_img, mask):
    w, h = col_img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src, dst = col_img.load(), out.load()
    for y in range(h):
        for x in range(w):
            if not mask[y * w + x]:
                dst[x, y] = src[x, y] + (255,)
    return out


def save(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")
    img.save(path)
    return path


def main():
    sheet = Image.open(SRC).convert("RGB")
    print("лист:", sheet.size)

    # Тон приводится к эталону персонажа ДО нарезки — тем же приёмом, что и
    # у остальных листов движения (tools/import_move.py): маска фона строится
    # по исходнику, потом сама картинка заменяется тон-скорректированной, а
    # маска используется как была (заливка от почти неизменного серого не
    # зависит от того, до или после коррекции тона её считать, но опорные
    # пиксели кожи/футболки в tone_match должны браться из ОРИГИНАЛА — так
    # сделано и во всех остальных import_*).
    # У основного import_art.background_mask порог другой (217/194) — здесь
    # свой набор оттенков (чередующийся шахматный фон), поэтому маску для
    # tone_match считаем тем же тестом, что и для колонок ниже.
    # tone_match (import_art.py) индексирует маску ПЛОСКО, mask[y*w+x] —
    # как её отдают background_mask() в import_move.py/import_walk.py, а не
    # как её отдаёт background_mask() САМОГО import_art.py (тот — список
    # списков mask[y][x], под свой собственный tone_match не подставляется).
    w, h = sheet.size
    px = sheet.load()
    rough_mask = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if any(_bg_like(p, lvl) for lvl in BG_LEVELS):
                rough_mask[y * w + x] = 1
    sheet = tone_match(sheet, rough_mask)

    # 1. вырезать все шесть фигур без подписи, найти бокс содержимого
    raws = []
    for i in range(6):
        x0, x1 = COL_CUTS[i], COL_CUTS[i + 1]
        col = sheet.crop((x0, TEXT_BOTTOM, x1, h))
        mask = _col_mask(col, BG_LEVELS[i])
        cut_img = _cut(col, mask)
        box = cut_img.getbbox()
        if box is None:
            sys.exit(f"колонка {i}: не нашлось фигуры — проверь BG_LEVELS/BG_TOL")
        raws.append(cut_img.crop(box))
        print(f"  возраст {AGES[i]}: содержимое {raws[-1].size}")

    # 2. единый масштаб — по самому старшему (последняя колонка, самая
    # высокая фигура на листе)
    tallest_h = max(r.size[1] for r in raws)
    k = TARGET_H_OLDEST / tallest_h
    scaled = [shrink(r, (max(1, round(r.size[0] * k)), max(1, round(r.size[1] * k)))) for r in raws]

    # 3. общий холст: ширина — по самому широкому кадру (с запасом),
    # высота — по самому высокому; все кадры кладутся по НИЖНЕМУ краю
    # (единая линия земли) и по центру (единая ось).
    canvas_w = max(s.size[0] for s in scaled) + 4
    canvas_h = max(s.size[1] for s in scaled)

    written = []
    for age, img in zip(AGES, scaled):
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        x = (canvas_w - img.size[0]) // 2
        y = canvas_h - img.size[1]           # низ = линия земли
        canvas.alpha_composite(img, (x, y))
        written.append(save(canvas, f"age_{age}"))

    print(f"записано файлов: {len(written)}")
    for p in written:
        print(" ", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
