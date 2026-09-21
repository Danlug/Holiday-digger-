#!/usr/bin/env python3
"""import_clouds.py — вырезает облака, солнце и месяц из одного исходника.

Источник: art/_source/sky_clouds_sun_moon_sheet.jpg (1024×521). Разметка
листа (см. отчёт агента, найдено программно по цвету фона):

  * Слева/сверху — россыпь ~12 отдельных кучевых/перистых/слоистых/дождевых
    облаков на ровном голубом небе (146,209,240), без сетки.
  * Справа снизу — прямоугольная плашка (463,262)-(1024,521) на ЧУТЬ более
    светлом голубом (167,223,250): в ней солнце, месяц (со звёздочками
    рядом — свой фон, органично, не отделяем) и маленький квадрат-образец
    со звёздами (тот достаётся отдельно, см. tools/import_stars.py —
    квадрат не облако и не светило).
  * Подпись «1 2 3 4 5» — внутри той же плашки, под месяцем/квадратом;
    вырезается по bbox плашки и в атлас не попадает (мы берём только
    bbox самого солнца/месяца).

Оба фона — заливка без градиента, поэтому вырезка проще, чем в
import_backdrops.py::cut_sky (там нужна связность от кромки листа из-за
залезающего в кадр неба с обеих сторон гор): здесь порог по расстоянию до
эталонного цвета фона с мягким рэмпом на кромке (тот же приём, что в
import_stars.py::_alpha_and_color, векторно и с двумя разными фонами).
БЕЗ гауссова размытия альфы (в отличие от cut_sky): tools/import_art.py:
shrink() считает пиксель «непрозрачным» уже при alpha>0 (см. её `if a:` —
это дешёвый coverage-трюк для персонажей с изначально жёсткой альфой), и
размытие поднимает фон чуть выше нуля почти everywhere, отчего после
_tight_alpha_bbox() в кадр попадает весь прямоугольник, а не силуэт —
на первом прогоне этого скрипта так и получилось (art/env/moon.png вышел
полностью непрозрачным). Рэмп T_LOW..T_HIGH сам даёт достаточно мягкий
край на итоговом LANCZOS-уменьшении shrink().

Результат:
  art/env/clouds/cloud_1.png … cloud_12.png — по одному облаку на файл,
    RGBA, без квантования палитры (см. tools/import_art.py::shrink).
  art/env/sun.png, art/env/moon.png — то же самое для светил.

Бокс-координаты подобраны вручную по связным компонентам исходника (see
_CLOUD_BOXES/_SUN_BOX/_MOON_BOX) — лист не меняется между запусками,
поэтому не пересчитываем компоненты каждый раз, а храним готовые числа
(быстрее, детерминированнее, и проще проверить глазами при ревью).

Запуск:  python3 tools/import_clouds.py
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, shrink  # noqa: E402

SRC = os.path.join(ROOT, "art", "_source", "sky_clouds_sun_moon_sheet.jpg")
OUT_CLOUDS_DIR = os.path.join(ROOT, "art", "env", "clouds")
OUT_ENV_DIR = os.path.join(ROOT, "art", "env")

SKY_BG = np.array([146, 209, 240], dtype=float)     # фон облачной части листа
# Плашка справа снизу — НЕ один сплошной фон: у солнца и у квадрата со
# звёздами светлый голубой (~167,222,246), а у месяца — свой более тёмный
# "ночной" фон (~124,179,209), нарочно другого тона (см. отчёт агента,
# найдено сравнением медианы по большому прямоугольнику внутри каждой
# панели). Два разных эталона, а не один — иначе с одним порог либо режет
# месяц заодно с фоном, либо совсем не вырезает его (так и было на первом
# прогоне: art/env/moon.png получился полностью непрозрачным).
SUN_BG = np.array([167, 221, 240], dtype=float)
MOON_BG = np.array([124, 179, 209], dtype=float)
STAR_SQ_BG = np.array([166, 222, 248], dtype=float)

T_LOW = 20.0
T_HIGH = 40.0

PAD = 12   # запас вокруг bbox с каждой стороны при вырезке (антиалиасинг края на исходнике,
           # плюс отдельные тонкие "хвосты" фигур типа cirrus, не попавшие в bbox компонента)

# (имя, (x0,y0,x1,y1) bbox фигуры на исходнике, целевая ЛОГИЧЕСКАЯ ширина px)
# bbox найдены связными компонентами (порог по SKY_BG, area>=50) на области
# листа вне плашки солнца/месяца; близкие обрывки одной фигуры (перистые
# полосы, дождевые капли под тучей) объединены в один bbox вручную — иначе
# получались бы висящие в воздухе отдельные капли без самой тучи.
_CLOUD_BOXES = [
    ("cirrus", (20, 28, 205, 105), 150),          # перистые полосы, верх-лево (bbox чуть
                                                    # уже связной компоненты — вплотную к ней
                                                    # начинается cumulus_xl, без зазора для PAD)
    ("cumulus_xl", (74, 32, 465, 231), 220),      # большая кучевая гора
    ("cumulus_tiny", (30, 213, 62, 228), 55),     # крошечный островок у подножья xl
    ("cumulus_m", (491, 28, 615, 121), 125),      # тёмно-серая кучевая, верх-центр
    ("stratus_wide", (652, 30, 975, 111), 210),   # широкая плоская слоистая
    ("cumulus_s", (483, 156, 632, 234), 115),     # маленькая кучевая, под cumulus_m
    ("stratus_flat_a", (653, 142, 821, 185), 115),
    ("stratus_flat_b", (652, 197, 821, 234), 115),
    ("raincloud_dark", (843, 128, 1008, 256), 150, 4),  # дождевая, с каплями снизу; низкий pad —
                                                          # низ рядом с плашкой солнца/месяца
                                                          # (y=262), у нее другой фон
    ("cumulus_l", (21, 266, 229, 325), 155),
    ("cumulus_m2", (22, 354, 198, 435), 135),
    ("raincloud_big", (210, 282, 455, 467), 195, 4),   # большая дождевая, с каплями; низкий
                                                         # pad — правый край рядом с плашкой
                                                         # солнца/месяца (x=463)
]

_SUN_BOX = (474, 274, 686, 485)
_SUN_PAD = 8    # солнечная панель начинается вплотную (x=463) — большой pad вылезает за неё
_MOON_BOX = (699, 276, 878, 481)   # включает звёздочки рядом с серпом — свой фон, органично;
_MOON_PAD = 0   # тёмная панель месяца впритык к самой фигуре, пада нет вообще

SUN_LOGICAL_W = 75
MOON_LOGICAL_W = 60   # чуть уже солнца — на исходнике серп визуально компактнее диска


def _cut(rgb: np.ndarray, ref: np.ndarray) -> np.ndarray:
    dist = np.abs(rgb.astype(float) - ref).sum(axis=2)
    alpha = np.clip((dist - T_LOW) / (T_HIGH - T_LOW), 0.0, 1.0) * 255.0
    alpha = np.round(alpha).astype(np.uint8)
    return np.dstack([rgb, alpha])


def _crop_box(im: Image.Image, box, pad: int) -> Image.Image:
    w, h = im.size
    x0, y0, x1, y1 = box
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(w, x1 + pad)
    y1 = min(h, y1 + pad)
    return im.crop((x0, y0, x1, y1))


def _tight_alpha_bbox(rgba: Image.Image) -> Image.Image:
    """Обрезает по фактической альфе после вырезки — паддинг PAD оставляет
    прозрачную кайму вокруг реальной фигуры, которую не нужно тащить в
    атлас/спрайт (лишние логические px в TextureRect)."""
    box = rgba.getbbox()
    return rgba.crop(box) if box else rgba


def _save_shape(name: str, im_source: Image.Image, box, ref: np.ndarray,
                 target_logical_w: int, out_path: str, report: list, pad: int = PAD) -> None:
    crop = _crop_box(im_source, box, pad)
    rgb = np.asarray(crop.convert("RGB")).astype(np.uint8)
    rgba_arr = _cut(rgb, ref)

    # Проверка эталона фона, а не тихая порча альфы: у padded-кромки (PAD px
    # от исходного bbox) обязан лежать чистый фон — если её альфа не 0,
    # значит ref не совпал с настоящим фоном (так и вышло на первом прогоне
    # с одним BOX_BG на солнце/месяц/квадрат — месяц вышел полностью
    # непрозрачным, см. докстринг файла).
    corners = rgba_arr[[0, 0, -1, -1], [0, -1, 0, -1], 3]
    if int(corners.max()) > 40:
        raise RuntimeError(
            f"{name}: кромка вырезки не похожа на фон (альфа углов={corners.tolist()}) "
            f"— эталон ref={ref.tolist()} не совпадает с настоящим фоном под этой "
            f"фигурой; проверь bbox/эталон в _CLOUD_BOXES/_SUN_BOX/_MOON_BOX")

    cut = Image.fromarray(rgba_arr, "RGBA")
    cut = _tight_alpha_bbox(cut)

    cw, ch = cut.size
    target_w_px = target_logical_w * ART_SCALE
    target_h_px = max(1, round(ch * target_w_px / cw))
    out = shrink(cut, (target_w_px, target_h_px))
    out.save(out_path)
    report.append(f"{name}: bbox_src={box} -> вырезано {cw}x{ch} -> сохранено "
                   f"{out.size[0]}x{out.size[1]} ({target_logical_w} логич. px шириной) "
                   f"-> {os.path.relpath(out_path, ROOT)}")


def main() -> None:
    os.makedirs(OUT_CLOUDS_DIR, exist_ok=True)
    os.makedirs(OUT_ENV_DIR, exist_ok=True)
    report: list = []

    im = Image.open(SRC).convert("RGB")
    report.append(f"исходник: {im.size}")

    for i, entry in enumerate(_CLOUD_BOXES, start=1):
        name, box, target_w = entry[0], entry[1], entry[2]
        pad = entry[3] if len(entry) > 3 else PAD
        out_path = os.path.join(OUT_CLOUDS_DIR, f"cloud_{i}.png")
        _save_shape(name, im, box, SKY_BG, target_w, out_path, report, pad)

    _save_shape("sun", im, _SUN_BOX, SUN_BG, SUN_LOGICAL_W,
                os.path.join(OUT_ENV_DIR, "sun.png"), report, _SUN_PAD)
    _save_shape("moon", im, _MOON_BOX, MOON_BG, MOON_LOGICAL_W,
                os.path.join(OUT_ENV_DIR, "moon.png"), report, _MOON_PAD)

    print("\n".join(report))
    print(f"\nоблаков сохранено: {len(_CLOUD_BOXES)}")


if __name__ == "__main__":
    main()
