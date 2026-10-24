#!/usr/bin/env python3
"""check_fringe.py — замер светлой каймы у авторской графики.

Авторские листы (art/_source/*.jpg|png) нарисованы на светлой или серой
подложке. Нарезка отделяет фон по порогу, и пиксели, где рисунок смешан с
подложкой (сглаживание художника, JPEG-шум), остаются по краю силуэта как
часть рисунка — на тёмной земле и на небе это видно как белёсая обводка.

Метрика: «кромка» — видимые пиксели, соседствующие (8-связно) с прозрачными;
«тело» — пиксели не ближе CORE_DEPTH к прозрачности. Пиксель кромки считается
каймой, если он заметно светлее тела рядом (среднее тела в окне радиуса
RADIUS) и при этом не цветнее его: подложка у всех листов серая или
серо-голубая, а светлое по природе (белая стена, облако, лепесток) светлое
и внутри — с телом рядом у него разницы нет. Тонкие части без тела (ручка
кирки, травинка) сравниваются с самым тёмным видимым соседом: у чистого
рисунка контур тёмный, у грязного кромка светлее собственного контура.

Доля каймы = сумма альф пикселей-каймы / сумма альф кромки (полупрозрачный
светлый пиксель — меньше заметен, но заметен).

Запуск:
  python3 tools/check_fringe.py                 # отчёт по реестру AUTHORED
  python3 tools/check_fringe.py --hero          # то же для art/character/**
  python3 tools/check_fringe.py art/x.png ...   # отчёт по своим файлам
  python3 tools/check_fringe.py --sheet out.png [файлы] # контрольный лист:
        файл на тёмном, на небе, на земле и с подсвеченной каймой (×3)
  python3 tools/check_fringe.py --before DIR --sheet out.png  # «было/стало»:
        DIR — копия art/ до чистки (пути внутри те же, что в art/)
"""

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Авторская графика вне art/character/** — что режется из листов владельца.
# Скрипт-источник указан для справки (и для tools/defringe.py --list).
AUTHORED = {
    "art/items/pickaxe_rusty.png": "import_pickaxes.py",
    "art/items/pickaxe_rusty_cracked.png": "import_pickaxes.py",
    "art/items/pickaxe_iron.png": "import_pickaxes.py",
    "art/items/pickaxe_titanium.png": "import_pickaxes.py",
    "art/items/pickaxe_platinum.png": "import_pickaxes.py",
    "art/items/pickaxe_diamond.png": "import_pickaxes.py",
    "art/items/pickaxe_obsidian.png": "import_pickaxes.py",
    "art/items/shovel.png": "import_art.py",
    "art/items/backpack_propeller.png": "import_art.py",
    "art/items/jetpack.png": "import_art.py",
    "art/items/hand_drill.png": "import_art.py",
    "art/items/backpack_plus.png": "(вырезан вручную из листа полёта)",
    "art/items/jetpack_top.png": "(вырезан вручную из листа полёта)",
    "art/items/drill_rig_icon.png": "import_rig_icon.py",
    "art/items/drill_rig_icon_titanium.png": "rig_drill_recolor.py",
    "art/items/drill_rig_icon_platinum.png": "rig_drill_recolor.py",
    "art/items/drill_rig_icon_diamond.png": "rig_drill_recolor.py",
    "art/items/drill_rig_icon_obsidian.png": "rig_drill_recolor.py",
    "art/ui/icon_inventory.png": "import_art.py",
    "art/ui/icon_dollar.png": "import_art.py",
    "art/env/workbench.png": "import_art.py",
    "art/env/bed.png": "import_art.py",
    "art/env/drill_mobile.png": "import_art.py",
    "art/env/drill_mobile_parked.png": "import_rig_exit.py",
    "art/env/house_rich.png": "import_house.py",
    "art/env/shack.png": "import_shack.py",
    "art/env/sun.png": "import_clouds.py",
    "art/env/backdrop_fence_old.png": "import_backdrops.py",
    "art/env/backdrop_fence_white.png": "import_backdrops.py",
    "art/env/backdrop_mountain.png": "import_backdrops.py",
}
for _p in sorted(glob.glob(os.path.join(ROOT, "art/env/clouds/cloud_*.png"))):
    AUTHORED[os.path.relpath(_p, ROOT)] = "import_clouds.py"
for _p in sorted(glob.glob(os.path.join(ROOT, "art/env/garden/*.png"))):
    AUTHORED[os.path.relpath(_p, ROOT)] = "import_garden.py"

ALPHA_FLOOR = 8     # ниже — шум ресемплинга, не рисунок (как в import_art.py)
CORE_DEPTH = 3      # «тело» — не ближе трёх пикселей к прозрачности
RADIUS = 4          # окно, в котором ищется тело рядом с пикселем кромки
D_LUM = 28          # насколько кромка светлее тела, чтобы считаться каймой
CHROMA_SLACK = 12   # кайма не цветнее тела больше чем на столько
THIN_ALPHA = 160    # у тонкого каймой считается только то, что прозрачнее
# Доля каймы, выше которой файл считается грязным. Чистый рисунок с тёмным
# контуром даёт 0-3 % (блики на кромке), грязный — от 15 % и выше.
FRINGE_MAX = 0.06

BG_DARK = (28, 24, 32)
BG_SKY = (124, 186, 232)
GROUND_TILE = "art/tiles/dirt_1.png"


def _dilate(m):
    """8-связное расширение булевой маски на 1 px (край — повтор края)."""
    p = np.pad(m, 1, mode="edge")
    out = np.zeros_like(m)
    h, w = m.shape
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            out |= p[dy:dy + h, dx:dx + w]
    return out


def depth_map(vis, limit=CORE_DEPTH):
    """Расстояние (шагов 8-связности) от видимого пикселя до прозрачности,
    обрезанное на limit. Прозрачные — 0. За краем картинки — то же, что на
    краю: спрайт, упёршийся в рамку, не получает там ложной кромки."""
    d = np.zeros(vis.shape, np.int32)
    hole = ~vis
    for k in range(1, limit + 1):
        grown = _dilate(hole)
        ring = vis & grown & (d == 0)
        d[ring] = k
        hole = grown
    d[vis & (d == 0)] = limit + 1
    return d


def _box_sum(a, r):
    """Сумма по окну (2r+1)² через интегральное изображение."""
    p = np.pad(a, ((r + 1, r), (r + 1, r)) + ((0, 0),) * (a.ndim - 2))
    c = p.cumsum(0).cumsum(1)
    h, w = a.shape[:2]
    s = (r * 2 + 1)
    return c[s:s + h, s:s + w] - c[0:h, s:s + w] - c[s:s + h, 0:w] + c[0:h, 0:w]


def _min_filter(a, r, mask):
    """Минимум a по окну среди пикселей mask (иначе +inf)."""
    big = np.where(mask, a, np.inf)
    p = np.pad(big, r, mode="constant", constant_values=np.inf)
    h, w = a.shape
    out = np.full(a.shape, np.inf)
    for dy in range(2 * r + 1):
        for dx in range(2 * r + 1):
            out = np.minimum(out, p[dy:dy + h, dx:dx + w])
    return out


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def chroma(rgb):
    return rgb.max(-1) - rgb.min(-1)


def analyze(arr, d_lum=D_LUM, radius=RADIUS):
    """Разбор RGBA-массива. Возвращает словарь с маской каймы и долями."""
    rgb = arr[..., :3].astype(np.float64)
    a = arr[..., 3].astype(np.float64)
    vis = a >= ALPHA_FLOOR
    depth = depth_map(vis)
    edge = depth == 1
    L = lum(rgb)
    C = chroma(rgb)

    core = (depth >= CORE_DEPTH) & (a >= 250)
    n = _box_sum(core.astype(np.float64), radius)
    with np.errstate(invalid="ignore", divide="ignore"):
        ref_l = _box_sum(np.where(core, L, 0.0), radius) / n
        ref_c = _box_sum(np.where(core, C, 0.0), radius) / n
    # Тонкое без тела рядом (ручка кирки, травинка): опора — самый тёмный
    # ПЛОТНЫЙ сосед, а каймой считается только полупрозрачное — у тонкого
    # светлая сторона бывает просто светом на рисунке.
    thin = n < 1
    if thin.any():
        dense = vis & (a >= THIN_ALPHA)
        fb = _min_filter(L, 1, dense)
        inner = _min_filter(L, 2, vis & (depth >= 2))
        fb = np.where(np.isfinite(fb), fb, np.where(np.isfinite(inner), inner, L))
        ref_l = np.where(thin, fb, ref_l)
        ref_c = np.where(thin, 255.0, ref_c)
    fringe = edge & (L - ref_l >= d_lum) & (C <= ref_c + CHROMA_SLACK) & (~thin | (a < THIN_ALPHA))
    w = a / 255.0
    edge_w = float((w * edge).sum())
    fr_w = float((w * fringe).sum())
    ring2 = depth == 2
    fr2 = ring2 & (L - ref_l >= d_lum) & (C <= ref_c + CHROMA_SLACK) & ~thin
    r2_w = float((w * ring2).sum())
    return {
        "edge_px": int(edge.sum()),
        "fringe_px": int(fringe.sum()),
        "frac": fr_w / edge_w if edge_w > 0 else 0.0,
        "frac2": float((w * fr2).sum()) / r2_w if r2_w > 0 else 0.0,
        "fringe": fringe,
        "has_alpha": bool((a < 255).any()),
    }


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"))


def measure(path):
    return analyze(load(path))


# ---------------------------------------------------------------------------
# Контрольный лист
# ---------------------------------------------------------------------------

def _font(size=12):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _ground(size):
    tile = Image.open(os.path.join(ROOT, GROUND_TILE)).convert("RGBA")
    out = Image.new("RGBA", size)
    for y in range(0, size[1], tile.height):
        for x in range(0, size[0], tile.width):
            out.paste(tile, (x, y))
    return out


def crop_window(arr, scale, max_w):
    """Окно для крупной картинки: кромку смотрят вблизи (вписывание целиком
    её бы размыло), поэтому берётся квадрат max_w/scale там, где больше всего
    каймы, а без неё — где больше всего кромки. None — картинка влезает."""
    h, w = arr.shape[:2]
    side = max(8, max_w // scale)
    if w <= side and h <= side:
        return None
    cw, ch = min(w, side), min(h, side)
    res = analyze(arr)
    target = res["fringe"] if res["fringe"].any() else (depth_map(arr[..., 3] >= ALPHA_FLOOR, 1) == 1)
    c = np.pad(target.astype(np.float64), ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    sums = c[ch:, cw:] - c[:-ch, cw:] - c[ch:, :-cw] + c[:-ch, :-cw]
    y0, x0 = np.unravel_index(int(np.argmax(sums)), sums.shape)
    return (int(x0), int(y0), int(x0) + cw, int(y0) + ch)


def _scaled(im, scale, box):
    if box:
        im = im.crop(box)
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def _panel(im, bg, scale, box):
    big = _scaled(im, scale, box)
    if bg == "ground":
        base = _ground(big.size)
    else:
        base = Image.new("RGBA", big.size, bg + (255,))
    base.alpha_composite(big)
    return base


def _marked(im, fringe, scale, box):
    arr = np.asarray(im).copy()
    arr[fringe] = (255, 0, 255, 255)
    return _panel(Image.fromarray(arr, "RGBA"), BG_DARK, scale, box)


def contact_sheet(rows, out, scale=3, max_w=300):
    """rows: [(подпись, [картинка панели, ...])] — панели одной строки."""
    font = _font(12)
    pad = 8
    lab = 16
    built = []
    for title, panels in rows:
        h = max(p.height for p in panels)
        w = sum(p.width for p in panels) + pad * (len(panels) - 1)
        built.append((title, panels, w, h))
    W = max(w for _, _, w, _ in built) + pad * 2
    H = sum(h + lab + pad for *_, h in built) + pad
    sheet = Image.new("RGBA", (W, H), (52, 52, 58, 255))
    d = ImageDraw.Draw(sheet)
    y = pad
    for title, panels, w, h in built:
        d.text((pad, y), title, fill=(240, 220, 120, 255), font=font)
        x = pad
        for p in panels:
            sheet.alpha_composite(p, (x, y + lab))
            x += p.width + pad
        y += h + lab + pad
    sheet.convert("RGB").save(out)
    return sheet.size


def sheet_rows(paths, before_dir=None, scale=3, max_w=300, after_dir=ROOT):
    rows = []
    for rel in paths:
        after = Image.open(os.path.join(after_dir, rel)).convert("RGBA")
        res_a = analyze(np.asarray(after))
        if before_dir:
            src = os.path.join(before_dir, rel)
            if not os.path.exists(src):
                continue
            before = Image.open(src).convert("RGBA")
            if before.size != after.size:
                continue
            res_b = analyze(np.asarray(before))
            box = crop_window(np.asarray(before), scale, max_w)
            title = (f"{rel}   кайма было {res_b['frac'] * 100:.0f}% → стало "
                     f"{res_a['frac'] * 100:.0f}%   (пары было|стало: тёмный, небо, земля)")
            panels = []
            for bg in (BG_DARK, BG_SKY, "ground"):
                panels.append(_panel(before, bg, scale, box))
                panels.append(_panel(after, bg, scale, box))
        else:
            box = crop_window(np.asarray(after), scale, max_w)
            title = f"{rel}   кайма {res_a['frac'] * 100:.1f}%   (тёмный | небо | земля | кайма)"
            panels = [_panel(after, BG_DARK, scale, box),
                      _panel(after, BG_SKY, scale, box),
                      _panel(after, "ground", scale, box),
                      _marked(after, res_a["fringe"], scale, box)]
        rows.append((title, panels))
    return rows


def hero_files():
    return sorted(os.path.relpath(p, ROOT) for p in
                  glob.glob(os.path.join(ROOT, "art/character/**/*.png"), recursive=True))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--hero", action="store_true", help="art/character/** (зона героя)")
    ap.add_argument("--sheet", help="записать контрольный лист в этот PNG")
    ap.add_argument("--sheet-dir", help="листы по группам реестра (предметы, дом, огород, небо) в каталог")
    ap.add_argument("--before", help="каталог-копия ДО чистки (для листа «было/стало»)")
    ap.add_argument("--after", default=ROOT, help="откуда брать «стало» (по умолчанию — репозиторий)")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--max-w", type=int, default=300)
    ap.add_argument("--strict", action="store_true", help="код 1, если есть файл с каймой")
    args = ap.parse_args()

    files = args.files or (hero_files() if args.hero else list(AUTHORED))
    files = [os.path.relpath(os.path.abspath(f), ROOT) if os.path.exists(f) else f for f in files]
    bad = []
    print(f"{'файл':52s} {'кромка':>7s} {'кайма':>6s} {'доля':>6s} {'2-й ряд':>7s}")
    for rel in files:
        res = measure(os.path.join(args.after, rel))
        flag = res["frac"] > FRINGE_MAX
        if flag:
            bad.append(rel)
        if not res["has_alpha"]:
            print(f"{rel:52s}   (непрозрачный — края нет)")
            continue
        print(f"{rel:52s} {res['edge_px']:7d} {res['fringe_px']:6d} "
              f"{res['frac'] * 100:5.1f}% {res['frac2'] * 100:6.1f}%  {'КАЙМА' if flag else 'ok'}")
    print(f"с каймой (доля > {FRINGE_MAX * 100:.0f}%): {len(bad)} из {len(files)}")

    if args.sheet:
        rows = sheet_rows(files, args.before, args.scale, args.max_w, args.after)
        print("лист:", args.sheet, contact_sheet(rows, args.sheet))
    if args.sheet_dir:
        os.makedirs(args.sheet_dir, exist_ok=True)
        groups = {"items": ("art/items/", "art/ui/"), "env": ("art/env/",),
                  "garden": ("art/env/garden/",), "sky": ("art/env/clouds/", "art/env/sun")}
        for g, prefixes in groups.items():
            part = [f for f in files if f.startswith(prefixes)
                    and (g != "env" or f.count("/") == 2 and "sun" not in f)]
            if not part:
                continue
            out = os.path.join(args.sheet_dir, f"{'ba' if args.before else 'fringe'}_{g}.png")
            rows = sheet_rows(part, args.before, args.scale, args.max_w, args.after)
            print("лист:", out, contact_sheet(rows, out))
    if args.strict and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
