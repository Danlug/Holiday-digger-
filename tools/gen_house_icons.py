#!/usr/bin/env python3
"""Графика интерфейса дома: значки действий в пузырях, сон, доставка, склад.

Пишет в art/house_ui/ (скрипт — источник правды, PNG руками не правим):

  act_*.png     24x24  значки действий в пузырях над героем: дверь, лестница,
                       кровать, заказ, пакет, ящик с инструментами (мастерская, 🧰),
                       склад, кирка (⛏️), бурмобиль
  z_small/z_big        «Z» сна, летящие вверх; sun, moon — рассвет и ночь
  skip_sleep    24x24  «пропустить сон за ролик»
  courier       32x32  курьер на скутере с коробом; knock — кулак у двери
  put_all, take_all    24x24 «сложить рюкзак» / «забрать всё»
  glyph_minus   16x16  «минус» окна количества; calendar — номер дня
  bubble_tail   11x6   хвостик пузыря (тело и рамка пузыря — tile_body/tile_rim магазина)

Стиль и палитра — как у art/ui/shop (tools/gen_shop_icons.py): чёткий пиксель, тёмная
обводка в один пиксель, без сглаживания. Это аккуратная замена-заглушка «программист
нарисовал», а не работа художника: готовые значки кладутся под теми же именами.

    python3 tools/gen_house_icons.py            # записать в art/house_ui/
    python3 tools/gen_house_icons.py --sheet X  # заодно контактный лист в файл X
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_shop_icons as S  # noqa: E402  холст, палитра и обводка те же, что у магазина

OUTDIR = os.path.join(S.G.ROOT, "art", "house_ui")
rgba = S.rgba
WHITE = S.WHITE
SAVED = []

WOOD, WOOD_L, WOOD_D = rgba("#8F6238"), rgba("#B4854E"), rgba("#6B4428")
STEEL, STEEL_L, STEEL_D = rgba("#8B99A2"), rgba("#D2DCE0"), rgba("#5C6A74")
GOLD, GOLD_L, GOLD_D = rgba("#FFE066"), rgba("#FFF3A0"), rgba("#D9962A")
RED, RED_L, RED_D = rgba("#C21E3A"), rgba("#FF5570"), rgba("#7A1024")
GREEN, GREEN_L, GREEN_D = rgba("#4DE094"), rgba("#B8FFD8"), rgba("#1C8A52")
BLUE, BLUE_L, BLUE_D = rgba("#5C9BD8"), rgba("#8FC4F4"), rgba("#33394A")
CREAM, CREAM_D = rgba("#E8D8B0"), rgba("#A4835A")
SKIN, SKIN_D = rgba("#F0C8A0"), rgba("#C8956C")
DARK = rgba("#2A2A32")


class Cv(S.Cv):
    def save(self, name):
        os.makedirs(OUTDIR, exist_ok=True)
        self.img.save(os.path.join(OUTDIR, name + ".png"))
        SAVED.append(name)


def cv24():
    return Cv(24, 24)


# --------------------------------------------------------------------------
# Значки действий
# --------------------------------------------------------------------------

def act_door():
    cv = cv24()
    cv.rect(4, 2, 19, 22, WOOD_D)
    cv.rect(5, 3, 18, 22, WOOD)
    cv.rect(5, 3, 18, 4, WOOD_L)
    cv.rect(7, 6, 11, 11, WOOD_D)
    cv.rect(12, 6, 16, 11, WOOD_D)
    cv.rect(7, 13, 16, 19, WOOD_D)
    cv.rect(8, 7, 10, 10, WOOD_L)
    cv.rect(13, 7, 15, 10, WOOD_L)
    cv.rect(8, 14, 15, 18, WOOD_L)
    cv.rect(15, 12, 16, 13, GOLD)
    cv.px(15, 12, GOLD_L)
    cv.outline()
    cv.save("act_door")


def act_enter():
    cv = cv24()
    cv.rect(4, 10, 19, 22, CREAM)
    cv.rect(4, 21, 19, 22, CREAM_D)
    cv.poly([(1, 11), (11.5, 1), (22, 11)], RED)
    cv.line([(3, 10), (11, 3)], RED_L, 1)
    cv.line([(12, 3), (20, 10)], RED_D, 1)
    cv.rect(9, 14, 14, 22, WOOD_D)
    cv.rect(10, 15, 13, 22, GOLD)
    cv.rect(10, 15, 13, 16, GOLD_L)
    cv.rect(5, 13, 7, 16, BLUE_L)
    cv.rect(16, 13, 18, 16, BLUE_L)
    cv.outline()
    cv.save("act_enter")


def act_exit():
    cv = cv24()
    cv.rect(2, 2, 14, 22, BLUE_D)
    cv.rect(3, 3, 13, 22, rgba("#CFE8FF"))
    cv.rect(3, 3, 13, 5, WHITE)
    cv.poly([(3, 3), (9, 5), (9, 20), (3, 22)], WOOD)
    cv.poly([(3, 3), (5, 4), (5, 21), (3, 22)], WOOD_L)
    cv.rect(8, 12, 8, 13, GOLD)
    cv.poly([(13, 10), (18, 10), (18, 7), (23, 12), (18, 17), (18, 14), (13, 14)], GREEN)
    cv.line([(14, 11), (18, 11)], GREEN_L, 1)
    cv.outline()
    cv.save("act_exit")


def act_stairs(down):
    cv = cv24()
    steps = [(2, 6, 7), (7, 10, 11), (12, 14, 15), (17, 18, 19)]
    if not down:
        steps = [(2, 18, 19), (7, 14, 15), (12, 10, 11), (17, 6, 7)]
    for x, top, _ in steps:
        cv.rect(x, top, x + 5, 22, WOOD)
        cv.rect(x, top, x + 5, top + 1, WOOD_L)
        cv.rect(x + 5, top, x + 5, 22, WOOD_D)
    if down:
        cv.poly([(2, 1), (9, 1), (9, 3), (6, 6), (2, 3)], rgba("#00000000"))
        cv.poly([(2, 2), (9, 2), (5.5, 6)], GOLD)
        cv.line([(3, 3), (8, 3)], GOLD_L, 1)
    else:
        cv.poly([(15, 6), (20, 1), (23, 6)], GREEN)
        cv.line([(17, 5), (20, 2)], GREEN_L, 1)
    cv.outline()
    cv.save("act_stairs_down" if down else "act_stairs_up")


def act_bed():
    cv = cv24()
    cv.rect(2, 8, 4, 20, WOOD_D)
    cv.rect(2, 8, 3, 20, WOOD)
    cv.rect(2, 13, 21, 18, CREAM)
    cv.rect(2, 13, 21, 14, WHITE)
    cv.rect(5, 12, 10, 14, WHITE)
    cv.rect(5, 12, 10, 12, CREAM)
    cv.rect(10, 13, 21, 18, BLUE)
    cv.rect(10, 13, 21, 14, BLUE_L)
    cv.rect(10, 17, 21, 18, BLUE_D)
    cv.line([(14, 13), (14, 18)], BLUE_L, 1)
    cv.line([(18, 13), (18, 18)], BLUE_L, 1)
    cv.rect(2, 19, 4, 21, WOOD_D)
    cv.rect(19, 19, 21, 21, WOOD_D)
    # «Z» над подушкой
    for (x, y, s) in ((13, 2, 3), (17, 5, 4)):
        cv.line([(x, y), (x + s, y)], GOLD, 1)
        cv.line([(x + s, y), (x, y + s)], GOLD, 1)
        cv.line([(x, y + s), (x + s, y + s)], GOLD, 1)
    cv.outline()
    cv.save("act_bed")


def act_order():
    cv = cv24()
    cv.rect(6, 1, 17, 22, DARK)
    cv.rect(7, 3, 16, 19, rgba("#1B2A4A"))
    cv.rect(7, 3, 16, 4, BLUE)
    cv.rect(11, 20, 12, 21, STEEL)
    # бургер на экране
    cv.rect(8, 8, 15, 10, rgba("#E8A03A"))
    cv.rect(8, 8, 15, 8, GOLD)
    cv.rect(8, 11, 15, 11, GREEN)
    cv.rect(8, 12, 15, 13, rgba("#7A4A28"))
    cv.rect(8, 14, 15, 15, rgba("#E8A03A"))
    cv.px(10, 9, WHITE)
    cv.px(13, 9, WHITE)
    # «звонок» — две дуги справа
    cv.line([(19, 7), (20, 9), (19, 11)], GOLD, 1)
    cv.line([(21, 5), (22, 9), (21, 13)], GOLD, 1)
    cv.outline()
    cv.save("act_order")


def act_package():
    cv = cv24()
    cv.poly([(4, 8), (19, 8), (18, 22), (5, 22)], rgba("#C8935A"))
    cv.poly([(4, 8), (8, 8), (7, 22), (5, 22)], rgba("#E3B27A"))
    cv.poly([(15, 8), (19, 8), (18, 22), (14, 22)], rgba("#9C6E3E"))
    # загнутый верх и ручки
    cv.rect(4, 7, 19, 9, rgba("#E3B27A"))
    cv.rect(4, 9, 19, 9, rgba("#9C6E3E"))
    cv.line([(8, 7), (8, 3), (11, 1)], rgba("#9C6E3E"), 1)
    cv.line([(15, 7), (15, 3), (12, 1)], rgba("#9C6E3E"), 1)
    # наклейка
    cv.ell(11, 15, 4, 4, RED)
    cv.ell(11, 15, 2, 2, GOLD)
    cv.px(10, 14, WHITE)
    cv.outline()
    cv.save("act_package")


def act_workbench():
    # ящик с инструментами в духе 🧰 (слова владельца 27.10): красный металлический,
    # стальная ручка-дуга сверху, две защёлки через шов крышки
    cv = cv24()
    cv.rect(8, 1, 15, 5, STEEL)
    cv.rect(8, 1, 15, 1, STEEL_L)
    cv.rect(10, 3, 13, 5, (0, 0, 0, 0))
    cv.px(8, 1, STEEL_L)
    cv.px(9, 2, STEEL_L)
    cv.rect(14, 2, 15, 5, STEEL_D)
    # крышка
    cv.rect(2, 6, 21, 12, RED)
    cv.rect(2, 6, 21, 6, RED_L)
    cv.rect(2, 7, 3, 12, RED_L)
    cv.rect(20, 7, 21, 12, RED_D)
    cv.rect(2, 12, 21, 12, RED_D)
    cv.rect(2, 13, 21, 13, DARK)
    # корпус
    cv.rect(2, 14, 21, 22, RED)
    cv.rect(2, 14, 3, 21, RED_L)
    cv.rect(20, 14, 21, 22, RED_D)
    cv.rect(2, 22, 21, 22, RED_D)
    for x in (5, 16):
        cv.rect(x, 11, x + 2, 15, STEEL)
        cv.rect(x, 11, x + 2, 11, STEEL_L)
        cv.rect(x, 15, x + 2, 15, STEEL_D)
        cv.px(x + 1, 13, STEEL_D)
    cv.px(5, 8, WHITE)
    cv.px(6, 8, WHITE)
    cv.outline()
    cv.save("act_workbench")


def act_chest():
    cv = cv24()
    cv.rect(2, 10, 21, 22, WOOD)
    cv.rect(2, 10, 21, 11, WOOD_L)
    cv.rect(2, 21, 21, 22, WOOD_D)
    cv.poly([(2, 10), (3, 4), (20, 4), (21, 10)], WOOD_L)
    cv.line([(4, 5), (19, 5)], rgba("#D8A868"), 1)
    for x in (5, 17):
        cv.rect(x, 4, x + 1, 22, STEEL)
        cv.rect(x, 4, x, 22, STEEL_L)
    cv.rect(2, 10, 21, 11, STEEL_D)
    cv.rect(10, 9, 13, 15, GOLD_D)
    cv.rect(10, 9, 13, 14, GOLD)
    cv.rect(11, 11, 12, 12, DARK)
    cv.px(10, 9, GOLD_L)
    cv.outline()
    cv.save("act_chest")


def act_pickaxe():
    # кирка в духе ⛏️ (слова владельца 27.10): рукоять снизу-слева, серый двузубый
    # серп-наконечник сверху-справа; серп — дуга вокруг центра C с толщиной,
    # сходящей на нет к зубьям, иначе на 24 px он читался как молоток
    cv = cv24()
    cv.line([(3, 21), (16, 8)], WOOD_D, 4)
    cv.line([(3, 20), (15, 8)], WOOD, 2)
    cv.line([(2, 20), (14, 8)], WOOD_L, 1)
    cx, cy = 9.0, 15.0
    r_mid, th_max, span = 10.0, 6.5, math.radians(60)
    axis = math.radians(-45)  # ось рукояти, вверх-вправо
    for y in range(24):
        for x in range(24):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            phi = (math.atan2(dy, dx) - axis + math.pi) % (2 * math.pi) - math.pi
            k = abs(phi) / span
            if k >= 1.0:
                continue
            th = th_max * (1.0 - k ** 2.2)
            if th < 1.0:
                continue
            r_in, r_out = r_mid - th * 0.5, r_mid + th * 0.5
            if r < r_in or r > r_out:
                continue
            t = (r - r_in) / (r_out - r_in)
            cv.px(x, y, STEEL_L if t > 0.66 else (STEEL_D if t < 0.26 else STEEL))
    cv.px(9, 3, WHITE)
    cv.px(10, 2, WHITE)
    cv.outline()
    cv.save("act_pickaxe")


def act_rig():
    cv = cv24()
    # гусеница
    cv.rect(2, 17, 18, 22, DARK)
    cv.rect(3, 18, 17, 21, STEEL_D)
    for x in (5, 9, 13):
        cv.ell(x, 19, 1, 1, STEEL_L)
    # кузов и кабина
    cv.rect(3, 9, 16, 16, rgba("#F2B33A"))
    cv.rect(3, 9, 16, 10, GOLD_L)
    cv.rect(3, 15, 16, 16, GOLD_D)
    cv.rect(4, 3, 10, 9, rgba("#E89A2E"))
    cv.rect(5, 4, 9, 8, BLUE_L)
    cv.rect(5, 4, 6, 5, WHITE)
    # бур
    cv.poly([(16, 10), (23, 13), (16, 16)], STEEL)
    cv.line([(17, 11), (22, 13)], STEEL_L, 1)
    cv.line([(18, 15), (21, 13)], STEEL_D, 1)
    cv.outline()
    cv.save("act_rig")


# --------------------------------------------------------------------------
# Сон
# --------------------------------------------------------------------------

def _z(name, s):
    cv = Cv(s + 4, s + 4)
    x0, y0, x1, y1 = 2, 2, 2 + s, 2 + s
    th = 1 if s < 8 else 2
    for off in range(th):
        cv.line([(x0, y0 + off), (x1, y0 + off)], WHITE, 1)
        cv.line([(x0, y1 - off), (x1, y1 - off)], WHITE, 1)
        cv.line([(x1 - off, y0), (x0 - off, y1)], WHITE, 1)
    cv.outline(rgba("#2A3A66"))
    cv.save(name)


def sun():
    cv = cv24()
    import math
    for i in range(8):
        a = i * math.pi / 4
        x0, y0 = 11.5 + math.cos(a) * 8, 11.5 + math.sin(a) * 8
        x1, y1 = 11.5 + math.cos(a) * 11, 11.5 + math.sin(a) * 11
        cv.line([(x0, y0), (x1, y1)], GOLD_D, 2)
    cv.ell(11.5, 11.5, 6, 6, GOLD)
    cv.ell(11.5, 11.5, 4, 4, GOLD_L)
    cv.px(9, 9, WHITE)
    cv.outline()
    cv.save("sun")


def moon():
    cv = cv24()
    cv.ell(11.5, 11.5, 9, 9, rgba("#E8EEFF"))
    cv.ell(16, 8, 8, 8, rgba("#00000000"))
    # вырез серпа: прозрачный круг поверх
    for y in range(24):
        for x in range(24):
            if (x - 16) ** 2 + (y - 8) ** 2 <= 64:
                cv.px(x, y, (0, 0, 0, 0))
    cv.ell(8, 14, 1, 1, rgba("#B8C4E8"))
    cv.ell(10, 8, 1, 1, rgba("#B8C4E8"))
    cv.px(20, 18, GOLD)
    cv.px(21, 17, GOLD)
    cv.px(19, 17, GOLD)
    cv.px(20, 16, GOLD)
    cv.outline()
    cv.save("moon")


def skip_sleep():
    cv = cv24()
    cv.rect(1, 3, 22, 17, BLUE_D)
    cv.rect(2, 4, 21, 16, BLUE)
    cv.rect(2, 4, 21, 6, BLUE_L)
    for x0 in (6, 12):
        cv.poly([(x0, 7), (x0, 15), (x0 + 6, 11)], WHITE)
    cv.rect(18, 7, 19, 15, WHITE)
    cv.rect(6, 19, 17, 20, BLUE_D)
    cv.outline()
    cv.save("skip_sleep")


# --------------------------------------------------------------------------
# Доставка
# --------------------------------------------------------------------------

def courier():
    cv = Cv(32, 32)
    # колёса
    for cx in (7, 24):
        cv.ell(cx, 25, 4, 4, DARK)
        cv.ell(cx, 25, 2, 2, STEEL)
        cv.px(cx, 25, STEEL_L)
    # корпус скутера
    cv.poly([(5, 22), (9, 17), (22, 17), (27, 22), (24, 22), (22, 20), (10, 20), (8, 22)], RED)
    cv.rect(9, 17, 22, 18, RED_L)
    cv.rect(21, 11, 23, 18, STEEL)
    cv.rect(19, 10, 25, 11, DARK)
    cv.px(27, 20, GOLD)
    cv.px(28, 20, GOLD)
    # короб на багажнике
    cv.rect(2, 8, 12, 17, rgba("#E8A03A"))
    cv.rect(2, 8, 12, 9, GOLD)
    cv.rect(2, 16, 12, 17, GOLD_D)
    cv.rect(6, 8, 7, 17, RED)
    # курьер
    cv.rect(13, 9, 18, 17, BLUE)
    cv.rect(13, 9, 14, 17, BLUE_L)
    cv.line([(18, 12), (21, 11)], BLUE, 2)
    cv.ell(16, 5, 3, 3, SKIN)
    cv.rect(13, 2, 19, 4, RED)
    cv.rect(18, 3, 21, 4, RED_D)
    cv.outline()
    cv.save("courier")


def knock():
    cv = cv24()
    # кулак: пальцы-костяшки слева, запястье справа
    cv.rect(8, 6, 18, 17, SKIN)
    cv.rect(8, 6, 18, 7, rgba("#F8DCC0"))
    cv.rect(8, 16, 18, 17, SKIN_D)
    for y in (6, 10, 14):
        cv.rect(5, y, 9, y + 3, SKIN)
        cv.line([(6, y), (9, y)], rgba("#F8DCC0"), 1)
        cv.line([(5, y + 3), (9, y + 3)], SKIN_D, 1)
    cv.rect(17, 8, 22, 16, rgba("#F2C14A"))
    cv.rect(17, 8, 22, 9, GOLD)
    cv.rect(17, 15, 22, 16, GOLD_D)
    cv.outline()
    # линии удара (после обводки, чтобы остались яркими)
    for (x0, y0, x1, y1) in ((2, 5, 0, 3), (2, 11, 0, 11), (2, 17, 0, 19)):
        cv.line([(x0, y0), (x1, y1)], GOLD, 1)
    cv.save("knock")


# --------------------------------------------------------------------------
# Склад
# --------------------------------------------------------------------------

def _crate(cv, top):
    cv.rect(2, top, 21, 22, WOOD)
    cv.rect(2, top, 21, top + 1, WOOD_L)
    cv.rect(2, 21, 21, 22, WOOD_D)
    cv.line([(2, top + 4), (21, top + 4)], WOOD_D, 1)
    cv.rect(10, top + 1, 13, top + 3, STEEL)


def put_all():
    cv = cv24()
    _crate(cv, 14)
    cv.poly([(8, 1), (15, 1), (15, 7), (19, 7), (11.5, 14), (4, 7), (8, 7)], GREEN)
    cv.line([(9, 2), (9, 7)], GREEN_L, 1)
    cv.outline()
    cv.save("put_all")


def take_all():
    cv = cv24()
    _crate(cv, 14)
    cv.poly([(8, 12), (15, 12), (15, 7), (19, 7), (11.5, 0), (4, 7), (8, 7)], GOLD)
    cv.line([(9, 11), (9, 7)], GOLD_L, 1)
    cv.outline()
    cv.save("take_all")


def glyph_minus():
    cv = Cv(16, 16)
    cv.line([(3, 8), (12, 8)], rgba("#B01A34"), 4)
    cv.line([(3, 7), (12, 7)], rgba("#FF5570"), 3)
    cv.px(4, 6, rgba("#FFC0C8"))
    cv.outline()
    cv.save("glyph_minus")


def calendar():
    cv = Cv(16, 16)
    cv.rect(2, 3, 13, 14, WHITE)
    cv.rect(2, 3, 13, 6, RED)
    cv.rect(2, 3, 13, 3, RED_L)
    cv.rect(2, 13, 13, 14, rgba("#C8C8D8"))
    cv.rect(4, 1, 5, 4, STEEL_D)
    cv.rect(10, 1, 11, 4, STEEL_D)
    for x in (4, 7, 10):
        for y in (8, 11):
            cv.rect(x, y, x + 1, y + 1, rgba("#6A6A80"))
    cv.outline()
    cv.save("calendar")


def bubble_tail():
    # хвостик пузыря: тёмное тело и белая рамка — красится так же, как tile_rim
    cv = Cv(11, 6)
    body = rgba("#1F1A28")
    for y in range(5):
        for x in range(y, 10 - y):
            cv.px(x, y, body)
    for y in range(5):
        cv.px(y, y, WHITE)
        cv.px(10 - y, y, WHITE)
    cv.px(5, 5, WHITE)
    cv.px(4, 4, WHITE)
    cv.px(6, 4, WHITE)
    cv.save("bubble_tail")


def contact_sheet(path):
    cell = 76
    cols = 8
    rows = (len(SAVED) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (52, 44, 60, 255))
    for i, n in enumerate(SAVED):
        im = Image.open(os.path.join(OUTDIR, n + ".png")).convert("RGBA")
        scale = 3 if im.width <= 24 else 2
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        x = (i % cols) * cell + (cell - big.width) // 2
        y = (i // cols) * cell + (cell - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    sheet.save(path)


def main():
    act_door()
    act_enter()
    act_exit()
    act_stairs(True)
    act_stairs(False)
    act_bed()
    act_order()
    act_package()
    act_workbench()
    act_chest()
    act_pickaxe()
    act_rig()
    _z("z_small", 5)
    _z("z_big", 9)
    sun()
    moon()
    skip_sleep()
    courier()
    knock()
    put_all()
    take_all()
    glyph_minus()
    calendar()
    bubble_tail()
    print("записано %d файлов в %s" % (len(SAVED), OUTDIR))
    if "--sheet" in sys.argv:
        contact_sheet(sys.argv[sys.argv.index("--sheet") + 1])


if __name__ == "__main__":
    main()
