#!/usr/bin/env python3
"""hero_ref_extract.py — эталон мальчика от владельца в «родную» пиксельную сетку.

Владелец (раунд 4): «Мальчик сейчас выглядит ужасно, я добавил картинку как он
должен выглядеть» — art/_source/hero_reference.jpg (768×1376, зелёный фон) и
«я добавил анимацию его ходьбы» — art/_source/hero_walk_turn.mp4 (736×1280,
8 кадров/с, 16 кадров: 1–2 анфас, 3 — поворот, 4–16 — ходьба в профиль).

Оба файла — пиксель-арт, растянутый в нецелое число раз и пережатый (JPEG,
H.264): у эталона «пиксель» 5,733 px (холст 134×240 растянут до 768×1376), у
первого кадра видео — 5,5 px; в остальных кадрах видео сетки нет (генератор
движения её размыл), их уменьшаем площадью в те же 5,5 раза. Фигура выходит
ровно 160 пикселей рисунка ростом — это 40 логических точек героя в игре, то
есть 4 пикселя рисунка на точку.

Что делает скрипт (результат — art/_source/hero_ref/, скрыт от Godot):
  * находит период и фазу сетки по энергии перепадов (Фурье по строкам/столбцам);
  * берёт цвет из середины каждой клетки (медиана, без краёв клетки — там JPEG
    смешивает соседей);
  * хромакей: клетка — фон, если в ней больше половины «зелёных» пикселей
    (g − max(r, b) > 45); у краёв фигуры цвет берётся только из незелёных
    пикселей клетки, и зелёный канал срезается до среднего красного и синего
    (подавление зелени: ни у одного материала мальчика g не выше) — зелёный
    ореол JPEG/H.264 не попадает в рисунок;
  * палитра: 32 цвета k-средних (Lab) по эталону; все кадры видео сводятся к
    ней же — JPEG-шума и зелени нет, альфа только 0/255;
  * одиночные пиксели-сироты по краю убираются, дырки в 1 пиксель — заливаются.

Нужен ffmpeg (только этой стадии). Дальше всё строит tools/gen_hero_ref.py
из готовых PNG, без ffmpeg.

Запуск:  python3 tools/hero_ref_extract.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "_source")
REF_JPG = os.path.join(SRC, "hero_reference.jpg")
WALK_MP4 = os.path.join(SRC, "hero_walk_turn.mp4")
OUT = os.path.join(SRC, "hero_ref")

PALETTE_SIZE = 32
GREEN_KEY = 45.0


def srgb_to_lab(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]),
                     200.0 * (f[..., 1] - f[..., 2])], -1)


def grid_of(img, box, lo=3.0, hi=12.0):
    """Период и фаза сетки (x, y) по перепадам внутри box."""
    x0, y0, x1, y1 = box
    c = img[y0:y1, x0:x1]
    res = []
    for axis, o in ((1, x0), (0, y0)):
        g = np.abs(np.diff(c, axis=axis)).sum(axis=2).sum(axis=1 - axis)
        idx = np.arange(len(g)) + 0.5
        best = (0.0, 0.0)
        for p in np.arange(lo, hi, 0.005):
            s = abs((g * np.exp(2j * np.pi * idx / p)).sum()) / g.sum()
            if s > best[0]:
                best = (s, p)
        p = best[1]
        ang = np.angle((g * np.exp(2j * np.pi * idx / p)).sum())
        res.append((p, ((ang / (2 * np.pi)) * p + o) % p, best[0]))
    return res


def sample_cells(img, px, py, center_only):
    """Клетки сетки: цвет (медиана незелёных пикселей) и доля зелени."""
    (p, phx), (q, phy) = px, py
    h, w, _ = img.shape
    nx = int((w - phx) // p)
    ny = int((h - phy) // q)
    col = np.zeros((ny, nx, 3), np.float64)
    green = np.ones((ny, nx), np.float64)
    isbg = (img[..., 1] - np.maximum(img[..., 0], img[..., 2])) > GREEN_KEY
    for j in range(ny):
        ya = phy + j * q
        y0, y1 = (int(round(ya + q * 0.22)), int(round(ya + q * 0.78)) + 1) if center_only \
            else (int(round(ya)), int(round(ya + q)))
        for i in range(nx):
            xa = phx + i * p
            x0, x1 = (int(round(xa + p * 0.22)), int(round(xa + p * 0.78)) + 1) if center_only \
                else (int(round(xa)), int(round(xa + p)))
            blk = img[max(0, y0):y1, max(0, x0):x1].reshape(-1, 3)
            m = isbg[max(0, y0):y1, max(0, x0):x1].reshape(-1)
            if blk.size == 0:
                continue
            green[j, i] = m.mean()
            fg = blk[~m].copy()
            if len(fg):
                # Подавление зелени: у всех материалов мальчика g не выше
                # среднего r и b, зелёный оттенок даёт только ореол фона.
                fg[:, 1] = np.minimum(fg[:, 1], (fg[:, 0] + fg[:, 2]) * 0.5 + 2.0)
                col[j, i] = np.median(fg, axis=0)
    return col, green < 0.5


def kmeans(x, k, iters=50):
    """Детерминированные k-средних (k-means++ по дальнему пикселю)."""
    c = [x[np.argmin(x[:, 0])]]
    for _ in range(1, k):
        d = np.min(((x[:, None] - np.array(c)[None]) ** 2).sum(-1), axis=1)
        c.append(x[int(np.argmax(d))])
    c = np.array(c, np.float64)
    lab = np.zeros(len(x), int)
    for _ in range(iters):
        lab = np.argmin(((x[:, None] - c[None]) ** 2).sum(-1), axis=1)
        new = np.array([x[lab == j].mean(0) if (lab == j).any() else c[j] for j in range(k)])
        if np.allclose(new, c):
            break
        c = new
    return c, lab


def quantize(col, mask, pal_rgb):
    pal_lab = srgb_to_lab(pal_rgb)
    out = np.zeros(col.shape[:2] + (4,), np.uint8)
    lab = srgb_to_lab(col[mask])
    idx = np.argmin(((lab[:, None] - pal_lab[None]) ** 2).sum(-1), axis=1)
    out[..., :3][mask] = pal_rgb[idx]
    out[..., 3][mask] = 255
    return out


def tidy(img):
    """Сироты по краю (≤1 соседа) — прочь; дырки (≥3 соседа) — цвет соседей."""
    a = img[..., 3] > 0
    for _ in range(2):
        pad = np.pad(a, 1)
        n = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
        lone = a & (n <= 1)
        img[lone] = 0
        a = img[..., 3] > 0
        pad = np.pad(a, 1)
        n = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
        holes = np.argwhere((~a) & (n >= 3))
        for y, x in holes:
            nb = [img[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
                  if 0 <= yy < img.shape[0] and 0 <= xx < img.shape[1] and img[yy, xx, 3]]
            if nb:
                img[y, x] = min(nb, key=lambda c: int(c[0]) + int(c[1]) + int(c[2]))
        a = img[..., 3] > 0
    return img


def video_frames(tmp):
    subprocess.run(["ffmpeg", "-v", "error", "-i", WALK_MP4, os.path.join(tmp, "f%02d.png")], check=True)
    names = sorted(f for f in os.listdir(tmp) if f.endswith(".png"))
    return [np.asarray(Image.open(os.path.join(tmp, f)).convert("RGB")).astype(np.float64) for f in names]


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, ".gdignore"), "w") as f:
        f.write("")
    ref = np.asarray(Image.open(REF_JPG).convert("RGB")).astype(np.float64)
    gx, gy = grid_of(ref, (280, 290, 630, 1230))
    print("эталон: пиксель %.3f×%.3f px, фаза %.2f/%.2f, чёткость сетки %.2f/%.2f"
          % (gx[0], gy[0], gx[1], gy[1], gx[2], gy[2]))
    col, mask = sample_cells(ref, gx[:2], gy[:2], True)
    lab = srgb_to_lab(col[mask])
    centers, member = kmeans(lab, PALETTE_SIZE)
    pal = np.array([np.median(col[mask][member == j], axis=0) for j in range(PALETTE_SIZE)])
    pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
    order = np.argsort(srgb_to_lab(pal)[:, 0])
    pal = pal[order]
    Image.fromarray(pal[None]).save(os.path.join(OUT, "palette.png"))
    native = tidy(quantize(col, mask, pal.astype(np.float64)))
    Image.fromarray(native).save(os.path.join(OUT, "ref.png"))
    ys, xs = np.nonzero(native[..., 3])
    print("эталон: холст %d×%d, фигура %d×%d" % (native.shape[1], native.shape[0],
                                               xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))

    tmp = tempfile.mkdtemp(prefix="hero_walk_")
    try:
        frames = video_frames(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    vx, vy = grid_of(frames[0], (200, 250, 560, 1180))
    print("видео: пиксель %.3f×%.3f px (по первому кадру), фаза %.2f/%.2f"
          % (vx[0], vy[0], vx[1], vy[1]))
    for i, fr in enumerate(frames):
        # Сетка есть только у первых кадров; у остальных — та же решётка
        # площадью: середина клетки там не точнее среднего.
        col, mask = sample_cells(fr, vx[:2], vy[:2], i < 2)
        img = tidy(quantize(col, mask, pal.astype(np.float64)))
        Image.fromarray(img).save(os.path.join(OUT, "walk_%02d.png" % (i + 1)))
        ys, xs = np.nonzero(img[..., 3])
        print("  кадр %2d: фигура %d×%d" % (i + 1, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))


if __name__ == "__main__":
    sys.exit(main())
