#!/usr/bin/env python3
"""rig_drill_recolor.py — перекраска бура бурмобиля под металл кирок.

Задача владельца: «в магазине появляется апгрейд бурмобиля — титановый /
платиновый / алмазный / обсидиановый бур, каждый на 20% быстрее предыдущего.
Вид бура один и тот же, цвета такие же как у кирок». Само число скорости
считает scripts/core/balance.gd (см. get_tool_speed_multiplier). Этот файл —
только про цвет: он тонирует один и тот же бур (форма не меняется) под
четыре металла, которыми уже нарисованы pickaxe_titanium/platinum/diamond/
obsidian.png, чтобы игрок узнавал апгрейд по тому же цвету, что и у кирки той
же ступени.

Источник — уже нарезанные листы бурмобиля (art/character/dig_rig_down.png,
dig_rig_side.png, rig_jump.png, art/items/drill_rig_icon.png), не сырой
art/_source/drill_sheet.jpg: перекраска работает ПОВЕРХ готовой нарезки
tools/import_drill.py/import_rig_jump_fly.py/import_rig_icon.py, а не вместо
неё, — трогать три разных импортёра втроём было бы риском конфликта с
агентами, которые их же правят параллельно (см. их докстринги). rig_fly.png
не трогается вовсе: бур на нём не виден ни в одном кадре (турбина скрывает
корпус целиком), перекрашивать там нечего.

ГЕОМЕТРИЯ МАСКИ «ЭТО БУР». У каждого из трёх листов бур — единственная
стальная деталь СВОЕЙ формы и СВОЕГО места в кадре (клиновидный винт спереди-
снизу машины на dig_rig_side.png/rig_jump.png, свисающий винт под гусеницами
на dig_rig_down.png), но гусеницы, ступицы колёс и стойка-перископ в кабине
тоже серые — цветом одним их не различить. Поэтому маска на каждом листе
своя, подобранная по РАСПОЛОЖЕНИЮ (см. _side_drill_mask/_jump_drill_mask/
_down_drill_mask ниже — там же почему для каждого листа выбран свой приём):
  * dig_rig_side.png — бур везде на одном месте (лист крутится по кругу,
    станок уже бурит), поэтому фиксированный прямоугольник справа от корпуса
    минус прямоугольники колёс и купола хватает без исключений;
  * rig_jump.png — бур втягивается по кадрам (0..7), поэтому фиксированный
    прямоугольник не годится: он ловил бы то пусто, то лишнее. Кадр 7 —
    полностью закрытая машина, бура на нём нет вовсе, и «что серое на кадре 7»
    (колёса, стойка) вычитается из каждого кадра как маска «это не бур»;
  * dig_rig_down.png — камера уезжает крупнее по мере бурения (машина растёт
    в кадре), фиксированный прямоугольник или маска соседнего кадра для этого
    листа не годятся. Вместо этого на каждом кадре отдельно ищется строка, на
    которой силуэт машины резко сужается (гусеницы кончились — начался винт),
    и всё ниже неё — кандидат в бур.
Маска — приближение, не пиксель-в-пиксель идеальная сегментация (см. отчёт
агента): на кадрах остаются единичные перекрашенные пиксели осыпающейся
породы рядом с буром. Это мелкий и рассеянный шум, а не сплошная лишняя
фигура, и он не отличим на глаз от самого бура на телефонном экране.

ЦВЕТ. Насколько бур того или иного тира красится — решают TIERS ниже: пара
(H, S) в HSV, снятая с ГОЛОВКИ (не рукояти) соответствующей кирки —
см. _pickaxe_metal_hsv, который взвешивает оттенок по насыщенности пикселя
(нейтрально-серые пиксели рукояти и бликов почти не голосуют за оттенок,
цветное стекло/металл голосует полностью) и отдельно отбрасывает
коричнево-деревянные оттенки рукояти по Hue (0..70°, 345..360°) — так кирки
с некрашеной серой рукоятью (платина) и с цветной головкой (алмаз, гранёные
самоцветы) дают один и тот же осмысленный «металл кирки», не смешанный с
деревом. Сама перекраска (_recolor_pixels) держит ЯРКОСТЬ (V) пикселя как
есть — так остаются тени и блики винта, металл не становится плоской
заливкой, — и меняет только оттенок (на целевой H) и насыщенность (целевая S,
промодулированная по яркости: в тенях металл цветнее, на бликах — ближе к
белому, как и у настоящего металла). Работает как HSV-аналог Lab: V здесь —
почти то же, что светлота L в Lab, а H/S — то же, что цвет a/b, и это тот же
приём, каким tools/import_pickaxes.py и import_art.tone_match держат тон
листов, не превращая существующее освещение в плоскую заливку.

Запуск:  python3 tools/rig_drill_recolor.py
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_DIR = os.path.join(ROOT, "art", "character")
ITEMS_DIR = os.path.join(ROOT, "art", "items")

FRAME_W, FRAME_H, FRAMES = 240, 168, 8

# ---------------------------------------------------------------------------
# Целевые металлы: (H в градусах, S, V) — сняты с головок кирок, см.
# докстринг. V здесь не «цвет пикселя», а общая светлота головки: у
# обсидиановой кирки она заметно ниже остальных (камень тёмный сам по себе,
# не только по оттенку), и без этого числа обсидиановый бур вышел бы просто
# синевато-серым тем же по светлоте, что и остальные три тира, — то есть не
# читался бы как обсидиан. См. _recolor_pixels: V каждого пикселя МАСШТАБИРУЕТСЯ
# к этому числу (не заменяется на него), поэтому тени и блики самого бура
# остаются на месте, просто вся шкала светлот сдвигается туда же, куда её
# сдвинул художник у кирки.
#
# Обсидиановый бур — не нулевой тир (см. GameState.drill_rig_tier: 0 значит
# "апгрейда ещё нет", а не "обсидиан"): 0=базовый серый бур без перекраски,
# 1..4 — титан/платина/алмаз/обсидиан по порядку покупки.
# ---------------------------------------------------------------------------
TIERS = [
    ("titanium", 278.0, 0.107, 0.579),
    ("platinum", 221.8, 0.126, 0.667),
    ("diamond", 195.3, 0.438, 0.631),
    ("obsidian", 252.5, 0.152, 0.285),
]

# Опорная светлота бура ДО перекраски (среднее V маски бура на dig_rig_side,
# кадр 0, см. отчёт агента) — знаменатель масштаба V в _recolor_pixels.
DRILL_BASE_V = 0.4976


# ---------------------------------------------------------------------------
# Цвет металла кирки той же ступени
# ---------------------------------------------------------------------------

def _rgb_to_hsv_np(arr):
    """RGB (…,3) 0..255 -> HSV (…,3), H в 0..1, векторно через numpy."""
    rgb = arr.astype(np.float64) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, axis=-1)
    mn = np.min(rgb, axis=-1)
    diff = mx - mn
    with np.errstate(divide="ignore", invalid="ignore"):
        s = np.where(mx > 0, diff / np.where(mx == 0, 1, mx), 0.0)
        rc = np.where(diff == 0, 0.0, (mx - r) / np.where(diff == 0, 1, diff))
        gc = np.where(diff == 0, 0.0, (mx - g) / np.where(diff == 0, 1, diff))
        bc = np.where(diff == 0, 0.0, (mx - b) / np.where(diff == 0, 1, diff))
    h = np.zeros_like(mx)
    is_r = (mx == r) & (diff > 0)
    is_g = (mx == g) & (diff > 0) & ~is_r
    is_b = (mx == b) & (diff > 0) & ~is_r & ~is_g
    h = np.where(is_r, bc - gc, h)
    h = np.where(is_g, 2.0 + rc - bc, h)
    h = np.where(is_b, 4.0 + gc - rc, h)
    h = (h / 6.0) % 1.0
    return h, s, mx


def _hsv_to_rgb_np(h, s, v):
    """HSV (H в 0..1) -> RGB 0..255, векторно."""
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p = v * (1.0 - s)
    q = v * (1.0 - f * s)
    t = v * (1.0 - (1.0 - f) * s)
    i_mod = i.astype(int) % 6
    conds = [i_mod == k for k in range(6)]
    choices_r = [v, q, p, p, t, v]
    choices_g = [t, v, v, q, p, p]
    choices_b = [p, p, t, v, v, q]
    r = np.select(conds, choices_r)
    g = np.select(conds, choices_g)
    b = np.select(conds, choices_b)
    out = np.stack([r, g, b], axis=-1) * 255.0
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


# Рукоять/дерево — эти оттенки безусловно исключаются из усреднения цвета
# головки, независимо от насыщенности (см. докстринг: платиновая рукоять
# почти белая, обсидиановая — почти чёрная, и по насыщенности их не отсеять).
_WOOD_HUE_LO, _WOOD_HUE_HI = 70.0 / 360.0, 345.0 / 360.0


def _pickaxe_metal_hsv(path):
    """Оттенок и насыщенность «металла» кирки — головка без рукояти.

    Взвешивает Hue по насыщенности (circular mean с весом S): нейтрально-
    серые пиксели (блик, стальная оправа) почти не двигают итоговый оттенок,
    цветные (самоцветы, окрашенный металл) — определяют его почти целиком.
    Без этого веса ржавая примесь на границе рукояти/головки и случайный шум
    сдвигают средний оттенок на произвольные десятки градусов (см. отчёт
    агента: невзвешенное среднее уводило титан в розовый, а не в его
    настоящий лавандово-серый).

    Насыщенность — тем же приёмом взвешена сама на себя (Σs²/Σs, а не Σs/n):
    простое среднее тонет в стальных бликах и почти белых рёбрах кадра
    (у них s≈0, а их всегда большинство пикселей), и титановая/платиновая
    кирка выходили бы у бура даже незаметнее, чем нарисованы художником.
    Взвешенное среднее — это насыщенность ЦВЕТНОЙ части головки (там, где
    металл вообще имеет оттенок), она же то, что глаз и считывает как «цвет
    кирки»; на серых бликах бур всё равно останется собственным бликом
    (яркость V перекраска не трогает, см. _recolor_pixels).
    """
    im = Image.open(path).convert("RGBA")
    arr = np.array(im)
    a = arr[..., 3]
    h, s, v = _rgb_to_hsv_np(arr[..., :3])
    keep = (a > 10) & ~((h <= _WOOD_HUE_LO) | (h >= _WOOD_HUE_HI))
    h_k, s_k, v_k = h[keep], s[keep], v[keep]
    sin_sum = float(np.sum(s_k * np.sin(h_k * 2 * np.pi)))
    cos_sum = float(np.sum(s_k * np.cos(h_k * 2 * np.pi)))
    mean_h = (np.arctan2(sin_sum, cos_sum) / (2 * np.pi)) % 1.0
    s_sum = float(np.sum(s_k))
    mean_s = float(np.sum(s_k * s_k) / s_sum) if s_sum > 1e-9 else 0.0
    mean_v = float(np.mean(v_k)) if v_k.size else 0.5
    return mean_h * 360.0, mean_s, mean_v


# ---------------------------------------------------------------------------
# Маска «это бур» — ахроматичный металл в нужной области кадра
# ---------------------------------------------------------------------------

def _achromatic(arr, diff_thresh=22, lum_min=45, lum_max=250, alpha_min=10):
    """True там, где пиксель — нейтральный металл (не синий корпус, не кожа,
    не дерево, не чёрная обводка/тень). См. докстринг файла."""
    r = arr[..., 0].astype(int)
    g = arr[..., 1].astype(int)
    b = arr[..., 2].astype(int)
    a = arr[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    diff = mx - mn
    lum = (r + g + b) / 3.0
    return (a > alpha_min) & (diff <= diff_thresh) & (lum >= lum_min) & (lum <= lum_max)


def _rect(shape, x0, x1, y0, y1):
    m = np.zeros(shape, dtype=bool)
    m[y0:y1, x0:x1] = True
    return m


def _side_drill_mask(frame):
    """dig_rig_side.png — бур всегда в одном месте (см. докстринг файла)."""
    ach = _achromatic(frame)
    wheels = _rect(ach.shape, 25, 170, 108, 148)
    cabin = _rect(ach.shape, 0, 150, 0, 78)
    zone = _rect(ach.shape, 140, FRAME_W, 55, 150)
    return ach & zone & ~wheels & ~cabin


def _jump_exclude_from_closed(closed_frame):
    """«Не бур» для rig_jump.png: всё серое на закрытом кадре 7 (колёса,
    стойка-перископ) — эти детали неподвижны между кадрами одного листа
    (см. докстринг файла), поэтому вычитание годится для любого кадра."""
    from scipy import ndimage
    return ndimage.binary_dilation(_achromatic(closed_frame), iterations=2)


def _jump_drill_mask(frame, exclude):
    ach = _achromatic(frame)
    cabin = _rect(ach.shape, 0, 165, 0, 76)
    zone = _rect(ach.shape, 90, FRAME_W, 50, 160)
    return ach & zone & ~cabin & ~exclude


def _down_boundary_y(alpha, y_search_start=60):
    """Строка кадра dig_rig_down.png, где силуэт резко сужается — гусеницы
    кончились, начался винт (см. докстринг файла: камера меняет масштаб по
    кадрам, поэтому границу ищем заново на каждом кадре, а не одним числом)."""
    h = alpha.shape[0]
    widths = alpha.sum(axis=1)
    tail = widths[y_search_start:]
    if tail.size == 0 or tail.max() == 0:
        return h
    max_w = tail.max()
    threshold = max_w * 0.55
    peak_y = y_search_start + int(np.argmax(tail))
    for y in range(peak_y, h):
        if widths[y] < threshold:
            look = widths[y:y + 6]
            if look.size == 0 or look.max() < threshold * 1.3:
                return y
    return h


def _down_drill_mask(frame):
    alpha = frame[..., 3] > 10
    boundary = _down_boundary_y(alpha)
    ach = _achromatic(frame)
    ach[:boundary, :] = False
    return ach


def _icon_drill_mask(arr):
    ach = _achromatic(arr)
    zone = _rect(ach.shape, 19, 32, 13, 29)
    return ach & zone


# ---------------------------------------------------------------------------
# Перекраска: держим V (яркость/блик), меняем H и S на целевой металл
# ---------------------------------------------------------------------------

def _recolor_pixels(arr, mask, target_h_deg, target_s, target_v=None):
    """Красит пиксели под маской в целевой металл.

    Насыщенность целевого металла модулируется по собственной яркости
    пикселя (тени чуть цветнее, блики — ближе к белому): то же самое
    поведение, какое даёт настоящий крашеный металл, а не плоская заливка.

    target_v (если задан) — не замена яркости, а её МАСШТАБ: каждый пиксель
    умножается на target_v/DRILL_BASE_V, так что тени и блики самого бура
    остаются на месте (см. докстринг TIERS про обсидиан — без этого он не
    отличался бы по светлоте от остальных тиров).
    """
    out = arr.copy()
    if not np.any(mask):
        return out
    region = arr[mask][..., :3]
    _, _, v = _rgb_to_hsv_np(region.reshape(1, -1, 3))
    v = v.reshape(-1)
    target_h = (target_h_deg / 360.0) % 1.0
    sat_curve = np.clip(1.25 - v, 0.45, 1.35)
    new_s = np.clip(target_s * sat_curve, 0.0, 1.0)
    new_h = np.full_like(v, target_h)
    new_v = v
    if target_v is not None:
        v_scale = np.clip(target_v / DRILL_BASE_V, 0.5, 1.4)
        new_v = np.clip(v * v_scale, 0.03, 1.0)
    new_rgb = _hsv_to_rgb_np(new_h, new_s, new_v)
    out_rgb = out[..., :3]
    out_rgb[mask] = new_rgb
    return out


# ---------------------------------------------------------------------------
# Листы целиком
# ---------------------------------------------------------------------------

def _recolor_side_or_down(src_path, out_path, target_h, target_s, target_v, mask_fn):
    im = Image.open(src_path).convert("RGBA")
    sheet = np.array(im)
    out = sheet.copy()
    for i in range(FRAMES):
        x0 = i * FRAME_W
        frame = sheet[:, x0:x0 + FRAME_W]
        mask = mask_fn(frame)
        out[:, x0:x0 + FRAME_W] = _recolor_pixels(frame, mask, target_h, target_s, target_v)
    Image.fromarray(out).save(out_path)


def _recolor_jump(src_path, out_path, target_h, target_s, target_v):
    im = Image.open(src_path).convert("RGBA")
    sheet = np.array(im)
    closed = sheet[:, 7 * FRAME_W:8 * FRAME_W]
    exclude = _jump_exclude_from_closed(closed)
    out = sheet.copy()
    for i in range(FRAMES):
        x0 = i * FRAME_W
        frame = sheet[:, x0:x0 + FRAME_W]
        mask = _jump_drill_mask(frame, exclude)
        out[:, x0:x0 + FRAME_W] = _recolor_pixels(frame, mask, target_h, target_s, target_v)
    Image.fromarray(out).save(out_path)


def _recolor_icon(src_path, out_path, target_h, target_s, target_v):
    im = Image.open(src_path).convert("RGBA")
    arr = np.array(im)
    mask = _icon_drill_mask(arr)
    out = _recolor_pixels(arr, mask, target_h, target_s, target_v)
    Image.fromarray(out).save(out_path)


# ---------------------------------------------------------------------------
# Точка входа: перекрашивает все четыре листа под все четыре тира
# ---------------------------------------------------------------------------

SHEETS = [
    # (имя листа без расширения, папка, перекрасчик)
    ("dig_rig_side", CHAR_DIR, lambda s, o, h, sat, val: _recolor_side_or_down(s, o, h, sat, val, _side_drill_mask)),
    ("dig_rig_down", CHAR_DIR, lambda s, o, h, sat, val: _recolor_side_or_down(s, o, h, sat, val, _down_drill_mask)),
    ("rig_jump", CHAR_DIR, _recolor_jump),
    ("drill_rig_icon", ITEMS_DIR, _recolor_icon),
]


def target_colors():
    """{tier_id: (H_deg, S, V)} — если под рукой лежат кирки (обычный прогон
    из репозитория), цвет СНИМАЕТСЯ с них заново; иначе используются заранее
    посчитанные числа из TIERS (см. его докстринг) — тот же результат, но
    без обязательной зависимости от art/items/pickaxe_*.png при запуске из
    контекста, где кирок нет."""
    out = {}
    for tier_id, fallback_h, fallback_s, fallback_v in TIERS:
        pickaxe_path = os.path.join(ITEMS_DIR, "pickaxe_%s.png" % tier_id)
        if os.path.exists(pickaxe_path):
            out[tier_id] = _pickaxe_metal_hsv(pickaxe_path)
        else:
            out[tier_id] = (fallback_h, fallback_s, fallback_v)
    return out


def main():
    colors = target_colors()
    for tier_id, (h, s, val) in colors.items():
        print("%-10s H=%.1f S=%.3f V=%.3f" % (tier_id, h, s, val))
        for name, folder, fn in SHEETS:
            src = os.path.join(folder, name + ".png")
            if not os.path.exists(src):
                print("  пропуск %s: исходника нет" % src)
                continue
            out = os.path.join(folder, "%s_%s.png" % (name, tier_id))
            fn(src, out, h, s, val)
            print("  %s -> %s" % (src, out))


if __name__ == "__main__":
    sys.exit(main())
