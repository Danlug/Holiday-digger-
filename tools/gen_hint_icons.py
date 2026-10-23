#!/usr/bin/env python3
"""gen_hint_icons.py — значки системы подсказок («знакомство с играми») в art/hints/.

Тот же приём, что в tools/gen_ui_icons.py: рисунок — текстовая сетка (одна буква —
один пиксель), обводка добавляется сама, в файл кладётся увеличенная вдвое
версия: на экране один пиксель рисунка равен одной проектной единице.
Размеры сеток разные (палец 16×20, стрелка 10×13, «!» 7×9, «new» 19×9, лампочка 16×16).

Это заглушки уровня «программист нарисовал аккуратно», не работа художника.
Руками PNG не правим — меняй рисунок здесь и запускай:

    python3 tools/gen_hint_icons.py [путь_к_контактному_листу.png]

Результат: art/hints/<имя>.png (+ .import делает Godot при переимпорте).
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "art", "hints")

PAL = {
	".": None,
	"K": (0x1A, 0x13, 0x0D),   # обводка
	"W": (0xF2, 0xE6, 0xC8),
	"G": (0xE0, 0xA9, 0x3B),   # золото
	"g": (0xF5, 0xD0, 0x6B),
	"o": (0xA0, 0x6F, 0x1E),
	"R": (0xD0, 0x45, 0x3C),   # красный бейджа (как UiBtn.set_badge)
	"r": (0xF0, 0x8A, 0x7C),
	"D": (0x8E, 0x2A, 0x26),
	"p": (0xE9, 0xBE, 0x92),   # кожа
	"h": (0xF8, 0xDB, 0xBC),
	"q": (0xC0, 0x8E, 0x64),
	"c": (0xCC, 0x5A, 0x3A),   # рукав (рубашка героя)
	"C": (0x9C, 0x40, 0x28),
	"S": (0x9A, 0xA3, 0xAD),   # сталь, серый
	"s": (0xCD, 0xD5, 0xDC),
	"t": (0x5D, 0x66, 0x70),
	"E": (0x7F, 0xB8, 0x6B),
	"e": (0xB4, 0xE0, 0x9C),
	"f": (0x4A, 0x7A, 0x3E),
}

ICONS = {}


def icon(name, rows, outline=True):
	rows = rows.strip("\n").split("\n")
	ICONS[name] = (rows, outline)


# Палец-указатель (как курсор-«рука»): указательный вверх, три сжатых пальца
# ступенькой, большой слева, рукав. Три пальца должны читаться отдельными
# бугорками, иначе рука выглядит как неприличный жест.
icon("finger", """
.................
......hp.........
.....hppq........
.....hppq........
.....hppq........
.....hppq........
.....hppqhpq.....
.....hppqhpqhpq..
..hp.hppqhpqhpqhp
.hppqhpppppppppqq
.hppphppppppppppq
.hppppppppppppppq
..hppppppppppppq.
..qpppppppppppq..
...qppppppppppq..
....qqpppppppq...
.....qqqqqqqqq...
.....cccccccc....
.....ccccccCC....
.....CCCCCCCC....
""")

# Стрелка вниз (поворачивается кодом на любую сторону).
icon("arrow", """
...GGGG...
...gGGo...
...gGGo...
...gGGo...
...gGGo...
GGGgGGoGGo
.GgGGGGGo.
..GgGGGo..
...GgGo...
....Go....
""")

# Красный кружок с «!» — на кнопке «•••» и на плитке, где есть что-то новое.
icon("bang", """
..RRRRR..
.RrRRRRD.
RrRRWRRRD
RRRRWRRRD
RRRRWRRRD
RRRRWRRRD
RRRRRRRRD
RRRRWRRRD
.RRRRRRD.
..DDDDD..
""")

# Ярлык «NEW» на плитке меню: красная плашка и пиксельные буквы.
icon("new", """
RRRRRRRRRRRRRRRRRRR
RrrrrrrrrrrrrrrrrrD
RrWRRWRWWWRWRRRWrRD
RrWWRWRWRRRWRRRWrRD
RrWRWWRWWRRWRWRWrRD
RrWRRWRWRRRWWRWWrRD
RrWRRWRWWWRWRRRWrRD
RDDDDDDDDDDDDDDDDDD
""")

# Лампочка: настройка «подсказки» включена / выключена.
icon("bulb_on", """
................
................
.....gGGGg......
....gGWWGGo.....
...gGWGGGGGo....
...GGWGGGGGo....
...GGGGGGGGo....
...GGGGGGGGo....
....GGGGGGo.....
.....GGGGo......
.....sSSSt......
.....sSSSt......
......StT.......
................
................
................
""".replace("T", "t"))

icon("bulb_off", """
................
................
.....sSSSs......
....sSsSSSt.....
...sSsSSSSSt....
...SSsSSSSSt....
...SSSSSSSSt....
...SSSSSSSSt....
....SSSSSSt.....
.....SSSSt......
.....sSSSt......
.....sSSSt......
......StS.......
................
................
................
""".replace("S", "t").replace("s", "S").replace("T", "t"))

# Стрелка по кругу: «показать подсказки заново».
icon("replay", """
................
................
.....GGGGG......
...GGg...gGG....
..GGg.....gGG...
..Gg...GGGGGGG..
.GG.....GGGGG...
.Go......GGG....
.Go.......G.....
.GG.............
..GG.........G..
..GGG.......GG..
...GGGGgggGGG...
.....GGGGGG.....
................
................
""")


def build(sheet_path=None):
	os.makedirs(OUT, exist_ok=True)
	errors = 0
	imgs = {}
	for name, (rows, outline) in sorted(ICONS.items()):
		w, h = len(rows[0]), len(rows)
		if any(len(r) != w for r in rows):
			print("ОШИБКА ширины строк:", name, [len(r) for r in rows])
			errors += 1
			continue
		# +1 пиксель по краям под обводку
		img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
		px = img.load()
		for y, row in enumerate(rows):
			for x, ch in enumerate(row):
				if ch not in PAL:
					print("ОШИБКА буквы:", name, repr(ch))
					errors += 1
					continue
				c = PAL[ch]
				if c is not None:
					px[x + 1, y + 1] = c + (255,)
		if outline:
			src = img.copy().load()
			for y in range(h + 2):
				for x in range(w + 2):
					if src[x, y][3] != 0:
						continue
					for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
						nx, ny = x + dx, y + dy
						if 0 <= nx < w + 2 and 0 <= ny < h + 2 and src[nx, ny][3] != 0:
							px[x, y] = PAL["K"] + (255,)
							break
		big = img.resize(((w + 2) * 2, (h + 2) * 2), Image.NEAREST)
		big.save(os.path.join(OUT, name + ".png"))
		imgs[name] = big
	if errors:
		sys.exit(1)
	print("значков:", len(ICONS))
	if sheet_path:
		names = sorted(imgs)
		cell = 200
		sheet = Image.new("RGBA", (cell * 4, cell * ((len(names) + 3) // 4)), (0x2A, 0x20, 0x18, 255))
		for i, name in enumerate(names):
			big = imgs[name]
			k = min(6, (cell - 16) // max(big.width, big.height))
			big = big.resize((big.width * k, big.height * k), Image.NEAREST)
			sheet.alpha_composite(big, ((i % 4) * cell + 8, (i // 4) * cell + 8))
		sheet.save(sheet_path)


if __name__ == "__main__":
	build(sys.argv[1] if len(sys.argv) > 1 else None)
