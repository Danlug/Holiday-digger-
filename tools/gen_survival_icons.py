#!/usr/bin/env python3
"""gen_survival_icons.py — значки-статусы у полосок голода и бодрости (раунд 5, ГДД §7).

Что показывают (слова — только в подсказке Tip, на экране значок):
  st_slow  — улитка: «медленнее» (бодрость ≤25%: ходьба, копка, прыжок);
  st_weak  — кирка со стрелкой вниз: «слабее» (сытость ≤25%: копка, удача);
  st_dizzy — завиток со звёздочками: «шатает» (бодрость на нуле);
  st_drain — сердце с каплей: «здоровье тает» (сытость на нуле).

Рисунок 10×10 текстом (одна буква — один пиксель), палитра и автообводка — как у
tools/gen_ui_icons.py (его PAL), в файл кладётся увеличенная вдвое версия 20×20:
на полоске значок показан в 10 проектных единиц, пиксель рисунка = единица экрана,
та же плотность, что у иконок полосок. Это заглушки уровня «программист нарисовал
аккуратно», не работа художника. Руками PNG не правим:

    python3 tools/gen_survival_icons.py [контактный_лист.png]

Результат: art/ui/icons/st_*.png (UiIcons.tex("st_slow")).
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_ui_icons import PAL  # noqa: E402  — общая палитра значков интерфейса

OUT = os.path.join(HERE, "..", "art", "ui", "icons")
N = 10

ICONS = {}


def icon(name, rows):
	ICONS[name] = rows.strip("\n").split("\n")


# Улитка: раковина-завиток золотом, тело зелёное, рожки с точками глаз.
icon("st_slow", """
..........
.k.k......
.e.e.ooo..
.eeeoGGGo.
eeeeoGkgo.
eeeeoGGko.
.eeeeoooe.
.EEEEEEEEE
..........
..........
""")

# Кирка (сталь и рукоять) и красная стрелка вниз — «копает слабее».
icon("st_weak", """
..........
..sSSSs...
.S..M..S..
...M...S..
..M.......
.M....RR..
M.....RR..
.....RRRR.
......RR..
..........
""")

# Звёздочки, кружащие по орбите над головой, — мультяшное «голова кругом».
icon("st_dizzy", """
..........
..g.......
.gGg......
..gbbbbb..
.b......b.
.b......b.
..bbbbbg..
......gGg.
.......g..
..........
""")

# Сердце и капля под ним — «здоровье утекает».
icon("st_drain", """
..........
.RR..RR...
RrRRRRRR..
RrRRRRRD..
RRRRRRRD..
.RRRRRD...
..RRRD..R.
...RD..RrR
.......RRR
........D.
""")


def render(rows):
	img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
	px = img.load()
	for y, row in enumerate(rows):
		for x, ch in enumerate(row):
			c = PAL[ch]
			if c is not None:
				px[x, y] = c + (255,)
	# автообводка: прозрачный пиксель рядом (по четырём сторонам) с закрашенным
	src = img.copy().load()
	for y in range(N):
		for x in range(N):
			if src[x, y][3] != 0:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if 0 <= nx < N and 0 <= ny < N and src[nx, ny][3] != 0:
					px[x, y] = PAL["K"] + (255,)
					break
	return img.resize((N * 2, N * 2), Image.NEAREST)


def build(sheet_path=None):
	os.makedirs(OUT, exist_ok=True)
	errors = 0
	imgs = {}
	for name in sorted(ICONS):
		rows = ICONS[name]
		if len(rows) != N or any(len(r) != N for r in rows):
			print("ОШИБКА размера:", name, len(rows), [len(r) for r in rows])
			errors += 1
			continue
		bad = {ch for r in rows for ch in r if ch not in PAL}
		if bad:
			print("ОШИБКА буквы:", name, bad)
			errors += 1
			continue
		imgs[name] = render(rows)
		imgs[name].save(os.path.join(OUT, name + ".png"))
	if errors:
		sys.exit(1)
	print("значков:", len(imgs))
	if sheet_path:
		cell = N * 2 * 6 + 16
		sheet = Image.new("RGBA", (len(imgs) * cell, cell), (0x2A, 0x20, 0x18, 255))
		for i, name in enumerate(sorted(imgs)):
			big = imgs[name].resize((N * 2 * 6, N * 2 * 6), Image.NEAREST)
			sheet.alpha_composite(big, (i * cell + 8, 8))
		sheet.save(sheet_path)


if __name__ == "__main__":
	build(sys.argv[1] if len(sys.argv) > 1 else None)
