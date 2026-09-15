#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_art.py — генератор плейсхолдер-графики для «Раскопки на каникулах».

Рисует программно (PIL) все спрайты игры в art/ пиксель-в-пиксель,
строго ограниченной палитрой (см. art/PALETTE.md, который этот же
скрипт и порождает из PALETTE ниже — один источник правды на код и документацию).

Идемпотентно: каждый прогон полностью перезаписывает art/.
Детерминировано: каждый ассет использует свой seed, так что повторный
запуск даёт битово те же PNG.

Запуск:
    python3 tools/gen_art.py

Если Pillow недоступна и её не получилось поставить через pip — здесь
нет ручного PNG-энкодера через zlib/struct, потому что Pillow в этом
окружении установилась; см. `pip install Pillow`, если её нет.
"""

import os
import random
import math

from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------------
# Пути
# --------------------------------------------------------------------------

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
TILE = 32


def out(relpath):
    p = os.path.join(ART, relpath)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def save(img, relpath):
    img.save(out(relpath))


# --------------------------------------------------------------------------
# ПАЛИТРА — единственный источник правды для кода и art/PALETTE.md
# --------------------------------------------------------------------------
# Логика перехода: тёплые земляные/охристые тона у поверхности -> нейтральный
# нерудный камень -> рукотворный бетон фундамента (первый шаг к «холоду») ->
# синевато-чёрная пустота шахты. Руды глубже 500 сознательно уходят в
# холодные, неоновые и противоестественные оттенки (литий, уран) — это
# должно физически ощущаться как «дальше от дома и солнца».

PALETTE = [
    # key,              hex,       группа,        назначение (RU)
    # --- Земля (поверхность, тёплая) ---
    ("soil_shadow",  "#3E2A1A", "Земля",       "тень в комьях земли, слои 1-4"),
    ("soil_base",     "#6B4428", "Земля",       "основной тон земляного тайла"),
    ("soil_light",    "#8F6238", "Земля",       "светлая грань комка земли"),
    ("soil_warm",     "#B4854E", "Земля",       "тёплый блик у самой поверхности"),

    # --- Камень (нейтральная помеха) ---
    ("stone_shadow", "#3A3A44", "Камень",      "тень в камне"),
    ("stone_base",    "#5C5C68", "Камень",      "основной тон камня"),
    ("stone_light",   "#7E7E8C", "Камень",      "светлая грань камня / скол"),

    # --- Фундамент (рукотворный, слой 5, первый шаг к холоду) ---
    ("concrete_shadow", "#4C4E54", "Фундамент", "тень бетона"),
    ("concrete_base",    "#6E7176", "Фундамент", "основной тон бетона"),
    ("rebar_dark",        "#5C3018", "Фундамент", "арматура, тёмный металл"),
    ("rebar_rust",         "#8A4E28", "Фундамент", "ржавчина на арматуре"),

    # --- Пустота (холодная, безвоздушная) ---
    ("void_far",   "#0A0C12", "Пустота",     "дальний план пустой клетки"),
    ("void_base",   "#161A24", "Пустота",     "основной тон полости"),
    ("void_rim",     "#2E3548", "Пустота",     "риммлайт по краю — намёк на объём"),

    # --- Руды: освоенные металлы (тёплые/нейтральные, неглубокие) ---
    ("iron_base",   "#8B4A3A", "Руда:Железо",   "ржаво-бурые вкрапления"),
    ("iron_light",   "#BC6A4C", "Руда:Железо",   "блик на вкраплении"),
    ("lead_base",    "#33394A", "Руда:Свинец",   "тяжёлый тёмно-синий, темнее камня"),
    ("lead_light",    "#9AA6BC", "Руда:Свинец",   "холодный стальной блик на слитке"),
    ("silver_base",   "#C7CDD6", "Руда:Серебро",  "холодный светлый металл"),
    ("silver_light",   "#F4F7FA", "Руда:Серебро",  "яркий блик серебра"),
    ("copper_base",    "#C2703A", "Руда:Медь",     "оранжево-рыжий металл"),
    ("copper_light",    "#E89A5E", "Руда:Медь",     "блик меди"),
    ("gold_base",        "#E8B32E", "Руда:Золото",   "жёлтый самородок"),
    ("gold_light",        "#FFE066", "Руда:Золото",   "яркий блик золота"),
    ("scrap_base",         "#6A6A72", "Руда:Металлолом", "серый ржавый хлам"),
    ("scrap_rust",          "#8A4E30", "Руда:Металлолом", "пятна ржавчины на ломе"),

    # --- Руды: редкие/технологичные (холоднее) ---
    ("diamond_base",  "#6FE0D8", "Руда:Алмаз",    "бирюзовый кристалл"),
    ("diamond_light",  "#FFFFFF", "Руда:Алмаз",    "белая искра алмаза"),
    ("nickel_base",     "#7FA868", "Руда:Никель",   "насыщенный оливково-зелёный металл"),
    ("nickel_light",     "#B8DC98", "Руда:Никель",   "блик никеля"),
    ("platinum_base",     "#BFDCFA", "Руда:Платина",  "яркий бело-голубой драгоценный металл"),
    ("platinum_light",     "#FFFFFF", "Руда:Платина",  "ослепительный блик платины"),
    ("aluminium_base",      "#8B99A2", "Руда:Алюминий", "матовый нейтрально-серый металл, без блеска"),
    ("aluminium_light",      "#B8C4C8", "Руда:Алюминий", "приглушённый блик алюминия"),
    ("titanium_base",       "#A996C4", "Руда:Титан",    "холодный сиреневый металл"),
    ("titanium_light",       "#D2C2EE", "Руда:Титан",    "блик титана"),

    # --- Руды: топливо ---
    ("peat_base",  "#3E2C1C", "Руда:Торф",   "тёмно-бурые волокна"),
    ("peat_light",  "#5E4830", "Руда:Торф",   "светлое волокно торфа"),
    ("coal_base",    "#1C1C22", "Руда:Уголь",  "чёрный уголь"),
    ("coal_light",    "#4E4E5C", "Руда:Уголь",  "сине-стальной блеск угля"),

    # --- Руды: опасные / ядовитые (максимальный холод глубины) ---
    ("lithium_base",  "#D878BC", "Руда:Литий",  "розово-пурпурный кристалл"),
    ("lithium_light",  "#FFB2E6", "Руда:Литий",  "яркая грань лития"),
    ("mercury_base",    "#CDD2D6", "Руда:Ртуть",  "жидкий металл"),
    ("mercury_accent",   "#8E6663", "Руда:Ртуть",  "красноватый отблеск (ядовитое облако)"),
    ("uranium_core",       "#14601F", "Руда:Уран",   "тёмное ядро уранового куска"),
    ("uranium_glow",        "#3DFF6F", "Руда:Уран",   "ядовито-неоновое свечение"),

    # --- Руды: самоцветы (чисто на продажу) ---
    ("ruby_base",    "#C21E3A", "Руда:Рубин",   "глубокий красный"),
    ("ruby_light",    "#FF5570", "Руда:Рубин",   "яркая грань рубина"),
    ("emerald_base",   "#1C8A52", "Руда:Изумруд", "насыщенный зелёный"),
    ("emerald_light",   "#4DE094", "Руда:Изумруд", "яркая грань изумруда"),

    # --- Персонаж ---
    ("skin",         "#E0A878", "Персонаж", "кожа"),
    ("skin_shadow",   "#B8815A", "Персонаж", "тень на коже"),
    ("hair",           "#3D2818", "Персонаж", "волосы / обувь (общий тёмный тон)"),
    ("shirt",            "#CC5A3A", "Персонаж", "рубашка, тёплый деревенский акцент"),
    ("shirt_shadow",      "#9C4028", "Персонаж", "тень рубашки"),
    ("pants",               "#465A72", "Персонаж", "штаны"),
    ("pants_shadow",         "#303F52", "Персонаж", "тень штанов"),
    ("eye_dark",              "#201818", "Персонаж", "глаза / контур лица"),

    # --- Инструменты (сверх переиспользуемых земляных/свинцовых тонов) ---
    ("steel_blue", "#5C7484", "Инструменты", "холодная сталь новых инструментов"),

    # --- UI ---
    ("parchment",        "#E8D8B0", "UI", "тёплый пергамент диалоговой панели"),
    ("parchment_border",  "#A4835A", "UI", "рамка панели"),
    ("ui_dark_bg",          "#241E2C", "UI", "тёмный фон слота инвентаря"),
    ("slot_border",          "#4A3F5C", "UI", "рамка слота"),
    ("stomach_base",          "#F4626F", "UI", "стенка желудка для иконки голода"),
    ("stomach_light",          "#F0918F", "UI", "светлая часть желудка (свод и малая кривизна)"),
    ("stomach_fold",          "#C8384A", "UI", "складки слизистой"),

    # --- Окружение (сверх переиспользуемых тонов) ---
    ("grass_field", "#4F7A34", "Окружение", "трава двора"),
    ("grass_dark",    "#365423", "Окружение", "тень травы"),
]

COLOR = {k: h for k, h, *_ in PALETTE}

# Смысловые псевдонимы: переиспользуем родственные тона вместо того, чтобы
# заводить новый цвет под каждую мелочь — так предметы визуально «из одного
# мира». Держит общий размер палитры разумным несмотря на то, что 17 руд
# сами по себе требуют 34 уникальных тона ради мгновенной узнаваемости.
ALIAS = {
    "wood": "soil_base", "wood_dark": "soil_shadow",
    "iron_tool": "lead_light", "rust_tool": "rebar_rust",
    "heart": "ruby_base", "heart_light": "ruby_light",
    "coin": "gold_base", "coin_light": "gold_light",
    "dollar": "emerald_base", "dollar_light": "emerald_light",
    "stamina": "gold_light", "stamina_dark": "copper_base",
    "blackbox_body": "coal_base", "blackbox_light": "ruby_light",
    "roof": "ruby_base", "roof_dark": "shirt_shadow",
    "wall": "parchment", "wall_dark": "parchment_border",
    "hatch": "lead_base", "hatch_light": "lead_light",
    "grave": "stone_light", "grave_shadow": "stone_shadow",
    "shoe": "hair",
}


def _hex_to_rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def C(key, a=255):
    """Цвет палитры (или псевдоним) как RGBA-кортеж."""
    real = ALIAS.get(key, key)
    r, g, b = _hex_to_rgb(COLOR[real])
    return (r, g, b, a)


def write_palette_doc():
    lines = []
    lines.append("# Палитра — «Раскопки на каникулах»\n")
    lines.append(
        "Сгенерировано из `tools/gen_art.py` (словарь `PALETTE`) — при правке "
        "цветов правь код, этот файл пересобирается автоматически.\n"
    )
    lines.append(
        "## Логика перехода тепло → холодно → ядовито\n\n"
        "Поверхность (слои 1-4) — тёплая охра земли, дом, деревня: `soil_*`. "
        "Камень (`stone_*`) нейтрален — это помеха, а не место действия. "
        "Слой 5, фундамент (`concrete_*`, `rebar_*`) — первый рукотворный, "
        "чуть более холодный и техногенный объект на пути вниз. Пустота "
        "шахты (`void_*`) — синевато-чёрная, без тепла вообще. Руды первых "
        "500 клеток (железо, свинец, серебро, медь, золото, металлолом) "
        "остаются в тёплой/нейтральной гамме металлов. Дальше — алмаз, "
        "никель, платина, титан — гамма уходит в холодные сине-сиреневые "
        "тона техники. На самой опасной глубине — литий и особенно ртуть "
        "и уран — цвет становится откровенно ядовитым и неестественным "
        "(неоновый зелёный уран, тревожный розовый литий), сигнализируя "
        "угрозу ещё до того, как игрок прочитает описание предмета.\n"
    )
    lines.append(
        "## Узнаваемость руд\n\n"
        "17 видов руды обязаны различаться с одного взгляда на тайле "
        "32×32 (см. ГДД, раздел 4) — поэтому у каждой руды *два* "
        "уникальных тона (база + блик), и это основная причина, по "
        "которой палитра больше типичных 32–48 цветов: 17 руд × 2 = 34 "
        "тона только на них, плюс форма вкраплений тоже разная для каждой "
        "категории (самородок-нуггет / кристалл / волокно торфа / "
        "блестящий уголь / капля ртути / светящийся уран / мусорные "
        "заклёпки лома) — цвет и силуэт подтверждают друг друга.\n"
    )
    lines.append("## Переиспользование тонов (`ALIAS` в коде)\n\n")
    lines.append(
        "Инструменты, UI и окружение не заводят новых цветов там, где "
        "тон уже есть в палитре — это держит общий мир визуально цельным. "
        "Например: дерево инструментов = тона земли, сталь инструментов = "
        "тон свинца, сердце HP = тон рубина, монета = тон золота, доллар = "
        "тон изумруда, кузов чёрного ящика = тон угля.\n\n"
    )
    lines.append("```")
    for k, v in ALIAS.items():
        lines.append(f"{k:16s} -> {v}")
    lines.append("```\n")

    lines.append(f"## Полный список ({len(PALETTE)} цветов)\n")
    lines.append("| Ключ | HEX | Группа | Назначение |")
    lines.append("|---|---|---|---|")
    for key, hexv, group, desc in PALETTE:
        lines.append(f"| `{key}` | `{hexv}` | {group} | {desc} |")
    lines.append("")

    with open(os.path.join(ART, "PALETTE.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# --------------------------------------------------------------------------
# Низкоуровневые помощники рисования
# --------------------------------------------------------------------------

def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def blend_px(img, x, y, color):
    """Альфа-композит одного пикселя поверх текущего содержимого."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    r, g, b, a = color
    if a >= 255:
        img.putpixel((x, y), (r, g, b, 255))
        return
    if a <= 0:
        return
    br, bg, bb, ba = img.getpixel((x, y))
    t = a / 255.0
    nr = int(r * t + br * (1 - t))
    ng = int(g * t + bg * (1 - t))
    nb = int(b * t + bb * (1 - t))
    na = max(ba, a)
    img.putpixel((x, y), (nr, ng, nb, na))


def shade(color, factor):
    r, g, b, a = color
    return (
        max(0, min(255, int(r * factor))),
        max(0, min(255, int(g * factor))),
        max(0, min(255, int(b * factor))),
        a,
    )


def fill_dither(img, base, accent, rng, prob=0.30, top_light=0.0, bottom_shade=0.0,
                 x0=0, y0=0, x1=None, y1=None):
    """Заполняет прямоугольник шумной текстурой из двух тонов + вертикальный
    градиент яркости (тёплый блик сверху / тень снизу)."""
    x1 = img.width if x1 is None else x1
    y1 = img.height if y1 is None else y1
    h = y1 - y0
    for y in range(y0, y1):
        f = 1.0
        ty = (y - y0) / max(1, h - 1)
        if top_light:
            f += top_light * max(0.0, 1.0 - ty * 3.0)
        if bottom_shade:
            f -= bottom_shade * max(0.0, (ty - 0.66) / 0.34)
        for x in range(x0, x1):
            c = accent if rng.random() < prob else base
            img.putpixel((x, y), shade(c, f))


def irregular_edge_shadow(img, rng, color, chance=0.5, margin=1):
    """Неровная тёмная кайма по периметру — намёк на границу клетки без
    жёсткой рамки (тайлы должны читаться поодиночке в превью)."""
    w, h = img.width, img.height
    for x in range(w):
        if rng.random() < chance:
            blend_px(img, x, margin - 1, color)
        if rng.random() < chance:
            blend_px(img, x, h - margin, color)
    for y in range(h):
        if rng.random() < chance:
            blend_px(img, margin - 1, y, color)
        if rng.random() < chance:
            blend_px(img, w - margin, y, color)


OUTLINE = (12, 12, 16, 255)


def ellipse(img, cx, cy, rx, ry, color, outline=None):
    d = ImageDraw.Draw(img)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=color, outline=outline)


def rect(img, x0, y0, x1, y1, color):
    d = ImageDraw.Draw(img)
    d.rectangle([x0, y0, x1, y1], fill=color)


def line(img, pts, color, width=1):
    d = ImageDraw.Draw(img)
    d.line(pts, fill=color, width=width)


def poly(img, pts, color, outline=None):
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=color, outline=outline)


# --------------------------------------------------------------------------
# ТАЙЛЫ 32×32
# --------------------------------------------------------------------------

def draw_empty_tile():
    img = canvas(TILE, TILE)
    rng = random.Random("empty")
    # Никакого направленного градиента и краевых риммлайтов: клетка пустоты
    # мостится вплотную с соседними такими же клетками, любая привязка к
    # краю (верх/лево) даёт на стыках повторяющуюся световую решётку.
    fill_dither(img, C("void_base"), C("void_far"), rng, prob=0.35)
    # блики раскиданы по всей площади без привязки к краю — тайл остаётся
    # бесшовным, но не выглядит совсем плоским
    for _ in range(7):
        x, y = rng.randint(0, TILE - 1), rng.randint(0, TILE - 1)
        blend_px(img, x, y, C("void_rim", 110))
    save(img, "tiles/empty.png")


def _dirt_base(img, rng):
    """Общая порода-подложка: один и тот же тон/дизеринг для всех вариантов
    земли, без направленного градиента и краевых засветок — иначе тайлы не
    стыкуются бесшовно. Разнообразие вариантов даёт только оверлей поверх."""
    fill_dither(img, C("soil_base"), C("soil_shadow"), rng, prob=0.30)
    # редкая тёплая крошка, равномерно по площади (не у края) — держит
    # землю живой без привязки к направлению
    for _ in range(rng.randint(10, 16)):
        x, y = rng.randint(0, TILE - 1), rng.randint(0, TILE - 1)
        blend_px(img, x, y, C("soil_warm", 130))


def draw_dirt_tile(n, seed):
    """Четыре варианта земли с одним и тем же базовым тоном, но разным
    почерком поверх — камешки, трещины, корешки, комья — чтобы поле не
    читалось как один повторяющийся тайл, оставаясь одной породой."""
    img = canvas(TILE, TILE)
    rng = random.Random(seed)
    _dirt_base(img, rng)

    if n == 1:
        # «камешки»: россыпь мелкой круглой гальки разного размера
        for _ in range(rng.randint(7, 10)):
            x, y = rng.randint(2, TILE - 3), rng.randint(2, TILE - 3)
            r = rng.choice([1, 1, 1, 2])
            c = C("soil_light") if rng.random() < 0.75 else C("stone_light")
            ellipse(img, x, y, r, r, c)
            if r == 2:
                blend_px(img, x - 1, y - 1, C("soil_warm"))
    elif n == 2:
        # «трещины»: сухая растрескавшаяся земля, галька почти не видна
        for _ in range(rng.randint(3, 5)):
            x = rng.randint(3, TILE - 4)
            y = rng.randint(3, TILE - 4)
            pts = [(x, y)]
            for _ in range(rng.randint(2, 4)):
                x += rng.randint(-3, 3)
                y += rng.randint(-3, 3)
                x = max(1, min(TILE - 2, x))
                y = max(1, min(TILE - 2, y))
                pts.append((x, y))
            line(img, pts, C("soil_shadow"), 1)
        for _ in range(rng.randint(2, 3)):
            x, y = rng.randint(2, TILE - 3), rng.randint(2, TILE - 3)
            ellipse(img, x, y, 1, 1, C("soil_light"))
    elif n == 3:
        # «корешки»: сухие травинки и корни, галька редкая
        for _ in range(rng.randint(3, 5)):
            x = rng.randint(3, TILE - 4)
            y0 = rng.randint(0, TILE - 6)
            length = rng.randint(3, 6)
            bend = rng.choice([-2, -1, 1, 2])
            line(img, [(x, y0), (x + bend, y0 + length)], C("soil_warm"), 1)
            blend_px(img, x, y0, C("soil_light"))
        for _ in range(rng.randint(2, 4)):
            x, y = rng.randint(2, TILE - 3), rng.randint(2, TILE - 3)
            ellipse(img, x, y, 1, 1, C("soil_light"))
    else:
        # «комья»: крупные слежавшиеся комки, малой галечной крошки нет
        for _ in range(rng.randint(4, 6)):
            x, y = rng.randint(3, TILE - 4), rng.randint(3, TILE - 4)
            rx, ry = rng.choice([2, 3]), rng.choice([2, 3])
            ellipse(img, x, y, rx, ry, shade(C("soil_base"), 0.85))
            ellipse(img, x - 1, y - 1, max(1, rx - 2), max(1, ry - 2), C("soil_light"))
            blend_px(img, x + rx - 1, y + ry - 1, C("soil_shadow"))

    save(img, f"tiles/dirt_{n}.png")


def draw_stone_tile():
    img = canvas(TILE, TILE)
    rng = random.Random("stone")
    fill_dither(img, C("stone_base"), C("stone_shadow"), rng, prob=0.34)
    # трещины — держим подальше от края, чтобы соседний тайл не обрубал линию
    for _ in range(rng.randint(2, 4)):
        x = rng.randint(5, TILE - 6)
        y = rng.randint(5, TILE - 6)
        pts = [(x, y)]
        for _ in range(rng.randint(2, 4)):
            x += rng.randint(-3, 3)
            y += rng.randint(-2, 3)
            x = max(2, min(TILE - 3, x))
            y = max(2, min(TILE - 3, y))
            pts.append((x, y))
        line(img, pts, C("stone_shadow"), 1)
    for _ in range(4):
        x, y = rng.randint(2, TILE - 3), rng.randint(2, TILE - 3)
        blend_px(img, x, y, C("stone_light", 200))
    save(img, "tiles/stone.png")


def draw_foundation_tile():
    img = canvas(TILE, TILE)
    rng = random.Random("foundation")
    fill_dither(img, C("concrete_base"), C("concrete_shadow"), rng, prob=0.22)
    # арматурный крест по центру
    cx, cy = TILE // 2, TILE // 2
    rect(img, cx - 1, 2, cx + 1, TILE - 3, C("rebar_dark"))
    rect(img, 2, cy - 1, TILE - 3, cy + 1, C("rebar_dark"))
    for (x0, y0, x1, y1) in [(cx - 1, 2, cx + 1, TILE - 3), (2, cy - 1, TILE - 3, cy + 1)]:
        blend_px(img, x0, y0, C("rebar_rust", 220))
        blend_px(img, x1, y1, C("rebar_rust", 220))
    # трещины в бетоне
    line(img, [(4, 6), (8, 10), (6, 15)], C("concrete_shadow"), 1)
    save(img, "tiles/foundation.png")


# --- Руды -------------------------------------------------------------

ORES = [
    ("iron", "Железо", "iron_base", "iron_light", "nugget"),
    ("lead", "Свинец", "lead_base", "lead_light", "ingot"),
    ("silver", "Серебро", "silver_base", "silver_light", "nugget_sparkle"),
    ("copper", "Медь", "copper_base", "copper_light", "nugget"),
    ("gold", "Золото", "gold_base", "gold_light", "nugget_sparkle"),
    ("diamond", "Алмаз", "diamond_base", "diamond_light", "crystal_sparkle"),
    ("nickel", "Никель", "nickel_base", "nickel_light", "pebble_cluster"),
    ("peat", "Торф", "peat_base", "peat_light", "fiber"),
    ("coal", "Каменный уголь", "coal_base", "coal_light", "chunk_sparkle"),
    ("platinum", "Платина", "platinum_base", "platinum_light", "facet"),
    ("aluminium", "Алюминий", "aluminium_base", "aluminium_light", "bar"),
    ("titanium", "Титан", "titanium_base", "titanium_light", "crystal_sparkle"),
    ("lithium", "Литий", "lithium_base", "lithium_light", "crystal_sparkle"),
    ("mercury", "Ртуть", "mercury_base", "mercury_accent", "bead"),
    ("uranium", "Уран", "uranium_core", "uranium_glow", "glow"),
    ("ruby", "Рубин", "ruby_base", "ruby_light", "crystal_sparkle"),
    ("emerald", "Изумруд", "emerald_base", "emerald_light", "crystal_sparkle"),
    ("scrap", "Металлолом", "scrap_base", "scrap_rust", "debris"),
]


def draw_nugget(img, rng, cx, cy, base, light, angular=False, shine=True):
    w = rng.choice([2, 3, 3])
    h = rng.choice([2, 3, 3])
    if angular:
        pts = []
        n = 5
        for i in range(n):
            a = (i / n) * 2 * math.pi + rng.uniform(-0.3, 0.3)
            rr = rng.uniform(0.6, 1.0)
            pts.append((cx + math.cos(a) * w * rr, cy + math.sin(a) * h * rr))
        poly(img, pts, base, outline=OUTLINE)
    else:
        ellipse(img, cx, cy, w, h, base, outline=OUTLINE)
    if shine:
        blend_px(img, cx - w // 2, cy - h // 2, light)
        blend_px(img, cx - w // 2 + 1, cy - h // 2, light)
    blend_px(img, cx + w // 2, cy + h // 2, shade(base, 0.55))


def draw_crystal(img, rng, cx, cy, base, light):
    w = rng.choice([2, 3])
    h = rng.choice([3, 4])
    if rng.random() < 0.5:
        pts = [(cx, cy - h), (cx + w, cy), (cx, cy + h), (cx - w, cy)]
    else:
        pts = [(cx, cy - h), (cx + w, cy - h // 2), (cx + w, cy + h // 2),
               (cx, cy + h), (cx - w, cy + h // 2), (cx - w, cy - h // 2)]
    poly(img, pts, base, outline=OUTLINE)
    blend_px(img, cx, cy - h, light)
    blend_px(img, cx, cy - h + 1, light)


def draw_fiber(img, rng, cx, cy, base, light):
    length = rng.randint(4, 7)
    ang = rng.choice([0, 0, 1])
    if ang == 0:
        end = (cx + length, cy + rng.choice([-1, 0, 1]))
    else:
        end = (cx + rng.choice([-1, 0, 1]), cy + length)
    # тёмная подложка чуть шире + светлое волокно поверх — держит контраст
    line(img, [(cx, cy), end], OUTLINE, 2)
    line(img, [(cx, cy), end], base, 1)
    blend_px(img, cx, cy, light)
    mid = ((cx + end[0]) // 2, (cy + end[1]) // 2)
    blend_px(img, mid[0], mid[1], light)


def draw_ingot(img, rng, cx, cy, base, light):
    # свинец: тяжёлый тусклый слиток-брусок, почти без блеска — плотная
    # прямоугольная масса читается как "тяжёлый металл", а не как крапинка
    w = rng.choice([3, 3, 4])
    h = rng.choice([2, 2, 3])
    rect(img, cx - w, cy - h, cx + w, cy + h, base)
    line(img, [(cx - w, cy - h), (cx + w, cy - h), (cx + w, cy + h),
               (cx - w, cy + h), (cx - w, cy - h)], OUTLINE, 1)
    # одна тонкая холодная грань сверху — единственный блик, тусклый металл
    line(img, [(cx - w + 1, cy - h + 1), (cx + w - 1, cy - h + 1)], light, 1)
    blend_px(img, cx - w + 1, cy + h - 1, shade(base, 0.6))


def draw_pebble_cluster(img, rng, cx, cy, base, light):
    # никель: тесная гроздь мелких округлых узелков-конкреций (не один
    # кусок, а слипшиеся горошины) — силуэт заметно отличается от слитка
    offs = [(0, 0), (2, 1), (-2, 1), (1, -2), (-1, 2)]
    n = rng.choice([3, 4])
    for dx, dy in offs[:n]:
        r = rng.choice([1, 1, 2])
        ellipse(img, cx + dx, cy + dy, r, r, base, outline=OUTLINE)
    blend_px(img, cx - 1, cy - 1, light)
    blend_px(img, cx + offs[n - 1][0], cy + offs[n - 1][1], shade(base, 0.6))


def draw_facet(img, rng, cx, cy, base, light):
    # платина: широкий гранёный самородок-"кабошон" с крестовым бликом —
    # плоский шестиугольник, а не круглая капля и не вертикальный кристалл
    w = rng.choice([3, 4])
    h = 2
    pts = [(cx - w, cy), (cx - w // 2, cy - h), (cx + w // 2, cy - h),
           (cx + w, cy), (cx + w // 2, cy + h), (cx - w // 2, cy + h)]
    poly(img, pts, base, outline=OUTLINE)
    blend_px(img, cx, cy - h, light)
    blend_px(img, cx - 1, cy, light)
    blend_px(img, cx + 1, cy, (255, 255, 255, 160))


def draw_bar(img, rng, cx, cy, base, light):
    # алюминий: узкая рифлёная пластина-брусок с двумя заклёпками —
    # силуэт вытянутый и плоский, принципиально не круглый и не гранёный
    vertical = rng.random() < 0.5
    if vertical:
        x0, y0, x1, y1 = cx - 1, cy - 4, cx + 1, cy + 4
    else:
        x0, y0, x1, y1 = cx - 4, cy - 1, cx + 4, cy + 1
    rect(img, x0, y0, x1, y1, base)
    line(img, [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], OUTLINE, 1)
    if vertical:
        line(img, [(x0 + 1, y0), (x0 + 1, y1)], light, 1)
        blend_px(img, cx, cy - 2, shade(base, 0.7))
        blend_px(img, cx, cy + 2, shade(base, 0.7))
    else:
        line(img, [(x0, y0 + 1), (x1, y0 + 1)], light, 1)
        blend_px(img, cx - 2, cy, shade(base, 0.7))
        blend_px(img, cx + 2, cy, shade(base, 0.7))


def draw_bead(img, rng, cx, cy, base, accent):
    # ртуть — жидкий металл: каплевидный силуэт со спутником-брызгом рядом
    # явно читается как "жидкость", не как ещё один круглый самородок
    # (с которым её иначе легко перепутать издали)
    poly(img, [(cx - 2, cy - 1), (cx - 1, cy - 2), (cx + 1, cy - 2), (cx + 2, cy - 1),
               (cx + 1, cy + 2), (cx, cy + 3), (cx - 1, cy + 2)], base, outline=OUTLINE)
    dx, dy = rng.choice([(-3, 2), (3, 2), (-3, -1), (3, -1)])
    ellipse(img, cx + dx, cy + dy, 1, 1, base, outline=OUTLINE)
    blend_px(img, cx - 1, cy - 1, (255, 255, 255, 235))
    blend_px(img, cx, cy - 1, (255, 255, 255, 150))
    blend_px(img, cx, cy + 2, accent)


def draw_glow(img, rng, cx, cy, core, glow):
    halo = [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, -1), (-1, 1), (1, 1),
            (-2, -1), (2, 1)]
    for dx, dy in halo:
        blend_px(img, cx + dx, cy + dy, (glow[0], glow[1], glow[2], 70))
    ellipse(img, cx, cy, 2, 2, core, outline=OUTLINE)
    blend_px(img, cx, cy, glow)
    blend_px(img, cx - 1, cy, shade(glow, 0.8))


def draw_debris(img, rng, cx, cy, base, rust):
    # металлолом: погнутая пластина с заклёпками и пятном ржавчины — явно
    # рукотворный хлам, крупнее и контрастнее соседних руд, чтобы не
    # сливаться с фоновым камнем того же серого тона
    rect(img, cx - 3, cy - 2, cx + 3, cy + 2, base)
    line(img, [(cx - 3, cy - 2), (cx + 3, cy - 2), (cx + 3, cy + 2),
               (cx - 3, cy + 2), (cx - 3, cy - 2)], OUTLINE, 1)
    blend_px(img, cx - 3, cy - 2, shade(base, 1.5))
    blend_px(img, cx - 2, cy - 1, shade(base, 1.3))
    rect(img, cx - 1, cy - 1, cx + 1, cy + 1, rust)
    ellipse(img, cx - 2, cy + 1, 0, 0, OUTLINE)
    blend_px(img, cx - 2, cy + 1, (20, 20, 22, 255))
    blend_px(img, cx + 2, cy - 1, (20, 20, 22, 255))
    if rng.random() < 0.6:
        ellipse(img, cx + 4, cy + 3, 1, 1, rust, outline=OUTLINE)


def draw_ore_tile(key, ru, base_key, light_key, style):
    img = canvas(TILE, TILE)
    rng = random.Random(f"ore_{key}")
    # фон-порода: нейтральный камень с лёгким затемнением понизу
    fill_dither(img, C("stone_base"), C("stone_shadow"), rng, prob=0.30)
    base = C(base_key)
    light = C(light_key)
    positions = []
    attempts = 0
    count = {
        "nugget": 5, "nugget_sparkle": 5, "chunk": 4, "chunk_dull": 4,
        "chunk_sparkle": 4, "crystal_sparkle": 4, "fiber": 6, "bead": 3,
        "glow": 3, "debris": 4, "ingot": 3, "pebble_cluster": 4,
        "facet": 4, "bar": 3,
    }[style]
    while len(positions) < count and attempts < 60:
        attempts += 1
        x, y = rng.randint(4, TILE - 5), rng.randint(4, TILE - 5)
        if all(abs(x - px) + abs(y - py) > 3 for px, py in positions):
            positions.append((x, y))

    for (x, y) in positions:
        if style == "nugget":
            draw_nugget(img, rng, x, y, base, light)
        elif style == "nugget_sparkle":
            draw_nugget(img, rng, x, y, base, light)
        elif style == "chunk":
            draw_nugget(img, rng, x, y, base, light, angular=True)
        elif style == "chunk_dull":
            draw_nugget(img, rng, x, y, base, light, angular=True, shine=False)
        elif style == "chunk_sparkle":
            draw_nugget(img, rng, x, y, base, light, angular=True)
        elif style == "crystal_sparkle":
            draw_crystal(img, rng, x, y, base, light)
        elif style == "fiber":
            draw_fiber(img, rng, x, y, base, light)
        elif style == "bead":
            draw_bead(img, rng, x, y, base, light)
        elif style == "glow":
            draw_glow(img, rng, x, y, base, light)
        elif style == "debris":
            draw_debris(img, rng, x, y, base, light)
        elif style == "ingot":
            draw_ingot(img, rng, x, y, base, light)
        elif style == "pebble_cluster":
            draw_pebble_cluster(img, rng, x, y, base, light)
        elif style == "facet":
            draw_facet(img, rng, x, y, base, light)
        elif style == "bar":
            draw_bar(img, rng, x, y, base, light)

    if style in ("nugget_sparkle", "chunk_sparkle", "crystal_sparkle", "facet"):
        for _ in range(2):
            x, y = rng.randint(3, TILE - 4), rng.randint(3, TILE - 4)
            blend_px(img, x, y, light)

    save(img, f"tiles/ore_{key}.png")


def gen_tiles():
    draw_empty_tile()
    for i, seed in enumerate(["dirt_a", "dirt_b", "dirt_c", "dirt_d"], start=1):
        draw_dirt_tile(i, seed)
    draw_stone_tile()
    draw_foundation_tile()
    for key, ru, base_key, light_key, style in ORES:
        draw_ore_tile(key, ru, base_key, light_key, style)


# --------------------------------------------------------------------------
# ПЕРСОНАЖ — кадр 32×48
# --------------------------------------------------------------------------

FW, FH = 32, 48


def draw_character(pose):
    """pose: словарь смещений частей тела, см. вызовы ниже."""
    img = canvas(FW, FH)
    cx = FW // 2

    leg_l_dx = pose.get("leg_l_dx", 0)
    leg_r_dx = pose.get("leg_r_dx", 0)
    leg_l_dy = pose.get("leg_l_dy", 0)
    leg_r_dy = pose.get("leg_r_dy", 0)
    arm_l = pose.get("arm_l", (0, 0))
    arm_r = pose.get("arm_r", (0, 0))
    body_dy = pose.get("body_dy", 0)
    head_dx = pose.get("head_dx", 0)
    tool = pose.get("tool")  # 'shovel' | 'pickaxe' | None
    eyes_closed = pose.get("eyes_closed", False)
    zzz = pose.get("zzz", False)

    top = 4 + body_dy

    # ноги (рисуем первыми, торс перекроет верх бёдер)
    leg_y0 = top + 24
    leg_y1 = top + 36
    rect(img, cx - 6 + leg_l_dx, leg_y0 + leg_l_dy, cx - 2 + leg_l_dx, leg_y1 + leg_l_dy, C("pants"))
    rect(img, cx - 6 + leg_l_dx, leg_y0 + leg_l_dy, cx - 5 + leg_l_dx, leg_y1 + leg_l_dy, C("pants_shadow"))
    rect(img, cx + 2 + leg_r_dx, leg_y0 + leg_r_dy, cx + 6 + leg_r_dx, leg_y1 + leg_r_dy, C("pants"))
    rect(img, cx + 5 + leg_r_dx, leg_y0 + leg_r_dy, cx + 6 + leg_r_dx, leg_y1 + leg_r_dy, C("pants_shadow"))
    # ступни
    rect(img, cx - 7 + leg_l_dx, leg_y1 + leg_l_dy, cx - 1 + leg_l_dx, leg_y1 + leg_l_dy + 3, C("shoe"))
    rect(img, cx + 1 + leg_r_dx, leg_y1 + leg_r_dy, cx + 7 + leg_r_dx, leg_y1 + leg_r_dy + 3, C("shoe"))

    # руки (за торсом)
    for side, (adx, ady) in (("l", arm_l), ("r", arm_r)):
        sign = -1 if side == "l" else 1
        ax0 = cx + sign * 9 + adx
        ax1 = cx + sign * 6 + adx
        ay0 = top + 12 + ady
        ay1 = top + 23 + ady
        lo, hi = (ax0, ax1) if ax0 < ax1 else (ax1, ax0)
        rect(img, lo, ay0, hi, ay1, C("shirt_shadow"))
        rect(img, lo, ay1 - 3, hi, ay1, C("skin"))  # кисть

    # торс
    rect(img, cx - 6, top + 11, cx + 6, top + 25, C("shirt"))
    rect(img, cx - 6, top + 11, cx - 4, top + 25, C("shirt_shadow"))
    rect(img, cx - 6, top + 23, cx + 6, top + 25, C("shirt_shadow"))

    # голова
    hx = cx + head_dx
    rect(img, hx - 5, top - 4, hx + 5, top + 6, C("skin"))
    rect(img, hx - 5, top - 4, hx - 3, top + 6, C("skin_shadow"))
    # волосы (чёлка + затылок)
    rect(img, hx - 6, top - 6, hx + 6, top - 2, C("hair"))
    rect(img, hx - 6, top - 6, hx + 6, top - 4, C("hair"))
    rect(img, hx + 4, top - 4, hx + 6, top + 3, C("hair"))
    # лицо
    if not eyes_closed:
        blend_px(img, hx - 2, top, C("eye_dark"))
        blend_px(img, hx + 2, top, C("eye_dark"))
    else:
        blend_px(img, hx - 3, top, C("eye_dark"))
        blend_px(img, hx - 2, top, C("eye_dark"))
        blend_px(img, hx + 1, top, C("eye_dark"))
        blend_px(img, hx + 2, top, C("eye_dark"))
    blend_px(img, hx, top + 3, C("skin_shadow"))

    # инструмент в руках
    if tool == "shovel":
        hx2 = cx + arm_r[0] + 6
        hy2 = top + 22 + arm_r[1]
        line(img, [(hx2, hy2), (hx2 + 8, hy2 - 14)], C("wood"), 2)
        poly(img, [(hx2 + 7, hy2 - 17), (hx2 + 12, hy2 - 14), (hx2 + 9, hy2 - 9)], C("steel_blue"))
    elif tool == "pickaxe":
        hx2 = cx + arm_r[0] + 6
        hy2 = top + 22 + arm_r[1]
        line(img, [(hx2, hy2), (hx2 + 7, hy2 - 15)], C("wood"), 2)
        poly(img, [(hx2 + 2, hy2 - 18), (hx2 + 12, hy2 - 15), (hx2 + 2, hy2 - 12)], C("rust_tool"))

    # пропеллерный ранец / джетпак на спине (для fly)
    if pose.get("backpack"):
        bx = cx - 2
        by = top + 12
        rect(img, bx - 3, by, bx + 3, by + 10, C("wood_dark"))
        for ddx, blade in ((-3, pose.get("blade", 0)), (3, pose.get("blade", 0))):
            pcx = bx + ddx
            pcy = by - 1
            if blade == 0:
                line(img, [(pcx - 3, pcy), (pcx + 3, pcy)], C("stone_light", 180), 1)
            else:
                line(img, [(pcx - 2, pcy - 2), (pcx + 2, pcy + 2)], C("stone_light", 180), 1)
            ellipse(img, pcx, pcy, 1, 1, C("steel_blue"))

    if zzz:
        blend_px(img, hx + 6, top - 8, C("void_rim", 255))
        blend_px(img, hx + 7, top - 9, C("void_rim", 255))
        blend_px(img, hx + 8, top - 10, C("void_rim", 255))

    return img


def strip(frames):
    w = FW * len(frames)
    sheet = canvas(w, FH)
    for i, f in enumerate(frames):
        sheet.paste(f, (i * FW, 0), f)
    return sheet


def gen_character():
    # покой — лёгкое дыхание
    idle = [draw_character({"body_dy": 0}), draw_character({"body_dy": 1})]
    save(strip(idle), "character/idle.png")

    # ходьба — контрапост ног/рук, 4 кадра
    walk = [
        draw_character({"leg_l_dx": -1, "leg_r_dx": 1, "arm_l": (1, -1), "arm_r": (-1, 1)}),
        draw_character({"body_dy": -1}),
        draw_character({"leg_l_dx": 1, "leg_r_dx": -1, "arm_l": (-1, 1), "arm_r": (1, -1)}),
        draw_character({"body_dy": -1}),
    ]
    save(strip(walk), "character/walk.png")

    # копка лопатой — замах и удар
    dig_shovel = [
        draw_character({"arm_r": (2, -6), "arm_l": (0, -2), "tool": "shovel", "body_dy": -1}),
        draw_character({"arm_r": (4, -2), "arm_l": (0, 0), "tool": "shovel"}),
        draw_character({"arm_r": (3, 4), "arm_l": (0, 1), "tool": "shovel", "body_dy": 1}),
        draw_character({"arm_r": (1, 1), "arm_l": (0, 0), "tool": "shovel"}),
    ]
    save(strip(dig_shovel), "character/dig_shovel.png")

    # копка киркой
    dig_pick = [
        draw_character({"arm_r": (1, -8), "arm_l": (0, -3), "tool": "pickaxe", "body_dy": -1}),
        draw_character({"arm_r": (3, -3), "arm_l": (0, 0), "tool": "pickaxe"}),
        draw_character({"arm_r": (5, 3), "arm_l": (0, 1), "tool": "pickaxe", "body_dy": 1}),
        draw_character({"arm_r": (2, 1), "arm_l": (0, 0), "tool": "pickaxe"}),
    ]
    save(strip(dig_pick), "character/dig_pick.png")

    # падение — руки вверх, ноги поджаты
    fall = [draw_character({"arm_l": (-2, -4), "arm_r": (2, -4), "leg_l_dx": 1, "leg_r_dx": -1,
                             "leg_l_dy": -2, "leg_r_dy": -2})]
    save(strip(fall), "character/fall.png")

    # полёт с ранцем — 2 кадра лопастей
    fly = [
        draw_character({"backpack": True, "blade": 0, "leg_l_dx": 0, "leg_r_dx": 0,
                         "leg_l_dy": -3, "leg_r_dy": -3, "arm_l": (-1, -2), "arm_r": (1, -2)}),
        draw_character({"backpack": True, "blade": 1, "leg_l_dx": 0, "leg_r_dx": 0,
                         "leg_l_dy": -3, "leg_r_dy": -3, "arm_l": (-1, -2), "arm_r": (1, -2)}),
    ]
    save(strip(fly), "character/fly.png")

    # сон — стоя, глаза закрыты, zzz (анимация пропускается по ГДД, кадр один)
    sleep = [draw_character({"eyes_closed": True, "zzz": True, "head_dx": -1, "body_dy": 1})]
    save(strip(sleep), "character/sleep.png")


# --------------------------------------------------------------------------
# ПРЕДМЕТЫ 32×32
# --------------------------------------------------------------------------

def item_canvas():
    return canvas(TILE, TILE)


def draw_shovel():
    img = item_canvas()
    # черенок с Т-образной рукоятью наверху — силуэт однозначно "лопата"
    line(img, [(10, 27), (18, 10)], C("wood"), 2)
    blend_px(img, 10, 27, C("wood_dark"))
    line(img, [(15, 8), (21, 11)], C("wood"), 2)
    # широкий совок с заострённым носком и ребром жёсткости
    poly(img, [(16, 8), (26, 11), (24, 21), (18, 26), (12, 19)], C("steel_blue"))
    line(img, [(16, 8), (26, 11), (24, 21), (18, 26), (12, 19), (16, 8)], OUTLINE, 1)
    poly(img, [(16, 8), (26, 11), (22, 13), (17, 11)], (255, 255, 255, 70))
    line(img, [(18, 12), (19, 22)], shade(C("steel_blue"), 0.7), 1)
    save(img, "items/shovel.png")


def _pickaxe_head(img, base, cracked=False):
    # крестовидный оголовок кирки: два сужающихся к концам клина от
    # места насадки на черенок — читается как "кирка", а не ромб/флаг
    hinge = (17, 13)
    if not cracked:
        pts = [hinge, (12, 8), (5, 15), (11, 17),
               hinge, (23, 5), (29, 9), (22, 16)]
        poly(img, pts, base, outline=OUTLINE)
        blend_px(img, 8, 12, (255, 255, 255, 60))
        blend_px(img, 24, 8, (255, 255, 255, 90))
    else:
        # левый клин цел, правый — треснул и отвалился отдельным осколком
        left = [hinge, (12, 8), (5, 15), (11, 17)]
        poly(img, left, shade(base, 0.85), outline=OUTLINE)
        stub = [hinge, (21, 8), (18, 15)]
        poly(img, stub, shade(base, 0.7), outline=OUTLINE)
        shard = [(25, 6), (30, 9), (26, 14), (22, 11)]
        poly(img, shard, shade(base, 0.6), outline=OUTLINE)
        # трещина, разбегающаяся от места скола
        line(img, [(19, 10), (16, 13), (18, 16)], C("silver_base"), 1)
        blend_px(img, 19, 10, (255, 255, 255, 210))
        blend_px(img, 8, 12, (255, 255, 255, 40))
    return hinge


def _pickaxe(color_key, cracked=False):
    img = item_canvas()
    hinge = _pickaxe_head(img, C(color_key), cracked)
    line(img, [(9, 27), hinge], C("wood"), 2)
    blend_px(img, 9, 27, C("wood_dark"))
    return img


def draw_pickaxe_rusty():
    save(_pickaxe("rust_tool", False), "items/pickaxe_rusty.png")


def draw_pickaxe_rusty_cracked():
    save(_pickaxe("rust_tool", True), "items/pickaxe_rusty_cracked.png")


def draw_pickaxe_iron():
    save(_pickaxe("iron_tool", False), "items/pickaxe_iron.png")


def draw_hand_drill():
    # ручной бур-мотобур: моторный блок с боковой рукоятью для упора и
    # длинный винтовой шнек, торчащий вперёд — силуэт мгновенно читается
    # как электроинструмент, а не как непонятная клякса
    img = item_canvas()
    # боковая упорная рукоять слева
    rect(img, 2, 17, 9, 20, C("wood_dark"))
    ellipse(img, 3, 18, 1, 1, (255, 255, 255, 50))
    # корпус мотора — гранёный кожух с вентиляционными рёбрами
    rect(img, 8, 12, 20, 23, C("steel_blue"))
    rect(img, 8, 12, 20, 14, shade(C("steel_blue"), 1.3))
    for y in (16, 18, 20):
        line(img, [(9, y), (14, y)], C("stone_shadow"), 1)
    blend_px(img, 9, 13, (255, 255, 255, 90))
    # пистолетная рукоять снизу с курком
    rect(img, 10, 23, 14, 29, C("wood_dark"))
    blend_px(img, 11, 25, C("wood"))
    # патрон-цанга, из которого выходит бур
    rect(img, 19, 14, 24, 20, shade(C("steel_blue"), 0.8))
    # винтовой шнек по прямой вправо-вверх — чередующиеся витки читаются
    # как резьба сверла, а не как случайные штрихи
    bx, by = 23, 16
    for i in range(6):
        x = bx + i * 2
        y = by - i * 2
        w = max(1, 4 - i // 2)
        c = C("iron_tool") if i % 2 == 0 else shade(C("iron_tool"), 0.7)
        line(img, [(x, y + w), (x + 3, y - w)], c, 2)
    poly(img, [(x + 2, y - w - 1), (x + 6, y - 2), (x + 3, y + 1)], C("silver_light"))
    blend_px(img, x + 5, y - 3, (255, 255, 255, 220))
    save(img, "items/hand_drill.png")


def _prop_disc(img, cx, cy, color):
    """Пропеллер как плоский диск размытия вращения — читается однозначно,
    в отличие от тонких лопастей, которые на 32×32 превращаются в кашу."""
    ellipse(img, cx, cy, 5, 2, color, outline=OUTLINE)
    blend_px(img, cx - 3, cy, (255, 255, 255, 90))
    ellipse(img, cx, cy, 1, 1, C("iron_tool"), outline=OUTLINE)


def draw_backpack_propeller():
    img = item_canvas()
    # скруглённый рюкзак-мешок вместо ящика — форма явно "носимая"
    poly(img, [(10, 13), (21, 13), (23, 16), (23, 25), (19, 28), (12, 28),
               (8, 25), (8, 16)], C("wood"))
    poly(img, [(10, 13), (8, 16), (8, 25), (12, 28), (12, 15)], C("wood_dark"))
    # клапан сверху и передний карман с пряжкой — читается как рюкзак,
    # а не как бочка с обручами
    rect(img, 9, 13, 22, 16, shade(C("wood"), 1.2))
    rect(img, 12, 19, 19, 25, shade(C("wood"), 0.82))
    line(img, [(12, 19), (19, 19), (19, 25), (12, 25), (12, 19)], C("wood_dark"), 1)
    ellipse(img, 15, 21, 1, 1, C("iron_tool"))
    # плечевые лямки
    line(img, [(9, 15), (5, 11)], C("hair"), 2)
    line(img, [(22, 15), (26, 11)], C("hair"), 2)
    # две мачты с дисками пропеллеров наверху, разнесённые в стороны,
    # чтобы силуэты не сливались в один
    for cx in (10, 21):
        line(img, [(cx, 13), (cx, 7)], C("stone_shadow"), 2)
        _prop_disc(img, cx, 5, C("stone_light"))
    save(img, "items/backpack_propeller.png")


def draw_jetpack():
    img = item_canvas()
    # корпус баллона сужается кверху — читается как реактивный ранец
    poly(img, [(11, 6), (21, 6), (24, 10), (24, 24), (20, 27), (12, 27),
               (8, 24), (8, 10)], C("iron_tool"))
    poly(img, [(11, 6), (8, 10), (8, 24), (12, 27), (12, 8)], C("steel_blue"))
    rect(img, 19, 9, 22, 24, C("steel_blue"))
    blend_px(img, 12, 9, (255, 255, 255, 70))
    line(img, [(13, 12), (18, 12)], C("stone_shadow"), 1)
    line(img, [(13, 16), (18, 16)], C("stone_shadow"), 1)
    line(img, [(13, 20), (18, 20)], C("stone_shadow"), 1)
    # плечевые лямки
    line(img, [(10, 8), (4, 13)], C("hair"), 2)
    line(img, [(22, 8), (28, 13)], C("hair"), 2)
    # сопла снизу с пламенем
    rect(img, 9, 25, 13, 29, C("stone_shadow"))
    rect(img, 18, 25, 22, 29, C("stone_shadow"))
    poly(img, [(9, 29), (13, 29), (11, 32)], C("gold_light"))
    poly(img, [(18, 29), (22, 29), (20, 32)], C("gold_light"))
    ellipse(img, 11, 27, 1, 1, C("gold_light"))
    ellipse(img, 20, 27, 1, 1, C("gold_light"))
    save(img, "items/jetpack.png")


def draw_mercury_bottle():
    # герметичная металлическая фляга с круглым смотровым окошком — внутри
    # видна тяжёлая блестящая жидкость. Круглый иллюминатор в нижней трети
    # (а не окно во всю переднюю грань) не даёт силуэту читаться как лицо.
    img = item_canvas()
    body = [(11, 9), (21, 9), (24, 14), (24, 24), (20, 27), (12, 27), (8, 24), (8, 14)]
    poly(img, body, C("steel_blue"), outline=OUTLINE)
    poly(img, [(11, 9), (8, 14), (8, 24), (12, 27), (12, 11)], shade(C("steel_blue"), 0.75))
    # горлышко с завинченной пробкой
    rect(img, 13, 4, 19, 9, C("iron_tool"))
    line(img, [(13, 4), (19, 4)], (255, 255, 255, 70), 1)
    rect(img, 12, 3, 20, 5, shade(C("iron_tool"), 0.8))
    # круглый иллюминатор, залитый ртутью до краёв (жидкость тяжёлая,
    # заполняет сосуд плотно) — читается как "смотровое окно", не как лицо
    ellipse(img, 16, 19, 6, 6, shade(C("steel_blue"), 0.55), outline=OUTLINE)
    ellipse(img, 16, 19, 5, 5, C("mercury_base"), outline=OUTLINE)
    ellipse(img, 16, 17, 4, 2, shade(C("mercury_base"), 1.35))
    blend_px(img, 14, 17, (255, 255, 255, 235))
    blend_px(img, 15, 17, (255, 255, 255, 235))
    blend_px(img, 13, 18, (255, 255, 255, 150))
    ellipse(img, 18, 21, 1, 1, C("mercury_accent"))
    # капля, просочившаяся наружу снизу — намёк на опасную утечку
    ellipse(img, 10, 29, 1, 2, C("mercury_base"), outline=OUTLINE)
    blend_px(img, 10, 28, (255, 255, 255, 200))
    save(img, "items/mercury_bottle.png")


def draw_uranium_container():
    img = item_canvas()
    rect(img, 6, 9, 25, 25, C("hatch"))
    rect(img, 6, 9, 25, 11, C("hatch_light"))
    rect(img, 6, 9, 8, 25, shade(C("hatch"), 0.8))
    line(img, [(6, 9), (25, 9), (25, 25), (6, 25), (6, 9)], OUTLINE, 1)
    cells = [(11, 14), (18, 14), (11, 20), (18, 20)]
    for (cx, cy) in cells:
        poly(img, [(cx, cy - 3), (cx + 3, cy - 1), (cx + 3, cy + 1),
                    (cx, cy + 3), (cx - 3, cy + 1), (cx - 3, cy - 1)], C("uranium_glow"))
        blend_px(img, cx, cy, (255, 255, 255, 140))
        for dx, dy in [(-3, -1), (-3, 1), (3, -1), (3, 1), (0, -3), (0, 3)]:
            blend_px(img, cx + dx, cy + dy, (C("uranium_glow")[0], C("uranium_glow")[1],
                                              C("uranium_glow")[2], 60))
    # предупреждающий трилистник радиации — узнаваем без подписи
    rcx, rcy, rr = 24, 22, 3
    ellipse(img, rcx, rcy, rr, rr, C("gold_base"), outline=OUTLINE)
    for a in (90, 210, 330):
        x = rcx + math.cos(math.radians(a)) * 1.6
        y = rcy + math.sin(math.radians(a)) * 1.6
        blend_px(img, int(x), int(y), (20, 20, 20, 255))
    blend_px(img, rcx, rcy, (20, 20, 20, 255))
    save(img, "items/uranium_container.png")


def gen_items():
    draw_shovel()
    draw_pickaxe_rusty()
    draw_pickaxe_rusty_cracked()
    draw_pickaxe_iron()
    draw_hand_drill()
    draw_backpack_propeller()
    draw_jetpack()
    draw_mercury_bottle()
    draw_uranium_container()


# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------

def draw_icon_heart():
    img = item_canvas()
    poly(img, [(16, 10), (22, 6), (28, 12), (16, 26), (4, 12), (10, 6)], C("heart"))
    blend_px(img, 12, 10, C("heart_light"))
    blend_px(img, 13, 9, C("heart_light"))
    save(img, "ui/icon_hp.png")


def draw_icon_hunger():
    img = item_canvas()
    base = C("stomach_base")
    lite = C("stomach_light")
    fold = C("stomach_fold")

    # Силуэт собран из трёх пересекающихся масс: свод сверху слева, тело
    # справа, привратник снизу. Между сводом и привратником слева остаётся
    # незакрашенный выем — это малая кривизна, по ней желудок и узнаётся.
    parts = [(15, 10, 7, 6), (21, 17, 8, 10), (15, 24, 7, 5)]
    for cx, cy, rx, ry in parts:
        ellipse(img, cx, cy, rx, ry, base, outline=OUTLINE)
    line(img, [(12, 2), (14, 7)], base, 5)      # пищевод
    line(img, [(11, 27), (4, 29)], base, 5)     # выход в двенадцатиперстную
    # те же массы на пиксель меньше и без обводки — убирают внутренние швы
    for cx, cy, rx, ry in parts:
        ellipse(img, cx, cy, rx - 1, ry - 1, base)
    line(img, [(12, 3), (14, 7)], base, 3)
    line(img, [(11, 27), (5, 29)], base, 3)

    # малая кривизна и свод светлее — как на анатомических схемах
    ellipse(img, 14, 10, 5, 4, lite)
    line(img, [(13, 14), (14, 19), (16, 23)], lite, 2)

    # складки слизистой на теле
    line(img, [(20, 11), (22, 13), (20, 15)], fold, 1)
    line(img, [(24, 13), (26, 15), (24, 17)], fold, 1)
    line(img, [(19, 18), (21, 20), (19, 22)], fold, 1)
    line(img, [(24, 19), (26, 21), (24, 23)], fold, 1)
    line(img, [(17, 25), (19, 26), (17, 27)], fold, 1)

    blend_px(img, 12, 7, (255, 255, 255, 110))
    save(img, "ui/icon_hunger.png")


def draw_icon_stamina():
    img = item_canvas()
    # молния собрана из двух простых (несамопересекающихся) треугольников
    poly(img, [(18, 4), (10, 17), (17, 17)], C("stamina"))
    poly(img, [(17, 17), (22, 12), (13, 28)], C("stamina"))
    blend_px(img, 17, 6, (255, 255, 255, 200))
    blend_px(img, 15, 24, (255, 255, 255, 160))
    save(img, "ui/icon_stamina.png")


def draw_icon_coin():
    img = item_canvas()
    ellipse(img, 16, 16, 10, 10, C("coin"))
    ellipse(img, 16, 16, 7, 7, shade(C("coin"), 0.85))
    blend_px(img, 12, 11, C("coin_light"))
    blend_px(img, 13, 10, C("coin_light"))
    save(img, "ui/icon_coin.png")


def draw_icon_dollar():
    img = item_canvas()
    rect(img, 6, 10, 26, 22, C("dollar"))
    rect(img, 6, 10, 26, 12, shade(C("dollar"), 1.15))
    rect(img, 6, 20, 26, 22, shade(C("dollar"), 0.8))
    line(img, [(16, 12), (16, 20)], C("dollar_light"), 1)
    line(img, [(12, 14), (20, 14)], C("dollar_light"), 1)
    line(img, [(12, 18), (20, 18)], C("dollar_light"), 1)
    save(img, "ui/icon_dollar.png")


def draw_icon_inventory():
    img = item_canvas()
    rect(img, 6, 12, 26, 25, C("wood"))
    rect(img, 6, 12, 26, 15, C("wood_dark"))
    rect(img, 13, 8, 19, 12, C("wood_dark"))
    blend_px(img, 8, 14, (255, 255, 255, 60))
    line(img, [(6, 18), (26, 18)], C("stone_shadow"), 1)
    save(img, "ui/icon_inventory.png")


def draw_icon_blackbox():
    img = item_canvas()
    rect(img, 6, 10, 26, 24, C("blackbox_body"))
    rect(img, 6, 10, 26, 13, shade(C("blackbox_body"), 1.4))
    ellipse(img, 22, 12, 1, 1, C("blackbox_light"))
    rect(img, 13, 15, 19, 19, C("stone_light"))
    blend_px(img, 16, 17, C("blackbox_body"))
    save(img, "ui/icon_blackbox.png")


def draw_icon_depth():
    img = item_canvas()
    line(img, [(16, 5), (16, 23)], C("stone_light"), 2)
    poly(img, [(10, 20), (22, 20), (16, 28)], C("stone_light"))
    for y in (9, 14, 19):
        line(img, [(11, y), (14, y)], C("void_rim", 220), 1)
    save(img, "ui/icon_depth.png")


def draw_panel_9slice():
    w = h = 48
    img = canvas(w, h)
    rect(img, 0, 0, w - 1, h - 1, C("parchment_border"))
    rect(img, 4, 4, w - 5, h - 5, C("parchment"))
    rng = random.Random("panel")
    fill_dither(img, C("parchment"), shade(C("parchment"), 0.94), rng, prob=0.25,
                x0=5, y0=5, x1=w - 5, y1=h - 5)
    for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        blend_px(img, x, y, (0, 0, 0, 0))
    rect(img, 1, 1, w - 2, 1, shade(C("parchment_border"), 1.3))
    rect(img, 1, 1, 1, h - 2, shade(C("parchment_border"), 1.3))
    save(img, "ui/panel_9slice.png")


def draw_slot_frame():
    img = canvas(TILE, TILE)
    rect(img, 0, 0, TILE - 1, TILE - 1, C("slot_border"))
    rect(img, 2, 2, TILE - 3, TILE - 3, C("ui_dark_bg"))
    for (x0, y0, x1, y1) in [(0, 0, 3, 0), (0, 0, 0, 3), (TILE - 4, 0, TILE - 1, 0),
                              (TILE - 1, 0, TILE - 1, 3), (0, TILE - 1, 3, TILE - 1),
                              (0, TILE - 4, 0, TILE - 1), (TILE - 4, TILE - 1, TILE - 1, TILE - 1),
                              (TILE - 1, TILE - 4, TILE - 1, TILE - 1)]:
        line(img, [(x0, y0), (x1, y1)], shade(C("slot_border"), 1.5), 1)
    save(img, "ui/slot_frame.png")


def gen_ui():
    draw_icon_heart()
    draw_icon_hunger()
    draw_icon_stamina()
    draw_icon_coin()
    draw_icon_dollar()
    draw_icon_inventory()
    draw_icon_blackbox()
    draw_icon_depth()
    draw_panel_9slice()
    draw_slot_frame()


# --------------------------------------------------------------------------
# ОКРУЖЕНИЕ
# --------------------------------------------------------------------------

def draw_house_exterior():
    w, h = 128, 112
    img = canvas(w, h)
    rng = random.Random("house")
    # стена
    fill_dither(img, C("wall"), shade(C("wall"), 0.94), rng, prob=0.2,
                x0=12, y0=40, x1=w - 12, y1=h - 10)
    rect(img, 12, 40, w - 13, h - 11, C("wall"))
    rect(img, 12, 40, 14, h - 11, C("wall_dark"))
    # крыша
    poly(img, [(6, 42), (w // 2, 8), (w - 6, 42)], C("roof"))
    poly(img, [(6, 42), (w // 2, 8), (w // 2, 12), (10, 42)], shade(C("roof"), 1.15))
    rect(img, w // 2 - 2, 4, w // 2 + 2, 14, C("roof_dark"))  # труба
    # дверь
    rect(img, w // 2 - 8, h - 34, w // 2 + 8, h - 11, C("wood_dark"))
    rect(img, w // 2 - 8, h - 34, w // 2 + 8, h - 11, C("wood"))
    for i in range(3):
        line(img, [(w // 2 - 8, h - 34 + i * 8), (w // 2 + 8, h - 34 + i * 8)], C("wood_dark"), 1)
    blend_px(img, w // 2 + 5, h - 22, C("gold_light"))
    # окна
    for wx in (26, w - 40):
        rect(img, wx, 54, wx + 16, 70, C("wood_dark"))
        rect(img, wx + 2, 56, wx + 14, 68, C("void_base"))
        line(img, [(wx + 8, 56), (wx + 8, 68)], C("wood_dark"), 1)
        line(img, [(wx + 2, 62), (wx + 14, 62)], C("wood_dark"), 1)
        blend_px(img, wx + 4, 58, C("void_rim", 200))
    # трава у основания
    rect(img, 0, h - 10, w, h, C("grass_field"))
    for _ in range(20):
        x = rng.randint(0, w - 1)
        line(img, [(x, h - 10), (x, h - 10 - rng.randint(2, 5))], C("grass_dark"), 1)
    save(img, "env/house_exterior.png")


def draw_fence():
    img = canvas(TILE, TILE)
    rect(img, 2, 20, TILE - 3, 23, C("wood"))
    rect(img, 2, 14, TILE - 3, 17, C("wood"))
    for x in (4, 12, 20, 27):
        rect(img, x, 4, x + 3, 28, C("wood"))
        rect(img, x, 4, x + 1, 28, C("wood_dark"))
        poly(img, [(x, 4), (x + 3, 4), (x + 1, 1)], C("wood"))
    save(img, "env/fence.png")


def draw_grave():
    img = canvas(TILE, TILE + 8)
    h = TILE + 8
    rect(img, 6, h - 8, TILE - 6, h - 2, C("grass_field"))
    poly(img, [(9, h - 8), (9, 12), (13, 6), (19, 6), (23, 12), (23, h - 8)], C("grave"))
    poly(img, [(9, h - 8), (9, 12), (13, 6), (16, 6), (16, h - 8)], C("grave_shadow"))
    line(img, [(12, 16), (20, 16)], shade(C("grave"), 0.7), 1)
    line(img, [(12, 22), (20, 22)], shade(C("grave"), 0.7), 1)
    save(img, "env/grave.png")


def draw_hatch():
    img = canvas(TILE, TILE)
    rng = random.Random("hatch")
    fill_dither(img, C("soil_base"), C("soil_shadow"), rng, prob=0.3, x0=0, y0=0, x1=TILE, y1=TILE)
    ellipse(img, 16, 17, 13, 10, C("hatch"))
    ellipse(img, 16, 17, 10, 7, shade(C("hatch"), 0.85))
    ellipse(img, 16, 17, 5, 3, C("hatch_light"))
    for a in range(0, 360, 45):
        x = 16 + int(11 * math.cos(math.radians(a)))
        y = 17 + int(8 * math.sin(math.radians(a)))
        blend_px(img, x, y, shade(C("hatch"), 0.6))
    blend_px(img, 12, 13, (255, 255, 255, 70))
    save(img, "env/hatch.png")


def draw_workbench():
    w, h = 48, 32
    img = canvas(w, h)
    rect(img, 4, 10, w - 4, 16, C("wood"))
    rect(img, 4, 10, w - 4, 12, shade(C("wood"), 1.2))
    for x in (8, w - 12):
        rect(img, x, 16, x + 4, h - 2, C("wood_dark"))
    # инструменты на стене/верстаке
    line(img, [(14, 9), (14, 2)], C("wood_dark"), 2)
    poly(img, [(10, 1), (18, 3), (15, 7)], C("steel_blue"))
    ellipse(img, 30, 6, 3, 3, C("iron_tool"))
    rect(img, 22, 4, 26, 9, C("rust_tool"))
    save(img, "env/workbench.png")


def draw_bed():
    w, h = 48, 32
    img = canvas(w, h)
    rect(img, 2, 18, w - 2, h - 4, C("wood_dark"))
    rect(img, 4, 10, w - 4, 20, C("wall"))
    rect(img, 4, 10, 14, 20, (255, 255, 255, 40))
    rect(img, 4, 8, 14, 14, C("wall_dark"))  # подушка
    line(img, [(16, 14), (w - 6, 14)], C("wall_dark"), 1)
    rect(img, 0, h - 6, 6, h, C("wood_dark"))
    rect(img, w - 6, h - 6, w, h, C("wood_dark"))
    save(img, "env/bed.png")


def gen_env():
    draw_house_exterior()
    draw_fence()
    draw_grave()
    draw_hatch()
    draw_workbench()
    draw_bed()


# --------------------------------------------------------------------------
# КОНТАКТНЫЙ ЛИСТ (art/_preview.png)
# --------------------------------------------------------------------------

def _load(rel):
    return Image.open(os.path.join(ART, rel)).convert("RGBA")


_CYRILLIC_FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
]


def _label_font(size=11):
    for path in _CYRILLIC_FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    try:
        return ImageFont.load_default()
    except Exception:
        return None


def _section(title, entries, scale, cols, font):
    """entries: список (подпись, относительный путь к PNG)."""
    imgs = [(_load(p), cap) for cap, p in entries]
    cell_w = max(im.width for im, _ in imgs) * scale + 12
    cell_h = max(im.height for im, _ in imgs) * scale + 22
    rows = math.ceil(len(imgs) / cols)
    header_h = 22
    sheet = Image.new("RGBA", (cell_w * cols, header_h + cell_h * rows), (0, 0, 0, 0))
    d = ImageDraw.Draw(sheet)
    d.rectangle([0, 0, sheet.width - 1, header_h - 1], fill=(40, 34, 30, 255))
    d.text((6, 5), title, font=font, fill=(230, 220, 200, 255))
    for i, (im, cap) in enumerate(imgs):
        col = i % cols
        row = i // cols
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        x = col * cell_w + (cell_w - big.width) // 2
        y = header_h + row * cell_h + 4
        sheet.alpha_composite(big, (x, y))
        tw = d.textlength(cap, font=font) if hasattr(d, "textlength") else len(cap) * 6
        tx = col * cell_w + max(2, (cell_w - int(tw)) // 2)
        ty = header_h + row * cell_h + big.height + 6
        d.text((tx, ty), cap, font=font, fill=(210, 205, 195, 255))
    return sheet


def gen_preview():
    font = _label_font()

    tile_entries = [("empty", "tiles/empty.png")]
    tile_entries += [(f"dirt_{i}", f"tiles/dirt_{i}.png") for i in range(1, 5)]
    tile_entries += [("stone", "tiles/stone.png"), ("foundation", "tiles/foundation.png")]
    tile_entries += [(ru, f"tiles/ore_{key}.png") for key, ru, *_ in ORES]

    char_entries = [
        ("idle", "character/idle.png"), ("walk", "character/walk.png"),
        ("dig_shovel", "character/dig_shovel.png"), ("dig_pick", "character/dig_pick.png"),
        ("fall", "character/fall.png"), ("fly", "character/fly.png"),
        ("sleep", "character/sleep.png"),
    ]

    item_entries = [
        ("shovel", "items/shovel.png"), ("pick_rusty", "items/pickaxe_rusty.png"),
        ("pick_rusty_cracked", "items/pickaxe_rusty_cracked.png"),
        ("pick_iron", "items/pickaxe_iron.png"), ("hand_drill", "items/hand_drill.png"),
        ("backpack", "items/backpack_propeller.png"), ("jetpack", "items/jetpack.png"),
        ("mercury_bottle", "items/mercury_bottle.png"),
        ("uranium_container", "items/uranium_container.png"),
    ]

    ui_entries = [
        ("hp", "ui/icon_hp.png"), ("hunger", "ui/icon_hunger.png"),
        ("stamina", "ui/icon_stamina.png"), ("coin", "ui/icon_coin.png"),
        ("dollar", "ui/icon_dollar.png"), ("inventory", "ui/icon_inventory.png"),
        ("blackbox", "ui/icon_blackbox.png"), ("depth", "ui/icon_depth.png"),
        ("panel_9slice", "ui/panel_9slice.png"), ("slot_frame", "ui/slot_frame.png"),
    ]

    env_entries = [
        ("house", "env/house_exterior.png"), ("fence", "env/fence.png"),
        ("grave", "env/grave.png"), ("hatch", "env/hatch.png"),
        ("workbench", "env/workbench.png"), ("bed", "env/bed.png"),
    ]

    sections = [
        _section(f"ТАЙЛЫ ({len(tile_entries)})", tile_entries, 3, 8, font),
        _section(f"ПЕРСОНАЖ ({len(char_entries)} листов анимаций)", char_entries, 2, 3, font),
        _section(f"ПРЕДМЕТЫ ({len(item_entries)})", item_entries, 3, 5, font),
        _section(f"UI ({len(ui_entries)})", ui_entries, 3, 5, font),
        _section(f"ОКРУЖЕНИЕ ({len(env_entries)})", env_entries, 2, 4, font),
    ]

    width = max(s.width for s in sections)
    total_h = sum(s.height for s in sections) + 40
    canvas_img = Image.new("RGBA", (width, total_h), (24, 20, 18, 255))
    d = ImageDraw.Draw(canvas_img)
    d.text((8, 6), "Раскопки на каникулах — превью арт-плейсхолдеров", font=font,
           fill=(240, 230, 210, 255))
    y = 26
    for s in sections:
        canvas_img.alpha_composite(s, (0, y))
        y += s.height
    canvas_img.save(os.path.join(ART, "_preview.png"))


# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------

def main():
    os.makedirs(ART, exist_ok=True)
    write_palette_doc()
    gen_tiles()
    gen_character()
    gen_items()
    gen_ui()
    gen_env()
    gen_preview()

    count = 0
    for r, _, files in os.walk(ART):
        count += len([f for f in files if f.lower().endswith(".png")])
    print(f"Готово. PNG-файлов создано: {count}")
    print(f"Цветов в палитре: {len(PALETTE)}")
    print(f"art/_preview.png и art/PALETTE.md обновлены.")


if __name__ == "__main__":
    main()
