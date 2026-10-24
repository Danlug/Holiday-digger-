#!/usr/bin/env python3
"""Значок «i» — намёк, что предмет в окне подтверждения покупки нажимается
(тап раскрывает описание). Рисуется отдельно от gen_shop_icons.py, чтобы не
пересекаться с правками его функций; кисть и палитра — те же.

    python3 tools/gen_shop_info_glyph.py        -> art/ui/shop/glyph_info.png (16x16)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_shop_icons as S  # noqa: E402


def glyph_info():
    cv = S.Cv(16, 16)
    # Круглый синий значок: тёмный низ, светлый верх, блик — как остальные знаки.
    cv.ell(7, 7, 6, 6, S.rgba("#2A5FB0"))
    cv.ell(7, 6, 5, 5, S.rgba("#4C93E8"))
    cv.ell(6, 4, 3, 2, S.rgba("#7FBBFF"))
    # Буква «i»: точка и ножка с засечками.
    cv.rect(6, 3, 8, 5, S.WHITE)
    cv.rect(6, 7, 8, 11, S.WHITE)
    cv.rect(5, 7, 5, 7, S.WHITE)
    cv.rect(5, 11, 9, 11, S.WHITE)
    cv.outline()
    cv.save("glyph_info")


if __name__ == "__main__":
    glyph_info()
    print("glyph_info -> " + S.OUTDIR)
