#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_newbie_icons.py — значки стрика новичка (scripts/meta/newbie_streak*.gd) в art/meta/:

  newbie.png        32×32 — пункт меню «•••» и шапка экрана: листок календаря с зелёной
                    шапкой (у недельных заданий — красная) и числом «30»;
  newbie_grand.png  48×48 — крупный подарок за все 30 дней: сундук в рубине и золоте под
                    золотым замком, с алмазом на крышке. Подарок пока не придуман (заглушка),
                    поэтому значок только закрытый.

Плейсхолдер уровня «программист нарисовал аккуратно», не работа художника. Те же приёмы,
что у tools/gen_meta_icons.py: палитра проекта (tools/gen_art.py), без сглаживания, тёмная
обводка в один пиксель. Идемпотентно: повторный запуск даёт те же PNG.

Запуск:  python3 tools/gen_newbie_icons.py [--sheet /путь/лист.png]
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_art import C, shade  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "meta")
RIM = (0x17, 0x13, 0x0F, 255)
WHITE = (255, 255, 255, 255)

# Цифры 3×5 (как на табло): рисуются с увеличением.
DIGITS = {
	"0": ["111", "101", "101", "101", "111"],
	"3": ["111", "001", "011", "001", "111"],
}


def rect(img, x0, y0, x1, y1, col):
	ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill=col)


def poly(img, pts, col):
	ImageDraw.Draw(img).polygon(pts, fill=col)


def ell(img, cx, cy, rx, ry, col):
	ImageDraw.Draw(img).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=col)


def line(img, pts, col, w=1):
	ImageDraw.Draw(img).line(pts, fill=col, width=w)


def dot(img, x, y, col):
	if 0 <= x < img.width and 0 <= y < img.height:
		img.putpixel((x, y), col)


def sparkle(img, x, y, col=WHITE, big=False):
	pts = ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
	if big:
		pts += ((2, 0), (-2, 0), (0, 2), (0, -2))
	for dx, dy in pts:
		dot(img, x + dx, y + dy, col)


def text(img, s, x, y, scale, col):
	for ch in s:
		rows = DIGITS[ch]
		for ry, row in enumerate(rows):
			for rx, bit in enumerate(row):
				if bit == "1":
					rect(img, x + rx * scale, y + ry * scale, x + (rx + 1) * scale - 1, y + (ry + 1) * scale - 1, col)
		x += 4 * scale


def finish(img):
	"""Обводка в один пиксель по четырём соседям — как у значков gen_meta_icons."""
	src = img.copy()
	px, dst = src.load(), img.load()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			if px[x, y][3] > 0:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0:
					dst[x, y] = RIM
					break
	return img


def g_newbie():
	img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
	rect(img, 4, 6, 27, 28, C("parchment"))
	rect(img, 4, 26, 27, 28, C("parchment_border"))         # тень нижнего края листа
	rect(img, 4, 6, 27, 12, C("emerald_base"))
	rect(img, 4, 6, 27, 7, C("emerald_light"))
	rect(img, 4, 12, 27, 12, shade(C("emerald_base"), 0.75))
	for x in (9, 21):
		rect(img, x, 2, x + 2, 9, C("iron_tool"))
		rect(img, x, 2, x, 9, shade(C("iron_tool"), 1.25))
	text(img, "30", 8, 15, 2, C("soil_shadow"))
	dot(img, 26, 25, C("gold_light"))                       # загнутый уголок листа
	poly(img, [(23, 28), (27, 24), (27, 28)], C("parchment_border"))
	poly(img, [(23, 28), (27, 24), (23, 24)], shade(C("parchment"), 0.92))
	sparkle(img, 28, 3, C("gold_light"))
	return finish(img)


def g_newbie_grand():
	img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
	body, light, dark = C("ruby_base"), C("ruby_light"), shade(C("ruby_base"), 0.7)
	gold, gold_l, gold_d = C("gold_base"), C("gold_light"), shade(C("gold_base"), 0.75)
	# Корпус сундука.
	rect(img, 6, 24, 41, 42, body)
	rect(img, 6, 24, 9, 42, light)
	rect(img, 38, 24, 41, 42, dark)
	rect(img, 6, 40, 41, 42, dark)
	# Крышка-купол.
	poly(img, [(6, 24), (8, 16), (14, 11), (34, 11), (40, 16), (42, 24)], light)
	poly(img, [(8, 21), (10, 16), (15, 13), (33, 13), (38, 16), (40, 21)], body)
	rect(img, 6, 22, 41, 24, gold)
	rect(img, 6, 22, 41, 22, gold_l)
	rect(img, 6, 25, 41, 25, gold_d)
	# Золотые полосы-оковки.
	for x in (12, 33):
		rect(img, x, 12, x + 2, 42, gold)
		rect(img, x, 12, x, 42, gold_l)
		rect(img, x + 2, 12, x + 2, 42, gold_d)
	rect(img, 6, 39, 41, 39, gold_d)
	# Алмаз на крышке.
	poly(img, [(20, 9), (22, 6), (26, 6), (28, 9)], C("diamond_light"))
	poly(img, [(20, 9), (28, 9), (24, 15)], C("diamond_base"))
	poly(img, [(20, 9), (24, 9), (24, 15)], shade(C("diamond_base"), 0.82))
	dot(img, 22, 7, WHITE)
	# Замок: дужка и корпус с замочной скважиной.
	line(img, [(19, 28), (19, 24), (21, 21), (27, 21), (29, 24), (29, 28)], C("iron_tool"), 2)
	rect(img, 16, 27, 31, 39, gold)
	rect(img, 16, 27, 31, 28, gold_l)
	rect(img, 16, 38, 31, 39, gold_d)
	rect(img, 16, 27, 17, 39, gold_l)
	ell(img, 23.5, 32, 2, 2, C("hair"))
	rect(img, 23, 33, 24, 36, C("hair"))
	# Блеск.
	sparkle(img, 41, 8, WHITE, big=True)
	sparkle(img, 5, 14, C("gold_light"))
	sparkle(img, 44, 30, C("gold_light"))
	return finish(img)


ICONS = {"newbie": g_newbie, "newbie_grand": g_newbie_grand}


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	for name, fn in ICONS.items():
		fn().save(os.path.join(OUT_DIR, f"{name}.png"))
	print(f"Готово: {len(ICONS)} значка в art/meta/ ({', '.join(ICONS)})")
	if "--sheet" in sys.argv:
		path = sys.argv[sys.argv.index("--sheet") + 1]
		sheet = Image.new("RGBA", (360, 210), (46, 36, 28, 255))
		x = 6
		for name in ICONS:
			im = Image.open(os.path.join(OUT_DIR, f"{name}.png"))
			im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
			sheet.paste(im, (x, 6), im)
			x += im.width + 10
		sheet.save(path)


if __name__ == "__main__":
	main()
