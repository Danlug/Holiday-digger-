#!/usr/bin/env python3
"""walls_check.py — объективная проверка стен-фонов (ветка «walls»): шов, тон, контраст.

Для каждой art/env/deep/wall_*.png:
  * шов: средний модуль разности пикселей через край плитки (и по X, и по Y) относительно такой же
    разности внутри плитки; у бесшовной плитки отношение около 1 (допуск 1.35);
  * тон: средняя яркость (Y 0..255) — стена тёмная (не выше MAX_MEAN) и низкоконтрастная (σ яркости не выше MAX_STD);
  * свечение: доля очень ярких пикселей (Y > 150) — не больше MAX_HOT, чтобы не спорить с лавой и рудами;
  * размер: квадрат, сторона кратна 8 (период дизера) — DeepBackdrop берёт период из размера.
Код возврата 1 при нарушении. Это дополнение к просмотру глазами, а не замена ему.

  python3 tools/walls_check.py
"""

import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEAM_MAX = 1.15
MAX_MEAN = 66.0
MAX_STD = 30.0
MAX_HOT = 0.012


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def seam_ratio(a):
    """Разность через шов относительно 98-го перцентиля разностей между соседними столбцами/строками внутри плитки."""
    y = lum(a)
    out = 0.0
    for arr in (y, y.T):
        inner = np.abs(arr[:, 1:] - arr[:, :-1]).mean(0)
        seam = np.abs(arr[:, 0] - arr[:, -1]).mean()
        out = max(out, seam / (np.percentile(inner, 98) + 1e-9))
    return out


def main():
    biomes = json.load(open(os.path.join(ROOT, "data", "world_layers.json"), encoding="utf-8"))["biomes"]["list"]
    bad = 0
    for b in biomes:
        n = b["wall"]
        path = os.path.join(ROOT, "art", "env", "deep", f"wall_{n}.png")
        a = np.array(Image.open(path).convert("RGB"), dtype=np.float64)
        h, w = a.shape[:2]
        y = lum(a)
        sr = seam_ratio(a)
        hot = float((y > 150).mean())
        msg = f"{n:8s} {w}x{h} сред. Y {y.mean():5.1f} σ {y.std():5.1f} шов x{sr:4.2f} ярких {hot * 100:4.2f}%"
        probs = []
        if w != h or w % 8:
            probs.append("размер")
        if sr > SEAM_MAX:
            probs.append("шов")
        if y.mean() > MAX_MEAN:
            probs.append("светлая")
        if y.std() > MAX_STD:
            probs.append("контрастная")
        if hot > MAX_HOT:
            probs.append("яркие пятна")
        print(msg + ("  <-- " + ",".join(probs) if probs else "  ok"))
        bad += bool(probs)
    print("OK" if not bad else f"НАРУШЕНИЙ: {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
