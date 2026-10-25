#!/usr/bin/env python3
"""Значок «у входной двери» для витрины (ветка garden-shop, раунд 5).

Пишет art/ui/shop/glyph_door.png (16x16): деревянная входная дверь в косяке,
латунная ручка и коврик. Им помечаются плитки, которые за монеты покупаются
только у входной двери (вместо замка), и он же стоит в полосе-напоминании
витрины и в стрелке «к двери» над домом.

Отдельный скрипт, а не функция в tools/gen_shop_icons.py: тот перезаписывает
весь каталог значков разом, а здесь нужен один файл. Холст и обводку берём
оттуда же — стиль один (тёмная обводка, чёткий пиксель, без сглаживания).
Заглушка уровня «программист нарисовал аккуратно», не работа художника.

    python3 tools/gen_door_glyph.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_shop_icons as S  # noqa: E402

rgba = S.rgba


def glyph_door():
    cv = S.Cv(16, 16)
    frame = rgba("#4A2E1A")
    wood = rgba("#8F6238")
    wood_hi = rgba("#B8834A")
    wood_lo = rgba("#6B4428")
    # косяк с полукруглым верхом
    cv.rect(2, 3, 13, 13, frame)
    cv.rect(4, 1, 11, 2, frame)
    cv.px(3, 2, frame)
    cv.px(12, 2, frame)
    # полотно двери
    cv.rect(4, 4, 11, 13, wood)
    cv.rect(5, 3, 10, 3, wood)
    cv.rect(6, 2, 9, 2, wood)
    # доски: светлый край слева, щели
    cv.rect(4, 4, 4, 13, wood_hi)
    cv.px(5, 3, wood_hi)
    cv.rect(7, 6, 7, 13, wood_lo)
    cv.rect(10, 6, 10, 13, wood_lo)
    # окошко-полукруг сверху
    cv.rect(6, 4, 9, 4, rgba("#FFE9A8"))
    cv.rect(7, 3, 8, 3, rgba("#FFF6D0"))
    # латунная ручка
    cv.px(9, 9, rgba("#FFD84A"))
    cv.px(9, 10, rgba("#C08A1E"))
    # коврик у порога
    cv.rect(2, 14, 13, 14, rgba("#6FD08A"))
    cv.rect(1, 15, 14, 15, rgba("#3FA45B"))
    cv.outline()
    cv.save("glyph_door")


def main():
    glyph_door()
    print("записано: " + ", ".join(S.SAVED))


if __name__ == "__main__":
    main()
