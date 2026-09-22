#!/usr/bin/env python3
"""Богатый дом бабки — из art/_source/house_modern.jpg в art/env/house_rich.png.

Почему отдельный скрипт, а не gen_art: это НЕ плейсхолдер, а присланный
владельцем рисунок. Нарезка скриптом, чтобы её можно было повторить, когда
рисунок поправят, — так же, как с персонажами, тайлами и буром.

Имя выхода (house_rich.png/.json) НЕ переименовано вслед за новым исходником:
на него ссылаются scripts/house/house_system.gd, docs/GDD.md и тесты, и смена
имени потребовала бы правки всех ссылок без всякой пользы — игра как считала
"дом после смерти деда" одним файлом, так и считает, просто рисунок теперь
другой. Старый исходник (house_rich.jpg, с небом и мостовой) остаётся в
_source нетронутым — он был снят с той же картинки дома, но в декорации
сада, и раньше именно по нему вырезался спрайт; см. git-историю скрипта, если
понадобится вернуться.

Новый лист — тот же дом на ОДНОРОДНОМ сером фоне (владелец прислал его именно
так, под нарезку), поэтому фон вычитается не порогом синевы неба (как было),
а универсальной заливкой от краёв — тем же приёмом, что в import_move.py и
import_art.py::background_mask, только со своим цветом фона.

Что делает:
  1. вычитает фон заливкой от краёв (серое ВНУТРИ дома — алюминиевые рамы,
     кровельный карниз, тарелка — остаётся: заливка не доходит до них, они
     изолированы более тёмными рамами и стенами, см. background_mask);
  2. обрезает по содержимому — рисунок уже кадрирован владельцем впритык, но
     точную рамку считаем сами, а не гадаем координаты руками;
  3. уменьшает LANCZOS'ом с премультиплированной альфой и возвращает резкость
     unsharp'ом (import_art.py::shrink/_restore_bite) — так на стекле и
     перилах не остаётся ни серой каймы от фона, ни размытия от масштаба;
     палитру НЕ квантуем (в отличие от старой версии скрипта) — рисунок и без
     того чистый пиксель-арт, квантование только смазало бы стекло и тени;
  4. считает, где у дома вход, и пишет это число рядом — движок ставит
     спрайт так, чтобы вход пришёлся ровно на клетку двери.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from import_art import shrink  # noqa: E402  премультиплированный LANCZOS + unsharp

SRC = ROOT / "art/_source/house_modern.jpg"
OUT = ROOT / "art/env/house_rich.png"
META = ROOT / "art/env/house_rich.json"

TILE = 32
# Ширина спрайта в клетках. Дом по balance.json (house.x_range) занимает
# клетки 0-14 — 15 клеток, 480 логических px, — а правым краем прижимается к
# границе огорода (см. house_system.gd:_build_world_props). 14 клеток
# (448 px) оставляют одну клетку травы слева от навеса — так дальний столб
# карпорта не упирается ровно в границу мира; 15 клеток дом бы тоже не
# перекрыл, но лишний метр газона левее делает сцену чуть просторнее.
TARGET_CELLS = 14

# Фон листа — однородно-серый (владелец прислал именно так). Цвет меряем по
# самой картинке (край кадра — гарантированно фон), а не вписываем числом:
# так скрипт переживёт лёгкую смену экспозиции при переприсылке рисунка.
BG_TOL = 24  # евклидово расстояние в RGB; подобрано по образцу ниже


def _measure_bg(a: np.ndarray) -> np.ndarray:
    """Средний цвет фона по кромке кадра (все четыре стороны — не только
    верх, как для house_rich.jpg со своим небом: тут фон сплошной со всех
    сторон)."""
    edge = np.concatenate([
        a[0, :, :], a[-1, :, :], a[:, 0, :], a[:, -1, :],
    ]).astype(np.float64)
    return edge.mean(axis=0)


def background_mask(a: np.ndarray, bg: np.ndarray, tol: float) -> np.ndarray:
    """True там, где фон. Заливка от ВСЕХ четырёх краёв (numpy BFS, без
    Python-цикла по пикселям — лист 1024×800, пиксельный BFS на нём заметно
    медленнее).

    Обычным порогом резать нельзя: карниз крыши, тарелка и алюминиевые рамы
    окон тоже серые и по тону близки к фону. Спасает связность — заливка идёт
    только там, где серое тянется НЕПРЕРЫВНО от кромки кадра, а эти детали
    со всех сторон обведены рамами/стенами куда темнее фона и остаются
    отрезанными островками.
    """
    h, w, _ = a.shape
    dist = np.sqrt(((a.astype(np.float64) - bg) ** 2).sum(axis=2))
    bg_like = dist <= tol

    seen = np.zeros((h, w), dtype=bool)
    frontier_y = np.concatenate([np.zeros(w, dtype=int), np.full(w, h - 1, dtype=int),
                                  np.arange(h), np.arange(h)])
    frontier_x = np.concatenate([np.arange(w), np.arange(w),
                                  np.zeros(h, dtype=int), np.full(h, w - 1, dtype=int)])
    stack = list(zip(frontier_y.tolist(), frontier_x.tolist()))
    mask = np.zeros((h, w), dtype=bool)
    while stack:
        y, x = stack.pop()
        if seen[y, x]:
            continue
        seen[y, x] = True
        if not bg_like[y, x]:
            continue
        mask[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def cut(im: Image.Image, mask: np.ndarray) -> Image.Image:
    """Весь лист в RGBA: альфа = не-фон. Обрезка по содержимому — отдельным
    шагом (getbbox), тут координаты листа не двигаем."""
    arr = np.asarray(im.convert("RGB"))
    alpha = np.where(mask, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([arr, alpha]), "RGBA")


# Перспектива рисунка не строго фронтальная: два столба навеса, ближние к
# зрителю, нарисованы на несколько px НИЖЕ, чем стена дома и колёса машины —
# они физически ближе к «камере» и потому крупнее/ниже на кадре. Обрежь низ
# по самому глубокому пикселю всего листа (эти столбы) — и между колёсами
# машины (они мельче и до этой линии не достают) и низом спрайта останется
# щель в несколько px, машина будет казаться висящей над землёй. 95-й
# перцентиль нижних кромок по столбцам берёт линию земли ПО ОСНОВНОЙ массе
# кадра (стена дома, большая часть машины, дальние столбы) и не тянется за
# редкими ближними столбами (их пара, это единицы процентов ширины) — их
# низ проще обрезать на несколько px, чем оставлять зазор под колёсами.
GROUND_PERCENTILE = 95


def _ground_bottom(alpha: np.ndarray, left: int, right: int, top: int) -> int:
    bottoms = []
    for x in range(left, right + 1):
        col = alpha[top:, x]
        ys = np.nonzero(col > 10)[0]
        if len(ys):
            bottoms.append(top + int(ys[-1]))
    return int(round(float(np.percentile(np.array(bottoms), GROUND_PERCENTILE))))


# Вход — правая (широкая) секция раздвижного остекления первого этажа: на
# рисунке это ЯВНО более широкая из двух низких стеклянных дверей — левая
# ведёт в гостиную поменьше, эта — главный вход. Найдено по чёрным рамам
# окон первого этажа (самые тёмные столбцы кадра на высоте дверей): левая
# секция 400-550 px (150 px), правая 621-870 px (249 px) в координатах
# исходника — заметно шире, как и должен быть парадный вход. Число — доля от
# ширины КАДРА ПОСЛЕ ОБРЕЗКИ (bbox содержимого), а не пиксели исходника:
# рисунок перекадрируют — доля переживёт. Замер сделан руками по картинке
# владельца (см. tools/import_house.py в истории коммитов для деталей) — как
# и раньше, для одной присланной картинки это честнее автоэвристики.
ENTRANCE_FRACTION = 0.752


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    im = Image.open(src).convert("RGB")
    a = np.asarray(im)

    bg = _measure_bg(a)
    mask = background_mask(a, bg, BG_TOL)
    full = cut(im, mask)

    box = full.getbbox()
    if box is None:
        sys.exit("после вычитания фона на листе ничего не осталось — проверь BG_TOL")
    left, top, right, bottom = box
    ground = _ground_bottom(np.asarray(full)[:, :, 3], left, right - 1, top)
    crop = full.crop((left, top, right, ground + 1))

    out_w = TARGET_CELLS * TILE
    out_h = max(1, round(crop.height * out_w / crop.width))
    # Высоту сажаем на сетку — низ дома должен лечь ровно на линию земли, а не
    # повиснуть с прозрачной каёмкой снизу.
    out_h = int(round(out_h / TILE)) * TILE

    # Премультиплированный LANCZOS + unsharp (import_art.py::shrink): именно
    # он не даёт серому фону просочиться в цвет краевых пикселей при
    # уменьшении — обычный resize смешал бы альфу и цвет наивно, и по контуру
    # остался бы серый ореол. Палитру не квантуем — colors=0 по умолчанию.
    small = shrink(crop, (out_w, out_h))
    small.save(OUT)

    entrance_x = int(round(out_w * ENTRANCE_FRACTION))
    META.write_text(json.dumps({
        "entrance_x": entrance_x,
        "width": out_w,
        "height": out_h,
        "_note": "entrance_x — точка спрайта, которая должна прийтись на клетку двери",
    }, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"{OUT.name}: {out_w}×{out_h}, вход на x={entrance_x} (источник: {src.name})")


if __name__ == "__main__":
    main()
