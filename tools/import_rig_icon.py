#!/usr/bin/env python3
"""import_rig_icon.py — иконка бурмобиля для полосы инструментов внизу HUD.

Задача владельца: «когда он в бурмобиле, внизу картинка не ручного бура, не
лопаты и не кирки, а бурмобиля». До этого скрипта у tools.drill_rig.icon в
balance.json стояла заглушка hand_drill.png — кнопка инструмента показывала
бур и тогда, когда игрок сидел в бурмобиле.

Источник — ТОТ ЖЕ авторский лист, что режет tools/import_drill.py
(art/_source/drill_sheet.jpg), ряд «Burmobile Right Work»
(import_drill.BAND_RIG_SIDE), кадр 1 — машина в позе покоя, боком, бур
спереди. Этот скрипт ЧИТАЕТ drill_sheet.jpg НАПРЯМУЮ и не трогает
tools/import_drill.py и его готовые dig_rig_*.png: тот файл параллельно
переписывает другой агент (сажает мальчика в кабину), и общий код с ним
делил бы риск конфликта. Здесь — свой минимальный набор функций, скопированных
там, где нужно то же самое (фон листа, поиск кадров по содержимому), и без
привязки к анимационным константам персонажа (FRAME_W/FRAME_H и т.п. этому
скрипту не нужны — иконка кадрируется как обычный предмет, тем же приёмом,
что и шесть кирок в tools/import_pickaxes.py: один масштаб по большей
стороне, без искажения пропорций).

Кадр специально НЕ обрезает мальчика в кабине: на исходнике он виден сквозь
купол, и это и есть бурмобиль как его рисует художник — машина с героем
внутри, а не пустой корпус. На кнопке инструмента это же читается яснее, чем
абстрактный силуэт: сразу видно, что герой «сел за руль».

Запуск:  python3 tools/import_rig_icon.py
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import shrink  # noqa: E402
from import_drill import (BAND_RIG_SIDE, background_mask, cut,  # noqa: E402
                          drop_slivers, frame_columns, tone_match)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "_source", "drill_sheet.jpg")
OUT_PATH = os.path.join(ROOT, "art", "items", "drill_rig_icon.png")

BOX = 32  # предмет 32×32 — как все прочие в art/items (см. import_pickaxes.py)


def main():
    sheet = Image.open(SRC).convert("RGB")
    w, _h = sheet.size
    mask = background_mask(sheet)
    # Лист снят со своей экспозицией — без приведения к эталону машина
    # выйдет темнее/светлее соседних иконок инструмента (см. import_drill.py).
    sheet = tone_match(sheet, mask)

    y0, y1 = BAND_RIG_SIDE
    cols = frame_columns(mask, w, y0, y1)
    x0, x1 = cols[0]  # кадр 1: машина в покое, без отвала и искр под гусеницами
    frame = drop_slivers(cut(sheet, mask, (x0, y0, x1, y1)))
    bb = frame.getbbox()
    if bb is None:
        raise SystemExit("кадр бурмобиля пуст")
    piece = frame.crop(bb)
    print("кадр бурмобиля: %d×%d px исходника" % piece.size)

    # Один масштаб по большей стороне — та же логика, что у шести кирок:
    # предмет вписывается в кадр 32×32 целиком, без искажения пропорций.
    k = min(BOX / piece.size[0], BOX / piece.size[1])
    tw = max(1, round(piece.size[0] * k))
    th = max(1, round(piece.size[1] * k))
    small = shrink(piece, (tw, th))

    img = Image.new("RGBA", (BOX, BOX), (0, 0, 0, 0))
    img.alpha_composite(small, ((BOX - tw) // 2, (BOX - th) // 2))

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH)
    print("бурмобиль %d×%d -> %d×%d в кадре %d×%d -> %s"
          % (piece.size[0], piece.size[1], tw, th, BOX, BOX, OUT_PATH))


if __name__ == "__main__":
    main()
