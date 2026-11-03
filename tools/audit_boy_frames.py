#!/usr/bin/env python3
"""audit_boy_frames.py — обмер кадров героя: размер кадра, линия земли, подошва,
макушка, рост тела и ширина лица по КАЖДОМУ кадру каждого листа.

Зачем: при смене позы мальчик «прыгал» и менял размер — листы нарезались
разными импортёрами (tools/import_move.py, import_dig.py, import_packs.py,
import_drill.py …) с разными правилами якоря. Этот скрипт печатает таблицу
«что есть на самом деле» и сверяет её с метаданными привязки
art/character/poses.json (единая линия земли и рост тела на позу).

Что меряется в кадре (пиксели текстуры, ART_SCALE=3 к логическим):
  sole   — подошва: самый нижний непрозрачный пиксель в полосе колонок под
           лицом (±SOLE_HALF от центра лица) — инструмент сбоку не мешает;
  crown  — макушка: от верха лица вверх по непрозрачным пикселям той же
           полосы колонок, пока они не кончатся (волосы над лицом);
  face   — лицо: самая крупная связная область цвета кожи (руки меньше);
  body_h — crown..sole;
  face_w — ширина лица (масштаб персонажа: одинаковая во всех позах, если
           он не «вырос»).

Запуск:
  python3 tools/audit_boy_frames.py                 # таблица по всем листам
  python3 tools/audit_boy_frames.py --debug out.png # + лист с линиями
  python3 tools/audit_boy_frames.py --json out.json # сырые числа
  python3 tools/audit_boy_frames.py --dir boy_gear  # другой набор листов
Код возврата 0; таблица — в stdout (Markdown).
"""

import argparse
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POSES_JSON = os.path.join(ROOT, "art", "character", "poses.json")

ALPHA_MIN = 40
SOLE_HALF = 21      # полоса колонок под лицом для подошвы (±7 логических px)
CROWN_HALF = 12     # полоса колонок над лицом для макушки
MIN_FACE_PX = 60    # меньше — это рука, не лицо

# Резерв на случай отсутствия poses.json: геометрия, вбитая раньше в
# character_view.gd:SHEET_FRAME (ширина, высота, линия земли).
FALLBACK_FRAME = {
    "dig_pick": (192, 144, 138), "dig_pick_rusty": (192, 144, 138), "dig_shovel": (192, 144, 138),
    "dig_rig_down": (240, 168, 150), "dig_rig_side": (240, 168, 150), "rig_jump": (240, 168, 150),
    "rig_fly": (220, 220, 150), "fly_1": (154, 162, 156), "fly_2": (204, 165, 163),
    "fly_3": (152, 141, 129), "fly_4": (260, 136, 123), "rig_exit": (348, 168, 150),
}
DEFAULT_FRAME = (144, 144, 138)

SHEETS = ["idle", "walk", "fall", "fly", "fly_jet", "fly_1", "fly_2", "fly_3", "fly_4",
          "dig_shovel", "dig_pick", "dig_pick_rusty", "dig_drill_down", "dig_drill_side",
          "dig_rig_down", "dig_rig_side", "rig_jump", "rig_fly", "rig_exit", "sleep"]


def load_poses():
    if not os.path.exists(POSES_JSON):
        return {}
    with open(POSES_JSON, encoding="utf-8") as f:
        doc = json.load(f)
    return doc.get("poses", {})


def frame_geom(name, poses):
    p = poses.get(name)
    if p:
        return int(p["frame_w"]), int(p["frame_h"]), int(p["ground_y"]), p
    fw, fh, gy = FALLBACK_FRAME.get(name, DEFAULT_FRAME)
    return fw, fh, gy, None


def skin_mask(a):
    r = a[:, :, 0].astype(int)
    g = a[:, :, 1].astype(int)
    b = a[:, :, 2].astype(int)
    op = a[:, :, 3] > ALPHA_MIN
    return op & (r >= 200) & (g >= 140) & (g <= 215) & (b >= 100) & (b <= 195) \
        & (r > g) & (g > b) & (r - b >= 45)


def largest_component(mask):
    """Самая крупная 4-связная область маски: (пиксели, bbox) или None."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    best = None
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if best is None or len(pts) > len(best[0]):
            best = (pts, None)
    if best is None:
        return None
    pts = best[0]
    py = [p[0] for p in pts]
    px = [p[1] for p in pts]
    return len(pts), (min(px), min(py), max(px), max(py))


def measure_frame(cell):
    """Обмер одного кадра (RGBA numpy). Возвращает dict или None для пустого кадра."""
    a = cell
    op = a[:, :, 3] > ALPHA_MIN
    if not op.any():
        return None
    ys, xs = np.nonzero(op)
    out = {"bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]}
    face = largest_component(skin_mask(a))
    if face is None or face[0] < MIN_FACE_PX:
        out["face"] = None
        # без лица — подошва по всему кадру
        out["sole"] = int(ys.max())
        out["crown"] = int(ys.min())
        out["cx"] = float((xs.min() + xs.max()) / 2.0)
        return out
    fx0, fy0, fx1, fy1 = face[1]
    cx = (fx0 + fx1) / 2.0
    out["face"] = [int(fx0), int(fy0), int(fx1), int(fy1)]
    out["face_w"] = int(fx1 - fx0 + 1)
    out["face_cy"] = float((fy0 + fy1) / 2.0)
    out["cx"] = float(cx)
    h, w = op.shape
    # подошва — ниже лица, в полосе колонок под ним
    x0 = max(0, int(round(cx)) - SOLE_HALF)
    x1 = min(w, int(round(cx)) + SOLE_HALF + 1)
    band = op[:, x0:x1]
    rows = np.nonzero(band.any(axis=1))[0]
    below = rows[rows > fy1]
    out["sole"] = int(below.max()) if below.size else int(fy1)
    # макушка — от верха лица вверх, пока в узкой полосе есть непрозрачное
    x0 = max(0, int(round(cx)) - CROWN_HALF)
    x1 = min(w, int(round(cx)) + CROWN_HALF + 1)
    narrow = op[:, x0:x1].any(axis=1)
    y = fy0
    while y - 1 >= 0 and narrow[y - 1]:
        y -= 1
    out["crown"] = int(y)
    return out


def audit_sheet(path, fw, fh):
    im = Image.open(path).convert("RGBA")
    if im.height < fh:
        fh = im.height
    n = max(1, im.width // fw)
    frames = []
    for i in range(n):
        cell = np.array(im.crop((i * fw, 0, (i + 1) * fw, fh)))
        frames.append(measure_frame(cell))
    return im, n, frames


def fmt_range(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return "—"
    lo, hi = min(vals), max(vals)
    return "%g" % lo if lo == hi else "%g..%g" % (lo, hi)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="", help="подкаталог art/character (boy_gear, grandpa …)")
    ap.add_argument("--sheets", default="", help="список листов через запятую")
    ap.add_argument("--debug", default="", help="PNG с измеренными линиями")
    ap.add_argument("--json", default="", help="сырые числа в JSON")
    args = ap.parse_args()

    poses = load_poses()
    names = args.sheets.split(",") if args.sheets else SHEETS
    base = os.path.join(ROOT, "art", "character", args.dir)
    rows = []
    raw = {}
    debug_rows = []
    print("| лист | кадр w×h | кадров | земля (мета) | подошва | макушка | рост тела | ширина лица | центр x−ось |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name in names:
        path = os.path.join(base, name + ".png")
        if not os.path.exists(path):
            continue
        fw, fh, gy, meta = frame_geom(name, poses)
        im, n, frames = audit_sheet(path, fw, fh)
        soles = [f["sole"] for f in frames if f]
        crowns = [f["crown"] for f in frames if f]
        bodies = [f["sole"] - f["crown"] + 1 for f in frames if f]
        faces = [f.get("face_w") for f in frames if f]
        cxs = [round(f["cx"] - (fw - 1) / 2.0, 1) for f in frames if f]
        print("| %s | %d×%d | %d | %d | %s | %s | %s | %s | %s |" % (
            name, fw, fh, n, gy, fmt_range(soles), fmt_range(crowns), fmt_range(bodies),
            fmt_range(faces), fmt_range(cxs)))
        raw[name] = {"frame_w": fw, "frame_h": fh, "ground_y": gy, "frames": frames}
        if args.debug:
            debug_rows.append((name, [(name, i, im.crop((i * fw, 0, (i + 1) * fw, fh)), gy, f)
                                      for i, f in enumerate(frames)]))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fp:
            json.dump(raw, fp, ensure_ascii=False, indent=1)

    if args.debug:
        pad = 4
        per_row = 8
        rows_img = []
        for name, group in debug_rows:
            for start in range(0, len(group), per_row):
                rows_img.append(group[start:start + per_row])
        cw = max(max(c[2].width for c in r) for r in rows_img) + pad
        ch_list = [max(c[2].height for c in r) + pad + 12 for r in rows_img]
        out = Image.new("RGBA", (cw * per_row, sum(ch_list)), (40, 44, 52, 255))
        d = ImageDraw.Draw(out)
        y_row = 0
        for r, ch in zip(rows_img, ch_list):
            for k, (name, i, cell, gy, f) in enumerate(r):
                x = k * cw
                y = y_row + 12
                out.alpha_composite(cell, (x, y))
                d.line([(x, y + gy), (x + cell.width, y + gy)], fill=(255, 70, 70, 255))
                if f:
                    d.line([(x, y + f["sole"]), (x + cell.width, y + f["sole"])], fill=(80, 255, 120, 255))
                    d.line([(x, y + f["crown"]), (x + cell.width, y + f["crown"])], fill=(90, 180, 255, 255))
                    d.line([(x + int(f["cx"]), y), (x + int(f["cx"]), y + cell.height)], fill=(255, 150, 255, 160))
                    if f.get("face"):
                        fx0, fy0, fx1, fy1 = f["face"]
                        d.rectangle([x + fx0, y + fy0, x + fx1, y + fy1], outline=(255, 230, 60, 255))
                d.text((x + 2, y - 11), "%s %d" % (name, i), fill=(240, 210, 90, 255))
            y_row += ch
        out.save(args.debug)
        print("\nотладочный лист:", args.debug, out.size, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
