#!/usr/bin/env python3
"""Графика часов-телепорта: площадка на траве, неоновый огонёк, пузырь «Вниз».

Пишет (скрипт — источник правды, PNG руками не правим):

  art/teleport/pad.png        40x14  мини-платформа справа от тоннеля: стальной диск-пятачок
                                     на каменном ободе, в крышке — кольцевой паз под энергию
  art/teleport/pad_rune.png   40x14  только паз и огоньки обода — их движок рисует сложением
                                     (зелёным), пока возврат под землю доступен
  art/teleport/orb.png        11x11  ядро огонька: мята-белый центр, зелёные ступени к краю
  art/teleport/mote.png        3x3   искра, бегущая по кругу и стекающая к площадке
  art/house_ui/act_teleport_down.png 24x24  значок пузыря «Вниз»: часы и зелёная стрелка вниз

Один пиксель картинки = один пиксель мира (как станция заправки, art/tech/station.png).
Стиль и палитра — как у станции и значков дома (tools/gen_shop_icons.py, gen_house_icons.py):
тёмная обводка, 4–6 тонов, ободок света сверху, без сглаживания. Ореол вокруг огонька —
общая мягкая текстура art/fx/glow_soft.png (свет мира, ветка world-fx), здесь не рисуется.
Это аккуратная замена-заглушка «программист нарисовал», не работа художника.

    python3 tools/gen_teleport_art.py            # записать
    python3 tools/gen_teleport_art.py --sheet X  # заодно контактный лист (×6) в файл X
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_shop_icons as S  # noqa: E402  холст, палитра и обводка те же, что у магазина

ROOT = S.G.ROOT
OUT_TP = os.path.join(ROOT, "art", "teleport")
OUT_HOUSE = os.path.join(ROOT, "art", "house_ui")
rgba = S.rgba
WHITE = S.WHITE
OUT = S.OUT
SAVED = []

STEEL_HI, STEEL_L, STEEL, STEEL_D, STEEL_DD = rgba("#E4ECEF"), rgba("#B9C6CC"), rgba("#8B99A2"), rgba("#5C6A74"), rgba("#3E4852")
STONE, STONE_D = rgba("#7A746A"), rgba("#544F48")
SLOT = rgba("#262C36")
GREEN_HI, GREEN_L, GREEN, GREEN_D, GREEN_DD = rgba("#E8FFF2"), rgba("#B8FFD8"), rgba("#4DE094"), rgba("#1C8A52"), rgba("#0F5432")
GOLD, GOLD_L, GOLD_D = rgba("#FFE066"), rgba("#FFF3A0"), rgba("#D9962A")
BLUE, BLUE_L, BLUE_D = rgba("#2E5C9C"), rgba("#5C9BD8"), rgba("#1E3A66")


class Cv(S.Cv):
    def __init__(self, w, h, outdir):
        super().__init__(w, h)
        self.outdir = outdir

    def save(self, name):
        os.makedirs(self.outdir, exist_ok=True)
        self.img.save(os.path.join(self.outdir, name + ".png"))
        SAVED.append((self.outdir, name))


def in_ell(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


# --------------------------------------------------------------------------
# Площадка
# --------------------------------------------------------------------------

PAD_W, PAD_H = 40, 14
TOP_CY, TOP_RX, TOP_RY = 4.5, 19.0, 4.4      # крышка диска (вид чуть сверху)
RIM_DROP = 4                                  # толщина обода под крышкой
RING_RX, RING_RY = 12.5, 2.6                  # кольцевой паз в крышке


def pad_mask():
    """Силуэт: крышка-эллипс и обод, свисающий на RIM_DROP вниз (низ — дуга той же крышки)."""
    m = set()
    cx = (PAD_W - 1) / 2.0
    for y in range(PAD_H):
        for x in range(PAD_W):
            top = in_ell(x, y, cx, TOP_CY, TOP_RX, TOP_RY)
            band = in_ell(x, y - RIM_DROP, cx, TOP_CY, TOP_RX, TOP_RY) and y >= TOP_CY
            if top or band:
                m.add((x, y))
    return m


def pad():
    cv = Cv(PAD_W, PAD_H, OUT_TP)
    cx = (PAD_W - 1) / 2.0
    mask = pad_mask()
    for (x, y) in mask:
        top = in_ell(x, y, cx, TOP_CY, TOP_RX, TOP_RY)
        if top:
            # Крышка: светлее к дальнему краю (свет сверху), ободок блика по верхней дуге.
            c = STEEL_L if y <= 3 else STEEL
            if not in_ell(x, y + 1, cx, TOP_CY, TOP_RX, TOP_RY - 0.4) or y == 0:
                c = STEEL_HI
            cv.px(x, y, c)
        else:
            # Обод: сталь сверху, камень снизу, тень к краям.
            depth = y - TOP_CY
            edge = abs(x - cx) / TOP_RX
            c = STEEL_D if depth < 3.5 else STONE
            if edge > 0.82:
                c = STEEL_DD if depth < 3.5 else STONE_D
            cv.px(x, y, c)
    # Нижняя кромка крышки — тонкая тень, отделяет крышку от обода.
    for x in range(PAD_W):
        for y in range(PAD_H - 1, -1, -1):
            if (x, y) in mask and in_ell(x, y, cx, TOP_CY, TOP_RX, TOP_RY):
                if (x, y + 1) in mask:
                    cv.px(x, y + 1, STEEL_DD)
                break
    # Кольцевой паз и тёмная сердцевина.
    for (x, y) in ring_pixels():
        cv.px(x, y, SLOT)
    cv.px(int(cx), 4, SLOT)
    cv.px(int(cx) + 1, 4, SLOT)
    # Огоньки обода (выключенные — тёмно-зелёные) и заклёпки.
    for (x, y) in rim_lights():
        cv.px(x, y, GREEN_DD)
    for x in (5, 34):
        cv.px(x, 9, STEEL_L)
    cv.outline(OUT)
    cv.save("pad")


def ring_pixels():
    cx = (PAD_W - 1) / 2.0
    out = []
    for y in range(PAD_H):
        for x in range(PAD_W):
            inside = in_ell(x, y, cx, TOP_CY - 0.3, RING_RX, RING_RY)
            inner = in_ell(x, y, cx, TOP_CY - 0.3, RING_RX - 1.5, RING_RY - 1.0)
            if inside and not inner:
                out.append((x, y))
    return out


def rim_lights():
    return [(10, 10), (16, 11), (23, 11), (29, 10)]


def pad_rune():
    """Только светящиеся пиксели: паз и огоньки обода — движок кладёт их сложением."""
    cv = Cv(PAD_W, PAD_H, OUT_TP)
    cx = (PAD_W - 1) / 2.0
    for (x, y) in ring_pixels():
        # Ближняя (нижняя) дуга ярче дальней — по ней «стекает» энергия к зрителю.
        cv.px(x, y, GREEN_L if y >= 5 else GREEN)
    cv.px(int(cx), 4, GREEN_HI)
    cv.px(int(cx) + 1, 4, GREEN_HI)
    for (x, y) in rim_lights():
        cv.px(x, y, GREEN_L)
    cv.save("pad_rune")


# --------------------------------------------------------------------------
# Огонёк
# --------------------------------------------------------------------------

def orb():
    """Неоновое ядро: ромбо-круг ступенями 4 тонов, без тёмной обводки (это свет)."""
    cv = Cv(11, 11, OUT_TP)
    c = 5.0
    for y in range(11):
        for x in range(11):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 + 0.35 * (abs(x - c) + abs(y - c)) / 2.0
            if d <= 1.6:
                cv.px(x, y, GREEN_HI)
            elif d <= 2.7:
                cv.px(x, y, GREEN_L)
            elif d <= 3.8:
                cv.px(x, y, GREEN)
            elif d <= 4.9:
                cv.px(x, y, (*GREEN_D[:3], 200))
    # блик — свет сверху слева, как у руд
    cv.px(4, 3, WHITE)
    cv.save("orb")


def mote():
    cv = Cv(3, 3, OUT_TP)
    cv.px(1, 1, GREEN_HI)
    for (x, y) in ((0, 1), (2, 1), (1, 0), (1, 2)):
        cv.px(x, y, GREEN)
    cv.save("mote")


# --------------------------------------------------------------------------
# Значок пузыря «Вниз»
# --------------------------------------------------------------------------

def act_teleport_down():
    cv = Cv(24, 24, OUT_HOUSE)
    # часы: ремешок, золотой корпус, синий циферблат со стрелками (как плитка товара)
    cv.rect(10, 0, 13, 2, rgba("#6B4428"))
    cv.ell(11.5, 8, 7, 7, GOLD_D)
    cv.ell(11.5, 8, 6, 6, GOLD)
    cv.ell(11.5, 8, 4.6, 4.6, BLUE)
    cv.ell(11, 7.5, 3.4, 3.4, BLUE_L)
    cv.line([(11.5, 8), (11.5, 5)], WHITE, 1)
    cv.line([(11.5, 8), (14, 9)], WHITE, 1)
    cv.px(9, 5, WHITE)
    cv.px(6, 4, GOLD_L)
    # зелёная стрелка вниз поверх нижнего края часов
    cv.rect(10, 12, 13, 17, GREEN_D)
    cv.rect(11, 12, 12, 17, GREEN)
    cv.poly([(5, 17), (18, 17), (11.5, 23)], GREEN_D)
    cv.poly([(7, 17), (16, 17), (11.5, 21.5)], GREEN)
    cv.px(11, 13, GREEN_L)
    cv.px(11, 14, GREEN_L)
    cv.px(9, 18, GREEN_L)
    cv.outline(OUT)
    cv.save("act_teleport_down")


def contact_sheet(path, scale=6):
    imgs = [Image.open(os.path.join(d, n + ".png")) for d, n in SAVED]
    w = sum(i.width * scale + 8 for i in imgs) + 8
    h = max(i.height for i in imgs) * scale + 16
    sheet = Image.new("RGBA", (w, h), (52, 60, 78, 255))
    x = 8
    for im in imgs:
        sheet.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST), (x, 8))
        x += im.width * scale + 8
    sheet.save(path)


def main():
    pad()
    pad_rune()
    orb()
    mote()
    act_teleport_down()
    if "--sheet" in sys.argv:
        contact_sheet(sys.argv[sys.argv.index("--sheet") + 1])
    print("gen_teleport_art: " + ", ".join(n for _, n in SAVED))


if __name__ == "__main__":
    main()
