#!/usr/bin/env python3
"""Значки окна смерти (ГДД §7 «Цена смерти», разбор чисел 26.10): art/ui/icons/<имя>.png, 32x32.

  hospital  — «потрачено на больницу»: белое здание с красным крестом над входом;
  fall      — причина «разбился при падении»: стрелка вниз бьётся о плиту, плита трескается.

Остальные причины берут готовые значки (голод, бодрость, пламя, череп, ртуть, спрайт монстра).
Холст, плюс с контуром и обводка — из tools/gen_shop_icons.py (тот же стиль, что аптечка и
таблетка): чёткий пиксель, свет сверху-слева, тёмный контур. Заглушка уровня «программист
нарисовал аккуратно», не работа художника; PNG руками не правим.

    python3 tools/gen_death_icons.py [контактный_лист.png]
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_shop_icons as S  # noqa: E402  холст Cv, rgba, плюс с контуром

OUTDIR = os.path.join(HERE, "..", "art", "ui", "icons")
rgba = S.rgba


def save(cv, name):
    os.makedirs(OUTDIR, exist_ok=True)
    cv.img.save(os.path.join(OUTDIR, name + ".png"))
    return cv.img


def gen_hospital():
    """Больница: центральный корпус выше крыльев, на нём красный крест (как на аптечке), окна
    голубые с бликом, тёмная дверь по центру, крыши крыльев светлее стен. Силуэт — «здание»,
    а не «чемоданчик»: рядом с монетой в 16 единиц читается домиком с крестом."""
    wall = [rgba(h) for h in ("#FFFFFF", "#F5F8FB", "#DDE4EE", "#B4C0D2", "#8896AE")]
    red, red_d = rgba("#EC4A63"), rgba("#A31A35")
    glass, glass_l = rgba("#5C9BD8"), rgba("#B8E0FF")
    door, door_l = rgba("#2E5C9C"), rgba("#5C9BD8")
    cv = S.Cv()
    # крылья
    cv.rect(2, 14, 29, 28, wall[1])
    cv.rect(2, 13, 29, 13, wall[0])                # кромка крыши крыльев на свету
    cv.rect(2, 14, 2, 27, wall[0])
    cv.rect(29, 14, 29, 28, wall[3])               # правый торец в тени
    cv.rect(2, 27, 29, 28, wall[3])                # цоколь
    # центральный корпус
    cv.rect(10, 4, 21, 28, wall[1])
    cv.rect(10, 3, 21, 3, wall[0])
    cv.rect(10, 4, 10, 27, wall[0])
    cv.rect(21, 4, 21, 27, wall[2])
    cv.rect(10, 12, 21, 12, wall[2])               # карниз под крестом
    # красный крест на корпусе
    S._plus_with_ink(cv, 16, 8, 4, 2, red, red_d)
    # окна крыльев (2 ряда по 2) с бликом
    for wx in (4, 7, 24, 27):
        for wy in (16, 21):
            cv.rect(wx - 1, wy, wx, wy + 2, glass)
            cv.px(wx - 1, wy, glass_l)
    # дверь с козырьком
    cv.rect(13, 21, 18, 28, door)
    cv.rect(13, 21, 13, 27, door_l)
    cv.rect(12, 19, 19, 19, red)
    cv.rect(12, 20, 19, 20, red_d)
    cv.rect(15, 21, 16, 28, rgba("#1E3E6E"))       # створки
    # окна над дверью
    cv.rect(12, 14, 13, 16, glass)
    cv.rect(18, 14, 19, 16, glass)
    cv.px(12, 14, glass_l)
    cv.px(18, 14, glass_l)
    cv.outline()
    return save(cv, "hospital")


def gen_fall():
    """Падение: золотая стрелка вниз (родня arrow_up/depth из значков HUD) упирается в каменную
    плиту; от удара — трещина в плите и белые штрихи-«звёздочки» по бокам. Без героя: значок
    стоит рядом с фразой «Разбился при падении с высоты N клеток»."""
    gold = [rgba(h) for h in ("#FFF3A0", "#FFE066", "#E8B32E", "#B07A18", "#7A5410")]
    stone = [rgba(h) for h in ("#B8A890", "#9D8B73", "#7A6A56", "#574A3C")]
    crack = rgba("#2A2018")
    cv = S.Cv()
    # плита
    cv.rect(3, 23, 28, 29, stone[1])
    cv.rect(3, 23, 28, 23, stone[0])
    cv.rect(3, 28, 28, 29, stone[2])
    cv.rect(28, 24, 28, 29, stone[3])
    for (x, y) in ((7, 26), (11, 27), (22, 25), (25, 27)):   # зерно камня
        cv.px(x, y, stone[2])
    # трещина от удара
    for (x, y) in ((15, 24), (16, 24), (15, 25), (14, 26), (14, 27), (13, 28),     # ствол вниз-влево
                   (17, 25), (18, 25), (19, 26), (20, 27),                         # ветка вправо
                   (11, 27), (12, 27)):                                            # отросток
        cv.px(x, y, crack)
    for (x, y) in ((16, 25), (15, 27), (19, 27)):                                  # скол светлее
        cv.px(x, y, stone[0])
    # стрелка: древко и наконечник вниз, свет слева
    cv.rect(13, 2, 18, 12, gold[2])
    cv.rect(13, 2, 14, 12, gold[1])
    cv.rect(18, 2, 18, 12, gold[3])
    cv.rect(13, 2, 18, 2, gold[0])
    head = [(6, 12), (25, 12), (16, 22), (15, 22)]
    cv.poly(head, gold[2])
    cv.poly([(6, 12), (15, 12), (15, 21)], gold[1])
    cv.line([(25, 12), (16, 22)], gold[3])
    cv.rect(6, 12, 25, 12, gold[0])
    # штрихи удара по бокам: два луча с каждой стороны, у плиты
    white = rgba("#FFFFFF")
    for (x, y) in ((4, 18), (5, 19), (6, 20), (2, 21), (3, 21), (4, 21),
                   (27, 18), (26, 19), (25, 20), (29, 21), (28, 21), (27, 21)):
        cv.px(x, y, white)
    cv.outline()
    return save(cv, "fall")


def main():
    imgs = [gen_hospital(), gen_fall()]
    print("записано %d значка в %s" % (len(imgs), os.path.normpath(OUTDIR)))
    if len(sys.argv) > 1:
        sheet = Image.new("RGBA", (len(imgs) * 170 + 10, 180), (0x2A, 0x20, 0x18, 255))
        for i, im in enumerate(imgs):
            sheet.alpha_composite(im.resize((160, 160), Image.NEAREST), (10 + i * 170, 10))
        sheet.save(sys.argv[1])


if __name__ == "__main__":
    main()
