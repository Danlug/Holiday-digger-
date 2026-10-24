#!/usr/bin/env python3
"""gen_hero_icons.py — иконки экрана героя 16×16 → art/ui/hero/<имя>.png.

Вкладки (шлем, узлы навыков, амфора, крестик), ветки прокачки (глаз, кирка,
сердце, молния, окорок, гиря, подкова, клевер, пламя жадности), служебные значки (замок,
галочка, звезда, глубина, самоцвет, рюкзак, монета, кубок, сундук) и пять
самоцветов-гнёзд Перчатки Мироздания.

Это заглушки уровня «программист нарисовал аккуратно» (как и артефакты, см.
tools/gen_artifact_art.py): обводка 1 пиксель, три тона на материал, без
антиалиасинга. Художник может заменить PNG под теми же именами.

Запуск:   python3 tools/gen_hero_icons.py [--sheet out.png]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pix import Spr, hexc, rot, shift, tint, contact_sheet  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "ui", "hero")
C = hexc
OUT = C("#1c1410")

GOLD = C("#e8b32e")
GOLD_L = C("#ffe066")
GOLD_D = C("#a8741c")
RED = C("#d23a4a")
GREEN = C("#58c26a")
TEAL = C("#3fb7c8")
STEEL = C("#b8c6dc")
STEEL_D = C("#6d82a8")
WOOD = C("#8a5a34")
TERRA = C("#c0623a")
WHITE = C("#ffffff")


def tab_hero(S):
    # Шахтёрская каска с налобным фонарём.
    S.ell(8, 8, 6, 6, C("#f08a2a"))
    S.rect(1, 10, 14, 12, C("#d06a1a"))
    S.rect(7, 2, 8, 8, C("#ffb050"), bevel=False)                 # гребень
    S.rect(9, 5, 12, 8, STEEL)                                    # фонарь
    S.pxs([(10, 6), (11, 6)], WHITE)
    S.pxs([(13, 5), (13, 8), (14, 6), (14, 7)], GOLD_L)           # свет

def tab_skills(S):
    # Дерево навыков: корень и три ступени-ветки.
    S.line([(8, 3), (2, 12)], GOLD_D)
    S.line([(8, 3), (14, 12)], GOLD_D)
    S.line([(8, 3), (8, 12)], GOLD_D)
    S.ell(8, 3, 2, 2, GOLD_L)
    for x in (2, 8, 14):
        S.ell(x, 12, 2, 2, GOLD)

def tab_museum(S):
    # Амфора.
    S.rect(6, 2, 9, 4, TERRA)                                     # горло
    S.ell(8, 9, 5, 5, TERRA)
    S.rect(5, 3, 10, 3, C("#8a3f22"), bevel=False)
    S.rect(2, 5, 3, 9, C("#8a3f22"))                              # ручки
    S.rect(12, 5, 13, 9, C("#8a3f22"))
    S.rect(5, 8, 10, 8, C("#3a1c10"), bevel=False)                # орнамент
    S.pxs([(6, 10), (8, 10), (10, 10)], C("#3a1c10"))
    S.rect(6, 13, 9, 14, C("#8a3f22"))


def tab_close(S):
    S.line([(3, 3), (12, 12)], C("#f4e6c8"), 2)
    S.line([(12, 3), (3, 12)], C("#f4e6c8"), 2)


def sk_vision(S):
    S.ell(8, 8, 7, 4, C("#f4f0e8"))
    S.ell(8, 8, 3, 3, TEAL, bevel=False)
    S.ell(8, 8, 1, 1, C("#10202a"), bevel=False)
    S.px(7, 7, WHITE)


def sk_dig_speed(S):
    S.rect(7, 5, 8, 14, WOOD)
    S.poly([(1, 7), (2, 4), (5, 2), (10, 2), (13, 4), (14, 7), (12, 5), (10, 4), (5, 4), (3, 5)], STEEL)
    S.pxs([(4, 3), (5, 3)], WHITE)


def sk_hp(S):
    S.ell(5, 6, 3, 3, RED)
    S.ell(10, 6, 3, 3, RED)
    S.poly([(2, 7), (13, 7), (8, 14)], RED)
    S.px(4, 5, C("#ff9aa4")); S.px(5, 4, C("#ff9aa4"))


def sk_stamina(S):
    S.poly([(9, 1), (3, 9), (7, 9), (6, 15), (13, 6), (9, 6)], GOLD_L)


def sk_hunger(S):
    # Куриная ножка.
    S.line([(8, 9), (12, 13)], C("#efe6d0"), 2)
    S.ell(13, 14, 1, 1, C("#efe6d0"), bevel=False)
    S.ell(6, 6, 5, 4, C("#b5622f"))
    S.pxs([(4, 4), (5, 4)], C("#e09a5a"))


def sk_strength(S):
    # Гиря.
    S.ell(8, 5, 4, 4, STEEL_D)
    S.ell(8, 5, 2, 2, OUT, bevel=False)
    S.ell(8, 10, 6, 5, STEEL_D)
    S.pxs([(5, 8), (6, 7), (5, 9)], tint(STEEL_D, 0.5))
    S.pxs([(7, 11), (8, 11), (9, 11)], tint(STEEL_D, -0.3))

def sk_luck_multiplier(S):
    # Подкова.
    S.ell(8, 8, 6, 6, STEEL)
    S.ell(8, 8, 3, 3, OUT, bevel=False)
    S.rect(5, 10, 10, 14, OUT, bevel=False)
    S.rect(2, 9, 4, 14, STEEL)
    S.rect(11, 9, 13, 14, STEEL)
    S.pxs([(3, 11), (12, 11), (4, 6), (11, 6)], C("#50607c"))


def sk_luck_chance(S):
    # Четырёхлистный клевер.
    for x, y in ((5, 5), (10, 5), (5, 10), (10, 10)):
        S.ell(x, y, 3, 3, GREEN)
    S.ell(8, 8, 1, 1, tint(GREEN, -0.3), bevel=False)
    S.line([(8, 11), (10, 15)], C("#3a8a4a"))
    S.pxs([(4, 4), (9, 4), (4, 9), (9, 9)], C("#a8f0b0"))


def sk_greed(S):
    # Жадность: пламя азарта с самородком (как значок шкалы азарта в HUD).
    S.poly([(8, 0), (11, 3), (13, 7), (14, 11), (12, 14), (8, 15), (4, 14), (2, 11), (2, 8), (4, 9),
            (5, 5), (6, 7)], C("#f07a1e"))
    S.poly([(8, 4), (10, 7), (11, 10), (10, 13), (6, 13), (5, 11), (6, 8), (7, 9)], C("#ffc83a"), bevel=False)
    S.ell(8, 11, 2, 2, GOLD)
    S.pxs([(7, 10)], GOLD_L)
    S.pxs([(9, 2), (12, 7)], C("#ffb060"))


def ui_lock(S):
    S.ell(8, 5, 3, 3, STEEL_D, bevel=False)
    S.ell(8, 5, 1, 1, OUT, bevel=False)
    S.rect(5, 7, 6, 8, STEEL_D, bevel=False)
    S.rect(10, 7, 11, 8, STEEL_D, bevel=False)
    S.rect(3, 8, 12, 14, C("#8a98b4"))
    S.rect(7, 10, 8, 12, OUT, bevel=False)


def ui_check(S):
    S.line([(2, 8), (6, 12), (13, 3)], C("#7de08a"), 3)
    S.line([(2, 8), (6, 12), (13, 3)], C("#d6ffd9"), 1)


def ui_star(S):
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36 * k)
        r = 7 if k % 2 == 0 else 3
        pts.append((round(8 + r * math.cos(a)), round(8.5 + r * math.sin(a))))
    S.poly(pts, GOLD)
    S.pxs([(7, 5), (7, 6)], GOLD_L)


def ui_depth(S):
    S.rect(5, 1, 10, 7, TEAL)
    S.poly([(1, 7), (14, 7), (8, 13)], TEAL)
    S.rect(1, 14, 14, 14, C("#b07a40"), bevel=False)

def _gem(S, base):
    S.poly([(4, 2), (11, 2), (14, 6), (8, 14), (2, 6)], base)
    S.poly([(4, 2), (7, 6), (2, 6)], tint(base, 0.4), bevel=False)
    S.poly([(11, 2), (8, 6), (14, 6)], tint(base, 0.15), bevel=False)
    S.line([(2, 6), (14, 6)], tint(base, 0.5))
    S.px(5, 3, WHITE)


def ui_gem(S):
    _gem(S, C("#4fd8d0"))


def ui_bag(S):
    S.rect(3, 5, 12, 14, C("#a2602c"))
    S.rect(5, 1, 10, 4, C("#6e3f1c"))
    S.rect(6, 9, 9, 11, STEEL)
    S.rect(2, 11, 3, 13, STEEL_D)
    S.rect(12, 11, 13, 13, STEEL_D)


def ui_coin(S):
    S.ell(8, 8, 6, 6, GOLD)
    S.ell(8, 8, 4, 4, C("#f2c64a"), bevel=False)
    S.rect(7, 5, 8, 11, GOLD_D, bevel=False)
    S.px(5, 5, GOLD_L); S.px(6, 4, GOLD_L)


def ui_dollar(S):
    S.ell(8, 8, 6, 6, C("#3fa05a"))
    S.ell(8, 8, 4, 4, C("#58c26a"), bevel=False)
    S.pxs([(9, 5), (8, 5), (7, 6), (7, 7), (8, 8), (9, 9), (9, 10), (8, 11), (7, 11)], C("#145a2a"))
    S.pxs([(8, 4), (8, 12)], C("#145a2a"))
    S.px(5, 5, C("#b6f2c0")); S.px(6, 4, C("#b6f2c0"))


def ui_trophy(S):
    S.line([(3, 3), (1, 3), (1, 6), (4, 8)], GOLD_D)
    S.line([(12, 3), (14, 3), (14, 6), (11, 8)], GOLD_D)
    S.poly([(3, 2), (12, 2), (11, 8), (8, 10), (4, 8)], GOLD)
    S.rect(7, 10, 8, 12, GOLD_D)
    S.rect(4, 12, 11, 14, GOLD_D)
    S.pxs([(5, 3), (5, 4), (5, 5)], GOLD_L)

def ui_chest(S):
    S.rect(2, 7, 13, 14, C("#8a5a34"))
    S.poly([(2, 7), (3, 3), (12, 3), (13, 7)], C("#a2723e"))
    S.rect(2, 7, 13, 8, GOLD_D, bevel=False)
    S.rect(7, 7, 8, 10, GOLD)
    S.pxs([(4, 5), (11, 5)], C("#c89a5c"))


def ui_xp(S):
    S.poly([(8, 1), (10, 6), (15, 8), (10, 10), (8, 15), (6, 10), (1, 8), (6, 6)], C("#5ea8f0"))
    S.px(7, 6, WHITE)


def ui_pip(S):
    S.ell(8, 8, 3, 3, GOLD)


def ui_branch_done(S):
    # Кубок-печать «ветка собрана».
    ui_trophy(S)


GEM_COLORS = {
    "gem_hellstone": "#e8552a",
    "gem_dark_matter": "#6a3fc0",
    "gem_universum": "#6ab8ff",
    "gem_angelstone": "#fff0b0",
    "gem_divine_heart": "#ff6aa0",
}

ICONS = [
    tab_hero, tab_skills, tab_museum, tab_close,
    sk_vision, sk_dig_speed, sk_hp, sk_stamina, sk_hunger, sk_strength, sk_luck_multiplier, sk_luck_chance, sk_greed,
    ui_lock, ui_check, ui_star, ui_depth, ui_gem, ui_bag, ui_coin, ui_dollar, ui_trophy, ui_chest, ui_xp, ui_pip,
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    images, labels = [], []

    def emit(name, draw):
        S = Spr(16)
        draw(S)
        S.outline(OUT, diag=False)
        im = S.image()
        im.save(os.path.join(OUT_DIR, name + ".png"))
        images.append(im)
        labels.append(name)

    for fn in ICONS:
        emit(fn.__name__, fn)
    for name, col in GEM_COLORS.items():
        emit(name, lambda S, c=C(col): _gem(S, c))
    print("записано %d иконок в %s" % (len(images), os.path.normpath(OUT_DIR)))
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(images, labels, 8, path, scale=8)
        print("контактный лист:", path)


if __name__ == "__main__":
    main()
