#!/usr/bin/env python3
"""import_backdrops.py — фоновые подложки за домом/огородом и за лесом/горой.

Три исходника (art/_source/), три результата (art/env/):

  backdrop_fence_white.jpg -> backdrop_fence_white.png  (сейчас, белый штакетник)
  backdrop_fence_old.jpg   -> backdrop_fence_old.png    (времена деда, старый забор)
  backdrop_mountain.jpg    -> backdrop_mountain.png     (гора за лесом, вдали)

Забор (оба варианта)
---------------------
Высота ровно 2 клетки (64 логических = 192 текстурных px при ART_SCALE=3),
ширина по тому же масштабу: 1024×205 -> 960×192 (960 текстурных = 320
логических = 10 клеток на повтор). Масштаб равномерный (192/205 ≈ 960/1024
с точностью до долей процента) — панораму не перекашивает.

Низ картинки должен СОЙТИСЬ с настоящим тайлом травы (art/tiles/grass_1.png),
на верхней кромке которого стоит забор (мировая клетка y=0):

  * нижние GRASS_STRIP_PX текстурных px тонируются в Lab к среднему тону
    grass_1.png — не заменяются им, а СДВИГАЮТСЯ (как tone_match в
    tools/import_tiles.py): каждый пиксель тянется к эталону на свою долю,
    линейно нарастающую к самому низу, — рисунок грядки под забором
    остаётся собой, просто теплее/зеленее у самого края;
  * нижние ALPHA_GRAD_PX текстурных px дополнительно гасятся по альфе до 0 —
    мягкий градиент, чтобы даже небольшая неточность стыковки по Y не
    читалась жёсткой линией.

Гора
----
Высота ровно 5 клеток (160 логических = 480 текстурных px), ширина —
тот же масштаб, округлённый до целого числа клеток (25×96 = 2400,
расхождение с честной пропорцией <0.15% — на глаз незаметно).

Небо вырезается заливкой от кромки: сцена нарисована на ровном голубом небе,
поэтому связная область, дотянувшаяся от границы листа и похожая на цвет
неба (эталон — медиана верхней строки), помечается прозрачной. Мягкая альфа
на кромке гор/ёлок — небольшое гауссово размытие маски перед вырезкой, чтобы
силуэт не резался пилой при последующем апскейле.
Подпись «1 2 3 4 5» внизу справа (авторская сетка листа) вырезается по
bbox и заращивается зеркальной копией соседней травы — её не должно быть в
игре.

Бесшовность по X
-----------------
Проверяется общей метрикой (как в tools/test_import_assets.py::grass) —
отношение SSD шва (последний столбец против первого) к SSD обычного соседнего
перехода. Если отношение великовато, стык смягчается кросс-фейдом шириной
SEAM_BLEND_PX (~32 px): изображение прокручивается на полширины (шов уезжает
в середину, подальше от края тайла), там смешивается с шириной SEAM_BLEND_PX,
и прокручивается обратно — так противоположные края становятся общим
усреднением, а не двумя случайными кусками панорамы.

Запуск:  python3 tools/import_backdrops.py
"""

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "art", "_source")
OUT_DIR = os.path.join(ROOT, "art", "env")
TILES_DIR = os.path.join(ROOT, "art", "tiles")

ART_SCALE = 3
TILE_PX = 32 * ART_SCALE  # 96 — тайл на диске (см. tools/import_art.py)

FENCE_W = TILE_PX * 10   # 960 — 10 клеток повтора
FENCE_H = TILE_PX * 2    # 192 — 2 клетки высоты
MOUNTAIN_W = TILE_PX * 25   # 2400
MOUNTAIN_H = TILE_PX * 5    # 480

GRASS_STRIP_PX = 8 * ART_SCALE    # 24 — нижняя полоса, тонируемая под траву
ALPHA_GRAD_PX = 5 * ART_SCALE     # 15 — из них гасится по альфе до 0
SEAM_BLEND_PX = 32                # ширина кросс-фейда шва, если нужен
SEAM_RATIO_THRESHOLD = 3.0        # выше — считаем шов заметным и смягчаем

CAPTION_BBOX = (958, 192, 1024, 205)   # bbox подписи "1 2 3 4 5" на исходнике горы
SKY_TOL = 40.0                          # допуск похожести на цвет неба (L1 по RGB)
SKY_FEATHER_SIGMA = 1.0                 # мягкая альфа по краю гор/ёлок


# ── Lab (см. tools/import_tiles.py:rgb2lab/lab2rgb — та же формула, векторно) ──

_LIN = np.array([((v / 255 + 0.055) / 1.055) ** 2.4 if v > 10 else v / 255 / 12.92
                  for v in range(256)])


def rgb2lab_np(arr_u8: np.ndarray) -> np.ndarray:
    """arr_u8: (...,3) uint8 RGB -> (...,3) float Lab."""
    lin = _LIN[arr_u8]
    R, G, B = lin[..., 0], lin[..., 1], lin[..., 2]
    x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
    y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883

    def f(t):
        return np.where(t > 0.008856, np.cbrt(t), 7.787 * t + 16 / 116)

    fx, fy, fz = f(x), f(y), f(z)
    L = 116 * fy - 16
    a = 500 * (fx - fy)
    b = 200 * (fy - fz)
    return np.stack([L, a, b], axis=-1)


def lab2rgb_np(lab: np.ndarray) -> np.ndarray:
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200

    def g(t):
        t3 = t ** 3
        return np.where(t3 > 0.008856, t3, (t - 16 / 116) / 7.787)

    x, y, z = g(fx) * 0.95047, g(fy), g(fz) * 1.08883
    r = 3.2406 * x - 1.5372 * y - 0.4986 * z
    gg = -0.9689 * x + 1.8758 * y + 0.0415 * z
    b = 0.0557 * x - 0.2040 * y + 1.0570 * z
    out = np.stack([r, gg, b], axis=-1)
    out = np.clip(out, 0.0, 1.0)
    out = np.where(out > 0.0031308, 1.055 * np.power(out, 1 / 2.4) - 0.055, out * 12.92)
    return np.clip(np.round(out * 255), 0, 255).astype(np.uint8)


def mean_lab(path: str) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    a = np.asarray(im)
    lab = rgb2lab_np(a)
    return lab.reshape(-1, 3).mean(axis=0)


# ── метрика шва (как tools/test_import_assets.py::test_grass_seamless) ──

def seam_ratio(rgb: np.ndarray) -> float:
    a = rgb.astype(float)
    seam = float(np.mean((a[:, -1, :] - a[:, 0, :]) ** 2))
    neighbor = float(np.mean((a[:, 1:, :] - a[:, :-1, :]) ** 2))
    return seam / max(1.0, neighbor)


def crossfade_seam_x(arr: np.ndarray, blend: int) -> np.ndarray:
    """Смягчает стык левого/правого края по X: шов уезжает на полширины
    прокруткой, там смешивается по линейной рампе, потом прокручивается
    обратно — противоположные исходные края становятся общим усреднением."""
    h, w = arr.shape[:2]
    half = w // 2
    rolled = np.roll(arr, half, axis=1).astype(float)
    a0 = half - blend // 2
    left_src = rolled[:, a0 - 1:a0, :] if a0 > 0 else rolled[:, a0:a0 + 1, :]
    right_src = rolled[:, a0 + blend:a0 + blend + 1, :] if a0 + blend < w else rolled[:, a0 + blend - 1:a0 + blend, :]
    for i in range(blend):
        x = a0 + i
        if x < 0 or x >= w:
            continue
        t = i / max(1, blend - 1)
        rolled[:, x, :] = left_src[:, 0, :] * (1 - t) + right_src[:, 0, :] * t
    out = np.roll(rolled.astype(np.uint8), -half, axis=1)
    return out


# ── забор ──────────────────────────────────────────────────────────────────

def build_fence(src_name: str, out_name: str, grass_ref_lab: np.ndarray, report: list) -> None:
    im = Image.open(os.path.join(SRC_DIR, src_name)).convert("RGB")
    im = im.resize((FENCE_W, FENCE_H), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.uint8)

    ratio_before = seam_ratio(rgb)
    if ratio_before > SEAM_RATIO_THRESHOLD:
        rgb = crossfade_seam_x(rgb, SEAM_BLEND_PX)
    ratio_after = seam_ratio(rgb)
    report.append(f"{out_name}: шов_до={ratio_before:.2f} шов_после={ratio_after:.2f} "
                   f"(порог {SEAM_RATIO_THRESHOLD}, смягчён={ratio_before > SEAM_RATIO_THRESHOLD})")

    lab = rgb2lab_np(rgb)

    strip0 = FENCE_H - GRASS_STRIP_PX
    tone_before = lab[strip0:, :, :].reshape(-1, 3).mean(axis=0)

    for row in range(strip0, FENCE_H):
        t = (row - strip0 + 1) / GRASS_STRIP_PX   # 0 у верха полосы .. 1 у самого низа
        delta = grass_ref_lab - lab[row, :, :]
        lab[row, :, :] = lab[row, :, :] + delta * t

    tone_after = lab[strip0:, :, :].reshape(-1, 3).mean(axis=0)
    tone_gap_before = float(np.linalg.norm(tone_before - grass_ref_lab))
    tone_gap_after = float(np.linalg.norm(tone_after - grass_ref_lab))
    report.append(f"{out_name}: тон низа vs grass_1 (Lab-расстояние) до={tone_gap_before:.1f} "
                   f"после={tone_gap_after:.1f}")

    rgb = lab2rgb_np(lab)

    # Небо над лесом у забора — своё, тёмно-синее, и оно ОБЯЗАНО быть
    # прозрачным: за лесом стоит гора (backdrop_mountain.png), а за ней —
    # живое небо SkyView с солнцем/месяцем/звёздами. Непрозрачная синяя
    # полоса закрывала бы и то, и другое. Вырезаем той же заливкой от
    # кромки, что и небо горы (cut_sky: эталон — медиана верхней строки).
    sky_cut = cut_sky(rgb)
    sky_alpha = sky_cut[:, :, 3].astype(float)
    top_alpha_mean = float(sky_alpha[0, :].mean())
    report.append(f"{out_name}: альфа верхней строки (небо над лесом) = {top_alpha_mean:.1f} (0 = вырезано)")

    alpha = np.full((FENCE_H, FENCE_W), 255, dtype=float)
    grad0 = FENCE_H - ALPHA_GRAD_PX
    for row in range(grad0, FENCE_H):
        t = (row - grad0 + 1) / ALPHA_GRAD_PX      # 0 у верха градиента .. 1 у самого низа
        alpha[row, :] = round(255 * (1.0 - t))
    alpha = np.clip(alpha * sky_alpha / 255.0, 0, 255).astype(np.uint8)

    out = np.dstack([rgb, alpha])
    Image.fromarray(out, "RGBA").save(os.path.join(OUT_DIR, out_name))
    report.append(f"{out_name}: сохранён {FENCE_W}x{FENCE_H}, альфа низа: "
                   f"{alpha[FENCE_H - 1, 0]}..{alpha[grad0 - 1, 0]}")


# ── гора ───────────────────────────────────────────────────────────────────

def inpaint_caption(rgb: np.ndarray) -> np.ndarray:
    x0, y0, x1, y1 = CAPTION_BBOX
    w = x1 - x0
    out = rgb.copy()
    src = rgb[y0:y1, x0 - w:x0, :][:, ::-1, :]
    out[y0:y1, x0:x1, :] = src
    # мягкий шов на левой границе заплатки
    feather = 6
    for i in range(feather):
        t = i / feather
        out[y0:y1, x0 + i, :] = (out[y0:y1, x0 + i, :].astype(float) * t
                                  + rgb[y0:y1, x0 - 1, :].astype(float) * (1 - t)).astype(np.uint8)
    return out


def cut_sky(rgb: np.ndarray) -> np.ndarray:
    h, w, _ = rgb.shape
    ref = np.median(rgb[0].reshape(-1, 3).astype(float), axis=0)
    dist = np.abs(rgb.astype(float) - ref).sum(axis=2)
    like = dist < SKY_TOL

    lbl, _ = ndimage.label(like, structure=np.ones((3, 3)))
    border_labels = set(lbl[0, :].tolist()) | set(lbl[:, 0].tolist()) | set(lbl[:, -1].tolist())
    border_labels.discard(0)
    sky_mask = np.isin(lbl, list(border_labels))

    alpha = np.where(sky_mask, 0.0, 255.0)
    # мягкая альфа по кромке гор/ёлок — размываем маску, а не режем жёстко
    alpha = ndimage.gaussian_filter(alpha, sigma=SKY_FEATHER_SIGMA)
    alpha = np.clip(alpha, 0, 255).astype(np.uint8)
    return np.dstack([rgb, alpha])


def build_mountain(report: list) -> None:
    im = Image.open(os.path.join(SRC_DIR, "backdrop_mountain.jpg")).convert("RGB")
    rgb = np.asarray(im).astype(np.uint8)

    rgb = inpaint_caption(rgb)
    rgba = cut_sky(rgb)

    # верхняя строка обязана стать прозрачной (небо вырезано) — проверяем
    # ДО апскейла, где судить по исходным пикселям честнее.
    top_alpha_mean = float(rgba[0, :, 3].mean())
    report.append(f"backdrop_mountain.png: альфа верхней строки исходника (небо) = {top_alpha_mean:.1f} (0 = вырезано)")

    im_rgba = Image.fromarray(rgba, "RGBA").resize((MOUNTAIN_W, MOUNTAIN_H), Image.LANCZOS)
    arr = np.asarray(im_rgba)

    rgb_part = arr[:, :, :3]
    ratio_before = seam_ratio(rgb_part)
    alpha_part = arr[:, :, 3].astype(float)
    seam_alpha = float(np.mean((alpha_part[:, -1] - alpha_part[:, 0]) ** 2))
    neighbor_alpha = float(np.mean((alpha_part[:, 1:] - alpha_part[:, :-1]) ** 2))
    ratio_alpha = seam_alpha / max(1.0, neighbor_alpha)
    report.append(f"backdrop_mountain.png: шов_RGB={ratio_before:.2f} шов_альфа={ratio_alpha:.2f}")

    if ratio_before > SEAM_RATIO_THRESHOLD or ratio_alpha > SEAM_RATIO_THRESHOLD:
        rgb_blended = crossfade_seam_x(rgb_part, SEAM_BLEND_PX)
        alpha_blended = crossfade_seam_x(
            np.dstack([alpha_part, alpha_part, alpha_part]).astype(np.uint8), SEAM_BLEND_PX)[:, :, 0]
        arr = np.dstack([rgb_blended, alpha_blended])
        ratio_after = seam_ratio(rgb_blended)
        report.append(f"backdrop_mountain.png: шов смягчён кросс-фейдом, шов_RGB_после={ratio_after:.2f}")
    else:
        report.append("backdrop_mountain.png: шов и так в пределах нормы, кросс-фейд не понадобился")

    Image.fromarray(arr, "RGBA").save(os.path.join(OUT_DIR, "backdrop_mountain.png"))
    report.append(f"backdrop_mountain.png: сохранён {MOUNTAIN_W}x{MOUNTAIN_H}, "
                   f"альфа верхней строки результата = {float(arr[0, :, 3].mean()):.1f}")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    report: list = []

    grass_ref_lab = mean_lab(os.path.join(TILES_DIR, "grass_1.png"))
    report.append(f"эталон тона травы (Lab, grass_1.png): L={grass_ref_lab[0]:.1f} "
                   f"a={grass_ref_lab[1]:.1f} b={grass_ref_lab[2]:.1f}")

    build_fence("backdrop_fence_white.jpg", "backdrop_fence_white.png", grass_ref_lab, report)
    build_fence("backdrop_fence_old.jpg", "backdrop_fence_old.png", grass_ref_lab, report)
    build_mountain(report)

    print("\n".join(report))


if __name__ == "__main__":
    main()
