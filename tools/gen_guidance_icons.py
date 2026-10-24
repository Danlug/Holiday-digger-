#!/usr/bin/env python3
"""gen_guidance_icons.py — значки экрана «Проекты» (ветка guidance, раунд 4).

Тот же приём, что у tools/gen_ui_icons.py: рисунок 16×16 буквами (одна буква —
один пиксель), обводка добавляется сама, в файл кладётся увеличенная вдвое
версия 32×32 — на экране при 16 единицах один пиксель рисунка равен одной
единице, как у остальных значков меню.

Заглушки уровня «программист нарисовал аккуратно», не работа художника.
Руками PNG не правим — меняем рисунок здесь и запускаем:

    python3 tools/gen_guidance_icons.py [контактный_лист.png]

Результат: art/guidance/<имя>.png.
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "art", "guidance")

PAL = {
	".": None,
	"K": (0x1A, 0x13, 0x0D),   # обводка
	"G": (0xE0, 0xA9, 0x3B),   # золото
	"g": (0xF5, 0xD0, 0x6B),
	"o": (0xA0, 0x6F, 0x1E),
	"B": (0x3F, 0x6E, 0x9A),   # синька чертежа
	"b": (0x8C, 0xB8, 0xD8),
	"n": (0x24, 0x40, 0x5E),
	"S": (0x9A, 0xA3, 0xAD),   # сталь
	"s": (0xCD, 0xD5, 0xDC),
	"t": (0x5D, 0x66, 0x70),
	"R": (0xC4, 0x52, 0x4A),   # красный
	"r": (0xE8, 0x8C, 0x80),
	"D": (0x7E, 0x2E, 0x2A),
	"W": (0xF2, 0xE6, 0xC8),
	"k": (0x1A, 0x13, 0x0D),
}

ICONS = {}


def icon(name, rows):
	ICONS[name] = rows.strip("\n").split("\n")


# Пункт меню «Проекты»: чертёж-синька с золотым буровым наконечником — «что
# собираем и из чего».
icon("projects", """
................
.nnnnnnnnnnnnnn.
.nBBBBBBBBBBBBn.
.nBbbbbbbbbbbBn.
.nBbBBBssBBBbBn.
.nBbBBsSStBBbBn.
.nBbBGGGGGGBbBn.
.nBbBBgGGoBBbBn.
.nBbBBgGGoBBbBn.
.nBbBBBgGBBBbBn.
.nBbBBBGoBBBbBn.
.nBbBBBBGBBBbBn.
.nBbbbbbbbbbbBn.
.nBBBBBBBBBBBBn.
.nnnnnnnnnnnnnn.
................
""")

# «Следить»: булавка — проект приколот к экрану (трекер на HUD).
icon("track", """
................
......RRRR......
.....RrrRRD.....
....RrrRRRRD....
....RrRRRRRD....
....RRRWWRRD....
....RRRWWRRD....
....DRRRRRDD....
.....DRRRRD.....
......DRRD......
.......SS.......
.......St.......
.......St.......
.......St.......
........t.......
................
""")

icon("track_off", """
................
......SSSS......
.....SssSSt.....
....SssSSSSt....
....SsSSSSSt....
....SSSttSSt....
....SSSttSSt....
....tSSSSStt....
.....tSSSSt.....
......tSSt......
.......SS.......
.......St.......
.......St.......
.......St.......
........t.......
................
""")


def render(rows):
	img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
	px = img.load()
	for y, row in enumerate(rows):
		for x, ch in enumerate(row):
			c = PAL[ch]
			if c is not None:
				px[x, y] = c + (255,)
	src = img.copy().load()
	for y in range(16):
		for x in range(16):
			if src[x, y][3] != 0:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if 0 <= nx < 16 and 0 <= ny < 16 and src[nx, ny][3] != 0:
					px[x, y] = PAL["K"] + (255,)
					break
	return img.resize((32, 32), Image.NEAREST)


def build(sheet_path=None):
	os.makedirs(OUT, exist_ok=True)
	imgs = []
	for name in sorted(ICONS):
		rows = ICONS[name]
		if len(rows) != 16 or any(len(r) != 16 for r in rows):
			sys.exit("ОШИБКА размера: %s" % name)
		for r in rows:
			for ch in r:
				if ch not in PAL:
					sys.exit("ОШИБКА буквы: %s %r" % (name, ch))
		big = render(rows)
		big.save(os.path.join(OUT, name + ".png"))
		imgs.append(big)
	print("значков:", len(imgs))
	if sheet_path:
		cell = 32 * 5 + 16
		sheet = Image.new("RGBA", (len(imgs) * cell, cell), (0x2A, 0x20, 0x18, 255))
		for i, im in enumerate(imgs):
			sheet.alpha_composite(im.resize((160, 160), Image.NEAREST), (i * cell + 8, 8))
		sheet.save(sheet_path)


if __name__ == "__main__":
	build(sys.argv[1] if len(sys.argv) > 1 else None)
