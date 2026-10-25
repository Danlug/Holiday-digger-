#!/usr/bin/env python3
"""check_ores.py — объективная проверка ресурсов: не слишком ли похожи друг на друга и видны ли на грунте.

Для каждой руды берётся её залежь без грунта: у перерисованных (tools/ores_metals.py, tools/ores_gems.py,
реестр TILES) — альфа спрайта, у прежних — маска «не грунт» из tools/gen_tiles_deep.py (soil_weights).
Меряем:
  * цвет залежи — средний Lab по телу (без контура и краевых пикселей), расстояние ΔE между парами;
  * форма — IoU силуэтов на сетке 16x16 после центрирования + расстояние гистограмм направлений
    градиента яркости (полоски против пятен против граней);
  * видимость — ΔE тела залежи до грунта поясов, где руда встречается заметно (от depth_min до depth_min+1500),
    должно быть >= MIN_CONTRAST.
Пара «слишком похожа» (see too_similar): цвета далеки (ΔE >= 20) — всегда нормально; ΔE 12..20 — нормально,
только если силуэты заметно разные (shape >= 0.9); ΔE < 12 — одна и та же краска: допустимо лишь при совсем разных
силуэтах (shape >= 1.3), на практике — нужно менять цвет.
Код возврата 1, если есть похожие пары или невидимые ресурсы среди проверяемых.

  python3 tools/check_ores.py                       # все руды, отчёт в stdout
  python3 tools/check_ores.py --only ore_iron,ore_lead   # пары, в которых участвует хотя бы одна из перечисленных
  python3 tools/check_ores.py --sheet /tmp/ores.png      # контрольный лист (залежи на грунте пояса 0 и 4, значки)
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tiles_deep as gtd  # noqa: E402

ROOT = gtd.ROOT
COLOR_FAR = 20.0       # ΔE76: от этого расстояния цвета читаются как разные
COLOR_SAME = 12.0      # ΔE76: ближе — одна и та же краска
SHAPE_FAR = 0.90       # при ΔE 12..20 силуэты должны отличаться не меньше этого
SHAPE_VERY_FAR = 1.30  # при ΔE < 12 — только совсем несхожие силуэты
MIN_CONTRAST = 20.0    # ΔE тела залежи до грунта
GRID = 16


def too_similar(de, shape):
    if de >= COLOR_FAR:
        return False
    if de >= COLOR_SAME:
        return shape < SHAPE_FAR
    return shape < SHAPE_VERY_FAR


def _body_mask(alpha):
    """Тело залежи: непрозрачные пиксели, не стоящие на краю (контур и тень не считаем цветом руды)."""
    if (alpha > 0.5).sum() < 12:   # прежняя руда «своего тона»: берём самые не-грунтовые 15%
        solid = alpha >= np.quantile(alpha, 0.85)
        return solid
    solid = alpha > 0.5
    edge = np.zeros_like(solid)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        shifted = np.roll(np.roll(solid, dy, 0), dx, 1)
        edge |= solid & ~shifted
    body = solid & ~edge
    return body if body.sum() >= 12 else solid


def _legacy_alpha(name, ref_lab):
    arr = gtd.load(os.path.join(gtd.TILES, name + ".png"))
    w = gtd.soil_weights(gtd.rgb2lab(arr), ref_lab)
    return arr, (1.0 - w)


def collect():
    dirt = [gtd.load(os.path.join(gtd.TILES, f"dirt_{i}.png")) for i in range(1, 9)]
    ref_lab = np.mean([gtd.rgb2lab(d).reshape(-1, 3).mean(0) for d in dirt], axis=0)
    out = {}
    for name in gtd.ATLAS_NAMES:
        if not name.startswith("ore_"):
            continue
        if name in gtd.SPRITES:
            img = gtd.SPRITES[name]().upscale()
            a = np.array(img, dtype=np.float64)
            rgb, alpha, src = a[..., :3], a[..., 3] / 255.0, "спрайт"
        else:
            rgb, alpha = _legacy_alpha(name, ref_lab)
            src = "прежняя"
        body = _body_mask(alpha)
        lab = gtd.rgb2lab(rgb)
        mean_lab = lab[body].mean(0)
        out[name] = {"rgb": rgb, "alpha": alpha, "body": body, "lab": lab, "mean_lab": mean_lab, "src": src}
    biomes = json.load(open(os.path.join(ROOT, "data", "world_layers.json"), encoding="utf-8"))["biomes"]["list"]
    soils = [np.array(ref_lab)] + [np.array(b["soil"], dtype=np.float64) for b in biomes[1:]]
    return out, soils


def _sil(alpha):
    m = alpha > 0.5
    ys, xs = np.nonzero(m)
    if len(ys) == 0:
        return np.zeros((GRID, GRID), dtype=bool)
    crop = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(np.uint8) * 255
    side = max(crop.shape)
    canvas = np.zeros((side, side), dtype=np.uint8)
    oy, ox = (side - crop.shape[0]) // 2, (side - crop.shape[1]) // 2
    canvas[oy:oy + crop.shape[0], ox:ox + crop.shape[1]] = crop
    small = Image.fromarray(canvas).resize((GRID, GRID), Image.BILINEAR)
    return np.array(small) > 110


def _orient_hist(lab, body):
    L = lab[..., 0]
    gy, gx = np.gradient(L)
    mag = np.hypot(gx, gy) * body
    ang = (np.arctan2(gy, gx) % np.pi) / np.pi * 8
    h = np.zeros(8)
    for b in range(8):
        h[b] = mag[(ang >= b) & (ang < b + 1)].sum()
    s = h.sum()
    return h / s if s > 0 else h


def pair_metrics(a, b):
    de = float(np.linalg.norm(a["mean_lab"] - b["mean_lab"]))
    sa, sb = _sil(a["alpha"]), _sil(b["alpha"])
    inter, union = (sa & sb).sum(), (sa | sb).sum()
    iou = inter / union if union else 0.0
    hd = float(np.abs(_orient_hist(a["lab"], a["body"]) - _orient_hist(b["lab"], b["body"])).sum()) / 2.0
    shape = (1.0 - iou) + hd
    return de, shape, iou


_TILE_TO_ID = {"ore_iron": "iron_ore", "ore_universalium": "universum"}
_BIOMES = None
_MINERALS = None


def relevant_belts(name):
    """Пояса, где руда встречается заметно: от depth_min до min(depth_max, depth_min + 1500).
    Торф живёт только у поверхности, уголь — с 1000: требовать видимость на поясах, где их нет, нет смысла."""
    global _BIOMES, _MINERALS
    if _BIOMES is None:
        _BIOMES = json.load(open(os.path.join(ROOT, "data", "world_layers.json"), encoding="utf-8"))["biomes"]["list"]
        raw = json.load(open(os.path.join(ROOT, "data", "minerals.json"), encoding="utf-8"))
        ms = raw.get("minerals", raw)
        _MINERALS = ms if isinstance(ms, dict) else {m["id"]: m for m in ms}

    def val(x, default):
        x = x.get("value") if isinstance(x, dict) else x
        return default if x is None else float(x)

    m = _MINERALS.get(_TILE_TO_ID.get(name, name[4:]), {})
    lo = val(m.get("depth_min"), 1.0)
    hi = min(val(m.get("depth_max"), 10000.0), lo + 1500.0)
    belts = [i for i, b in enumerate(_BIOMES) if b["y_from"] <= hi and b["y_to"] >= lo]
    return belts or list(range(len(_BIOMES)))


def contrast(r, soils, name=None):
    belts = relevant_belts(name) if name else range(len(soils))
    return min(float(np.linalg.norm(r["mean_lab"] - soils[i])) for i in belts)


def sheet(data, soils, path):
    names = list(data.keys())
    cell, cols, pad = gtd.T, 8, 6
    rows = (len(names) + cols - 1) // cols
    dirt0 = gtd.load(os.path.join(gtd.TILES, "dirt_1.png"))
    sheet_img = Image.new("RGB", (cols * (cell + pad) + pad, rows * (cell * 2 + pad + 22) + pad), (30, 25, 22))
    d = ImageDraw.Draw(sheet_img)
    for i, n in enumerate(names):
        r = data[n]
        x = pad + (i % cols) * (cell + pad)
        y = pad + (i // cols) * (cell * 2 + pad + 22)
        tile0 = np.clip(dirt0 * (1 - r["alpha"][..., None]) + r["rgb"] * r["alpha"][..., None], 0, 255)
        sheet_img.paste(Image.fromarray(tile0.astype(np.uint8)), (x, y))
        icon = Image.new("RGB", (cell, cell), (22, 18, 16))
        if n in gtd.SPRITES:
            ic = gtd.SPRITES[n]().icon().resize((cell, cell), Image.NEAREST)
            icon.paste(ic, (0, 0), ic)
        sheet_img.paste(icon, (x, y + cell))
        d.text((x, y + cell * 2 + 2), n[4:] + ("" if r["src"] == "спрайт" else " *"), fill=(240, 210, 90))
    sheet_img.save(path)
    print("лист:", path, "(* — ещё прежняя графика)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    data, soils = collect()
    names = list(data.keys())
    flagged, invisible = [], []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if only and a not in only and b not in only:
                continue
            de, shape, iou = pair_metrics(data[a], data[b])
            if too_similar(de, shape):
                flagged.append((a, b, de, shape))
    for n in names:
        if only and n not in only:
            continue
        c = contrast(data[n], soils, n)
        if c < MIN_CONTRAST:
            invisible.append((n, c))
    legacy = [n for n in names if data[n]["src"] != "спрайт"]
    if not args.quiet:
        print(f"ресурсов с тайлами: {len(names)}, перерисовано: {len(names) - len(legacy)}, прежних: {len(legacy)}")
        print(f"пороги: ΔE далёк >= {COLOR_FAR} (12..20 — нужен shape >= {SHAPE_FAR}; <12 — shape >= {SHAPE_VERY_FAR}); контраст к грунту >= {MIN_CONTRAST}")
    for a, b, de, shape in sorted(flagged, key=lambda t: t[2] + t[3]):
        print(f"ПОХОЖИ  {a[4:]:<14} {b[4:]:<14} ΔE={de:5.1f}  shape={shape:4.2f}")
    for n, c in invisible:
        print(f"НЕВИДНА {n[4:]:<14} контраст к грунту {c:4.1f} < {MIN_CONTRAST}")
    if args.sheet:
        sheet(data, soils, args.sheet)
    if not flagged and not invisible:
        print("OK: похожих пар и невидимых ресурсов нет")
        return 0
    print(f"итого: похожих пар {len(flagged)}, невидимых {len(invisible)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
