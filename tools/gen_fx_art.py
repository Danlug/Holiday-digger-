#!/usr/bin/env python3
"""gen_fx_art.py — мелкая графика эффектов мира (ветка «world-fx»): мягкий ореол, контактная тень, огонёк глаз.

Всё белое/чёрное с альфой: цвет ставит игра (modulate), поэтому один ореол служит урану, лаве и ангельскому камню.
Альфа не плавная, а ступенчатая (7 уровней) с упорядоченным дизерингом по границам ступеней, как у остального
пиксель-арта: мягко, но без размытия. Запуск из корня: python3 tools/gen_fx_art.py
"""
import math
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "fx")
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float64) / 16.0


def dither_levels(a, levels):
    """Квантует альфу 0..1 на levels ступеней, добавляя Байера по границам ступеней."""
    h, w = a.shape
    b = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    return np.clip(np.floor(a * levels + b), 0, levels) / levels


def halo(n=96):
    """Ореол: не пик в центре (руда сама яркая и пересветилась бы), а широкое плечо вокруг клетки."""
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.hypot(xx - (n - 1) / 2.0, yy - (n - 1) / 2.0) / (n / 2.0)
    prof = np.where(r < 0.16, 0.30 + r * 2.6, 0.72 * np.clip(1.0 - (r - 0.16) / 0.84, 0, 1) ** 1.6)
    prof = np.where(r >= 1.0, 0.0, prof)
    a = dither_levels(prof, 7)
    img = np.zeros((n, n, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.round(a * 255).astype(np.uint8)
    return Image.fromarray(img)


def shadow(w=28, h=9):
    """Контактная тень: плотное ядро, редкий дизеринг по краю. Чёрная, цвет не нужен."""
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - (w - 1) / 2.0) / (w / 2.0), (yy - (h - 1) / 2.0) / (h / 2.0))
    prof = np.where(r >= 1.0, 0.0, 0.82 * np.clip(1.0 - r ** 2.0, 0, 1))
    a = dither_levels(prof, 5)
    img = np.zeros((h, w, 4), np.uint8)
    img[..., 3] = np.round(a * 255).astype(np.uint8)
    return Image.fromarray(img)


def eye(n=9):
    """Огонёк глаза/светляка: 3x3 ядро и крест вокруг, цвет — modulate."""
    img = np.zeros((n, n, 4), np.uint8)
    c = n // 2
    for y in range(n):
        for x in range(n):
            d = max(abs(x - c), abs(y - c))
            dd = abs(x - c) + abs(y - c)
            a = 0.0
            if d <= 0:
                a = 1.0
            elif dd <= 1:
                a = 0.85
            elif d <= 1:
                a = 0.5
            elif dd <= 2:
                a = 0.35
            elif dd <= 3:
                a = 0.14
            img[y, x] = (255, 255, 255, int(round(a * 255)))
    return Image.fromarray(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    halo().save(os.path.join(OUT, "glow_soft.png"))
    shadow().save(os.path.join(OUT, "shadow_blob.png"))
    eye().save(os.path.join(OUT, "glow_eye.png"))
    print("art/fx: glow_soft.png 96x96, shadow_blob.png 28x9, glow_eye.png 9x9")


if __name__ == "__main__":
    main()
