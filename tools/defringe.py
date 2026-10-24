#!/usr/bin/env python3
"""defringe.py — снятие светлой каймы (остатка подложки) с краёв спрайта.

Откуда кайма. Авторские листы нарисованы на светлой/серой/небесной подложке
и сохранены в JPEG. Нарезка отделяет фон по порогу, и пиксели, где рисунок
смешан с подложкой (сглаживание художника, шум JPEG), остаются частью
рисунка. Уменьшение (import_art.shrink) усредняет их с тёмным контуром, а
подрезка резкости ещё и высветляет край — против чёрного цвета прозрачных
пикселей. В игре это белёсый ободок на земле, под землёй и на ночном небе.

Что делается (подложка `bg` известна — цвет края листа; без неё — только
шаги 2 и 4, и только перекраской):

  1. ОБДИРКА — только у цветной подложки (небо облаков и солнца): от
     прозрачности внутрь снимаются пиксели цвета подложки (не дальше
     `rings` слоёв); заливка идёт только по похожему на подложку, и тёмный
     контур её останавливает. Серую подложку от серебра, стали и бетона по
     цвету не отличить — там работает только шаг 2.
  2. КРОМКА — кольцами изнутри наружу. Для пикселя кольца k «свой цвет» F —
     среднее (с весом альфы) соседей глубже k, уже очищенных: у рисунка с
     контуром это цвет контура. Пиксель — кайма, если он светлее F на
     `d_lum` и при этом лежит на прямой «F → подложка» (смесь с подложкой)
     или почти белый у светлой подложки (пересвет подрезки резкости); без
     подложки — если не цветнее F. Кольцо глубже первого трогается, только
     если снаружи тоже светлое: светлая деталь за контуром — это рисунок.
     Цвет каймы становится F, альфа — долей рисунка в пикселе (C = t·F +
     (1−t)·подложка); `keep_alpha` — только перекраска, силуэт прежний.
  3. ОСТРОВКИ. Мелкие (до ISLAND_MAX пикселей) оторванные куски, почти
     целиком цвета подложки, — это не рисунок: снимаются. Так же — «шипы»:
     пиксели цвета подложки, держащиеся за край одним-двумя соседями.
  4. МУСОР. Полупрозрачные точки (альфа < 128) почти без соседей в окне 5×5.

По желанию (`outline`) кромка затемняется в ободок 1 px — как у программной
графики проекта.

Тонкое (ручка кирки, травинка, верёвка) не портится: у тонкой части нет
пикселей глубже кромки — её пиксель только перекрашивается в средний цвет
плотных соседей (альфа прежняя). Непрозрачное тонкое трогается лишь как
одиночная искра (не больше одного светлого соседа) и только у средне-серой
подложки: белая ручка платиновой кирки от светлой подложки неотличима, а
белое крыло стрекозы — несколько белых пикселей подряд.

Повторный прогон почти ничего не меняет: очищенная кромка уже цвета F.

Запуск:
  python3 tools/defringe.py --all             # реестр AUTHORED (на месте)
  python3 tools/defringe.py --all --dry-run   # только отчёт: было → стало
  python3 tools/defringe.py файл.png [...] [--bg R,G,B] [--rings N]
        [--keep-alpha] [--outline] [--out каталог]
  python3 tools/defringe.py --list            # реестр: файл, источник, параметры

Из Python (так его зовут импортёры):
  from defringe import defringe
  img = defringe(img, bg=(217, 217, 217))
"""

import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_fringe import (ALPHA_FLOOR, AUTHORED, CHROMA_SLACK, D_LUM,  # noqa: E402
                          ROOT, analyze, chroma, depth_map, lum)

# Подложки авторских листов (цвет края листа, см. art/_source/*).
BG_CHARACTERS = (217, 217, 217)   # characters_sheet.jpg — предметы import_art.py
BG_PICKAXES = (215, 215, 215)     # pickaxes_sheet.jpg
BG_GARDEN = (143, 143, 143)       # garden_assets_sheet.jpg
BG_HOUSE = (129, 134, 140)        # house_modern.jpg
BG_SHACK = (145, 145, 145)        # shack.jpg
BG_SKY = (146, 209, 240)          # sky_clouds_sun_moon_sheet.jpg — облака
BG_SUN = (167, 221, 240)          # там же, плашка солнца
BG_MOUNTAIN = (147, 206, 236)     # backdrop_mountain.jpg — небо над горой
BG_FENCE = (24, 76, 133)          # backdrop_fence_*.jpg — ночное небо над лесом

# Параметры по скрипту-источнику. Тёмные листы (бур, полёт, выезд
# бурмобиля) светлой подложки не имеют — светлая кайма там только от
# подрезки резкости, и она снимается перекраской (bg=None).
PARAMS = {
    "import_art.py": {"bg": BG_CHARACTERS},
    "import_pickaxes.py": {"bg": BG_PICKAXES},
    "import_garden.py": {"bg": BG_GARDEN},
    "import_house.py": {"bg": BG_HOUSE},
    "import_shack.py": {"bg": BG_SHACK},
    "import_rig_icon.py": {"bg": None},
    "rig_drill_recolor.py": {"bg": None},
    "import_rig_exit.py": {"bg": None},
    "(вырезан вручную из листа полёта)": {"bg": None},
}
FILE_PARAMS = {
    "art/env/sun.png": {"bg": BG_SUN, "rings": 3},
    # Фоны не чистятся (None): край у них растушёван нарочно
    # (import_backdrops.cut_sky), его подкрашивает шейдер неба, белой
    # обводки в игре нет (скриншоты неба 12:00/19:00/22:00). Замер у горы
    # ненулевой из-за снежных вершин — они светлые по рисунку.
    "art/env/backdrop_mountain.png": None,
    "art/env/backdrop_fence_old.png": None,
    "art/env/backdrop_fence_white.png": None,
}
CLOUD_PARAMS = {"bg": BG_SKY, "rings": 6}   # облака растянуты ×2.5 — кайма шире
# перистые облака (cloud_1) без контура и сами цвета неба: обдирка и
# островки съели бы их голубые пряди
FILE_PARAMS["art/env/clouds/cloud_1.png"] = {"bg": BG_SKY, "rings": 2, "peel": False, "islands": False}

PEEL_TOL = 40.0       # «цвет подложки» для обдирки: сумма |ΔR|+|ΔG|+|ΔB| ...
PEEL_SCALE = 1.3      # ... до подложки, пересвеченной не больше чем в 1.3 раза
BEYOND_TP = 1.15      # кайма «светлее подложки» (пересвет) ...
BEYOND_ALPHA = 200    # ... бывает только бледной
BLOWN_SCALE = 2.5     # пересвет светлой подложки вплоть до белого ...
BLOWN_TOL = 50.0      # ... с таким допуском
MIN_SEP = 40.0        # F и подложка ближе — разложить нельзя, только перекраска
LINE_TOL = 0.3        # допуск «на прямой F → подложка» (доля |F − подложка|)
LINE_TOL_MIN = 20.0
THIN_ALPHA = 160      # у тонкого кайма — только полупрозрачное (как в check_fringe)
ISLAND_MAX = 40       # островок — не больше стольких пикселей ...
ISLAND_BG = 0.6       # ... и не меньше такой доли цвета подложки
ISLAND_TOL = 60.0     # «цвет подложки» для островков (мягче, чем для обдирки)
SPECK_ALPHA = 128     # мусор — полупрозрачные точки ...
SPECK_NEIGHBOURS = 3  # ... почти без соседей в окне 5×5
OUTLINE_DARK = 0.45   # во сколько раз темнеет кромка при outline=True


def params_for(rel):
    """Параметры defringe() для файла реестра (подложка, глубина колец);
    None — файл в реестре, но не чистится (см. FILE_PARAMS)."""
    if rel in FILE_PARAMS:
        p = FILE_PARAMS[rel]
        return None if p is None else dict(p)
    if rel.startswith("art/env/clouds/"):
        return dict(CLOUD_PARAMS)
    return dict(PARAMS.get(AUTHORED.get(rel, ""), {}))


_N8 = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]


def _shift(a, dy, dx, fill):
    """a[y+dy, x+dx] с заполнением за краем."""
    h, w = a.shape[:2]
    out = np.full_like(a, fill)
    ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    out[yd, xd] = a[ys, xs]
    return out


def _box_count(m, r):
    p = np.pad(m.astype(np.int32), ((r + 1, r), (r + 1, r)))
    c = p.cumsum(0).cumsum(1)
    h, w = m.shape
    s = 2 * r + 1
    return c[s:s + h, s:s + w] - c[0:h, s:s + w] - c[s:s + h, 0:w] + c[0:h, 0:w]


def _bg_like(rgb, B, s_max, tol):
    """Похоже на подложку — саму или пересвеченную подрезкой резкости.

    Подрезка толкает край от чёрного (цвета прозрачных пикселей), то есть
    подложка B становится s·B со срезом на 255: светло-голубое небо — в
    бирюзово-белое (209,255,255), серое — в белое. Поэтому сравнение идёт
    с лучом clip(s·B), s ∈ [0.9, s_max], по сумме |ΔR|+|ΔG|+|ΔB|."""
    best = np.full(rgb.shape[:2], np.inf)
    for k in np.arange(0.9, s_max + 1e-6, 0.05):
        ref = np.clip(B * k, 0, 255)
        best = np.minimum(best, np.abs(rgb - ref[None, None, :]).sum(-1))
    return best <= tol


def _light(B):
    return float(lum(B[None, :])[0]) >= 150


def _peel(rgb, a, B, layers):
    """Шаг 1: снять от прозрачности слои цвета подложки.

    Снимается только ТОНКАЯ полоса: если похожее на подложку тянется вглубь
    дальше `layers` (голубая тень облака там, где контур прерван), рядом с
    этим ничего не снимается — иначе каждый следующий запуск откусывал бы
    тело облака ещё на `layers` пикселей."""
    bgl = _bg_like(rgb, B, PEEL_SCALE, PEEL_TOL)
    depth = depth_map(a >= ALPHA_FLOOR, layers + 1)
    guarded = _box_count(bgl & (depth > layers), layers) > 0
    near = bgl & ~guarded
    removed = np.zeros(a.shape, bool)
    for _ in range(layers):
        vis = a >= ALPHA_FLOOR
        hole = ~vis
        touch = np.zeros(a.shape, bool)
        for dy, dx in _N8:
            touch |= _shift(hole, dy, dx, False)
        take = vis & near & touch
        if not take.any():
            break
        a[take] = 0
        removed |= take
    return removed


def _islands(a, bgish):
    """Шаг 3: мелкие оторванные куски почти целиком цвета подложки.

    Обход в ширину с отсечкой: кусок, переросший ISLAND_MAX, помечается
    «большим» целиком по мере обхода — так картинка в миллион пикселей
    обходится один раз, а не по разу на каждый пиксель кромки."""
    h, w = a.shape
    vis = a >= ALPHA_FLOOR
    state = np.zeros((h, w), np.int8)   # 0 — не видели, 1 — большой, 2 — разобран
    out = np.zeros((h, w), bool)
    seeds = np.argwhere(vis & bgish)
    for y0, x0 in seeds:
        if state[y0, x0]:
            continue
        comp = [(y0, x0)]
        seen = {(y0, x0)}
        q = deque(comp)
        big = False
        while q and not big:
            y, x = q.popleft()
            for dy, dx in _N8:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and vis[ny, nx] and (ny, nx) not in seen:
                    if state[ny, nx] == 1:
                        big = True
                        break
                    seen.add((ny, nx))
                    comp.append((ny, nx))
                    q.append((ny, nx))
                    if len(comp) > ISLAND_MAX:
                        big = True
                        break
        ys, xs = np.array(comp).T
        if big:
            state[ys, xs] = 1
            continue
        state[ys, xs] = 2
        wgt = a[ys, xs]
        if (wgt * bgish[ys, xs]).sum() >= ISLAND_BG * wgt.sum():
            out[ys, xs] = True
    return out


def _one_pass(rgb, a, B, rings, d_lum, keep_alpha, peel, islands, specks):
    """Шаги 1-4 один раз; меняет rgb и a на месте, возвращает маску правок."""
    changed = np.zeros(a.shape, bool)
    # Обдирка — только для цветной подложки (небо): серую подложку от
    # серебра, стали и бетона по цвету не отличить, там решает кромка (шаг 2)
    if B is not None and not keep_alpha and peel and chroma(B[None, :])[0] >= 30:
        changed |= _peel(rgb, a, B, rings)

    vis = a >= ALPHA_FLOOR
    depth = depth_map(vis, rings + 1)
    for k in range(rings, 0, -1):
        ring = depth == k
        if not ring.any():
            continue
        L = lum(rgb)
        wsum = np.zeros(a.shape)
        csum = np.zeros(rgb.shape)
        tsum = np.zeros(a.shape)
        tcol = np.zeros(rgb.shape)
        for dy, dx in _N8:
            dn = _shift(depth, dy, dx, 0)
            an = _shift(a, dy, dx, 0.0)
            cn = _shift(rgb, dy, dx, 0.0)
            w = np.where(dn > k, an, 0.0)
            wsum += w
            csum += cn * w[..., None]
            # опора тонкого — ПЛОТНЫЕ соседи: цвет бледных пикселей после
            # уменьшения случаен, а самый тёмный сосед бывает выбросом
            wt = np.where((dn >= 1) & (an >= THIN_ALPHA), an, 0.0)
            tsum += wt
            tcol += cn * wt[..., None]
        has = wsum > 0
        F = np.where(has[..., None], csum / np.maximum(wsum, 1e-9)[..., None],
                     np.where((tsum > 0)[..., None], tcol / np.maximum(tsum, 1e-9)[..., None], rgb))
        LF = lum(F)
        cand = ring & ((L - LF) >= d_lum)
        t = np.ones(a.shape)
        if B is not None:
            v = B[None, None, :] - F
            s = np.sqrt((v * v).sum(-1))
            ok = s >= MIN_SEP
            tp = ((rgb - F) * v).sum(-1) / np.maximum(s * s, 1e-9)
            resid = np.sqrt((((rgb - F) - tp[..., None] * v) ** 2).sum(-1))
            on_line = ok & (tp >= 0.2) & (resid <= np.maximum(LINE_TOL_MIN, LINE_TOL * s))
            if _light(B):
                # «светлее самой светлой подложки» у плотного пикселя — это
                # светлый рисунок (серебро, белая краска): пересвет бледный
                on_line &= (tp <= BEYOND_TP) | (a < BEYOND_ALPHA)
            # серость сама по себе не признак: жёлтый блик на оранжевом
            # луче солнца тоже «серее» луча
            if _light(B):
                on_line |= _bg_like(rgb, B, BLOWN_SCALE, BLOWN_TOL) & (a < BEYOND_ALPHA)
            cand &= on_line
            t = np.where(ok, np.clip(1.0 - tp, 0.0, 1.0), 1.0)
        else:
            cand &= chroma(rgb) <= chroma(F) + CHROMA_SLACK
        # Тонкое (нет пикселей глубже) у светлой подложки трогаем только
        # полупрозрачное: там светлое плотное — сама ручка или серебро. У
        # средне-серой подложки белые искры на тонком — пересвет, их можно.
        # Белое крыло стрекозы — тоже тонкое, но белых в нём несколько
        # подряд; искра — одна-две среди тёмного.
        thin_ok = a < THIN_ALPHA
        if B is not None and not _light(B):
            lit = np.zeros(a.shape, np.int32)
            for dy, dx in _N8:
                lit += ((_shift(a, dy, dx, 0.0) >= ALPHA_FLOOR)
                        & (_shift(L, dy, dx, -np.inf) >= L - d_lum))
            thin_ok |= lit <= 1
        cand &= has | thin_ok
        t = np.where(has, t, 1.0)
        if k >= 2:
            outward = np.zeros(a.shape, bool)
            for dy, dx in _N8:
                outward |= ((_shift(depth, dy, dx, 0) == k - 1)
                            & (_shift(L, dy, dx, -np.inf) - LF >= d_lum))
            cand &= outward
        rgb[cand] = F[cand]
        if not keep_alpha:
            a[cand] = a[cand] * t[cand]
        changed |= cand

    a[a < ALPHA_FLOOR] = 0
    if B is not None and not keep_alpha and islands:
        bgish = _bg_like(rgb, B, BLOWN_SCALE if _light(B) else PEEL_SCALE, ISLAND_TOL)
        isl = _islands(a, bgish)
        a[isl] = 0
        changed |= isl
        # шипы: пиксель цвета подложки, торчащий из края на 1-2 соседях
        for _ in range(2):
            vis_now = a >= ALPHA_FLOOR
            spur = vis_now & bgish & (_box_count(vis_now, 1) - 1 <= 2)
            a[spur] = 0
            changed |= spur
    if specks:
        visible = a >= ALPHA_FLOOR
        lonely = visible & (a < SPECK_ALPHA) & (_box_count(visible, 2) <= SPECK_NEIGHBOURS)
        a[lonely] = 0
        changed |= lonely
    return changed


def defringe(img, bg=None, rings=2, d_lum=D_LUM, keep_alpha=False, outline=False,
             peel=True, islands=True, specks=True, passes=6, report=None):
    """Возвращает новый RGBA-образ без светлой каймы (см. шапку файла).

    bg — цвет подложки листа (R, G, B) или None; rings — сколько слоёв кромки
    проверять (1-2 для уменьшенных спрайтов, больше — для растянутых и
    растушёванных краёв); keep_alpha — только перекрашивать, силуэт не
    трогать; outline — затемнить кромку в ободок 1 px; peel / islands —
    шаги 1 и 3 (выключать там, где рисунок сам цвета подложки: перистые
    облака на небе); passes — предел повторов до неподвижной точки;
    report — словарь, куда сложить число изменённых пикселей.
    """
    src = img.convert("RGBA")
    arr = np.asarray(src).astype(np.float64)
    rgb = arr[..., :3].copy()
    a = arr[..., 3].copy()
    if (a >= ALPHA_FLOOR).all() or not (a >= ALPHA_FLOOR).any():
        if report is not None:
            report["changed"] = 0
        return src.copy()
    B = None if bg is None else np.array(bg, np.float64)
    changed = np.zeros(a.shape, bool)
    # Кайма бывает в несколько слоёв, и снятый слой открывает следующий:
    # проходы повторяются до неподвижной точки — тогда повторный запуск
    # инструмента по уже чищенному файлу ничего не меняет.
    for _ in range(passes):
        before_rgb, before_a = rgb.copy(), a.copy()
        _one_pass(rgb, a, B, rings, d_lum, keep_alpha, peel, islands, specks)
        rgb = np.clip(np.round(rgb), 0, 255)
        a = np.clip(np.round(a), 0, 255)
        moved = (np.abs(rgb - before_rgb).max(-1) > 0) | (a != before_a)
        changed |= moved
        if not moved.any():
            break
    if outline:
        edge = depth_map(a >= ALPHA_FLOOR, 1) == 1
        rgb[edge] *= OUTLINE_DARK
        changed |= edge

    out = np.dstack([np.clip(np.round(rgb), 0, 255), np.clip(np.round(a), 0, 255)]).astype(np.uint8)
    if report is not None:
        report["changed"] = int(changed.sum())
    return Image.fromarray(out, "RGBA")


def _parse_bg(s):
    if s is None or s.lower() == "none":
        return None
    parts = [int(p) for p in s.replace(" ", "").split(",")]
    if len(parts) != 3:
        raise SystemExit("--bg ждёт R,G,B")
    return tuple(parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--all", action="store_true", help="весь реестр AUTHORED (check_fringe.py)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--bg", help="подложка R,G,B или none (по умолчанию — из реестра)")
    ap.add_argument("--rings", type=int, help="глубина кромки (по умолчанию 2 или из реестра)")
    ap.add_argument("--d-lum", type=float, default=D_LUM)
    ap.add_argument("--keep-alpha", action="store_true", help="только перекрашивать")
    ap.add_argument("--outline", action="store_true", help="тёмный ободок 1 px")
    ap.add_argument("--no-specks", action="store_true", help="не снимать полупрозрачный мусор")
    ap.add_argument("--out", help="писать сюда (те же относительные пути), а не на место")
    ap.add_argument("--root", help="читать файлы из копии репозитория (пути и реестр — те же)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.list:
        for rel, script in AUTHORED.items():
            p = params_for(rel)
            print(f"{rel:48s} {script:34s} {'не чистится' if p is None else p}")
        return
    files = list(AUTHORED) if args.all else args.files
    if not files:
        ap.error("укажи файлы или --all")
    base = os.path.abspath(args.root) if args.root else ROOT
    for f in files:
        path = f if os.path.isabs(f) else os.path.join(base, f)
        if not os.path.exists(path):
            path = os.path.abspath(f)
        if not os.path.exists(path):
            print(f"{f}: нет файла")
            continue
        rel = os.path.relpath(path, base)
        p = params_for(rel)
        if p is None:
            if args.files:
                p = {}
            else:
                print(f"{rel:48s} не чистится (см. FILE_PARAMS)")
                continue
        if args.bg is not None:
            p["bg"] = _parse_bg(args.bg)
        if args.rings is not None:
            p["rings"] = args.rings
        if args.keep_alpha:
            p["keep_alpha"] = True
        img = Image.open(path)
        before = analyze(np.asarray(img.convert("RGBA")))
        rep = {}
        out = defringe(img, d_lum=args.d_lum, outline=args.outline,
                       specks=not args.no_specks, report=rep, **p)
        after = analyze(np.asarray(out))
        print(f"{rel:48s} кайма {before['frac'] * 100:5.1f}% → {after['frac'] * 100:5.1f}%  "
              f"пикселей изменено: {rep['changed']}")
        if args.dry_run or not (rep["changed"] or args.out):
            continue
        dst = os.path.join(args.out, rel) if args.out else path
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        out.save(dst)


if __name__ == "__main__":
    main()
