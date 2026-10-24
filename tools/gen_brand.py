#!/usr/bin/env python3
"""Фирменная графика веб-оболочки «Раскопки на каникулах» -> art/brand/.

Что получается:
  logo.png                       кирка + самородок + название (родной размер, масштабируется целым числом)
  tap.png, rotate.png            значок «нажмите» и значок «поверни телефон»
  treeline.png, soil.png         полоса сосен (повтор по X) и плитка земли с вкраплениями — фон экрана загрузки
  cloud_1.png, cloud_2.png       облака
  pixel_font.woff                пиксельный шрифт (кириллица, цифры, знаки) — только если стоит fontTools
  icon-192/512.png, icon-maskable-512.png, apple-touch-icon.png, favicon-32.png, favicon.ico

Всё рисуется кодом, руками PNG не правим. Это аккуратная замена-заглушка «программист нарисовал»,
не работа художника владельца: при желании файлы заменяются одноимёнными.
Шрифт читается из GLYPHS ниже: 5x7, прописные; строчные буквы в шрифте — те же глифы.

Запуск: python3 tools/gen_brand.py [--preview файл.png]
Каталог art/brand/ закрыт файлом .gdignore: Godot его не импортирует и в пак не кладёт.
"""
import math
import pathlib
import random
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "brand"


def hexc(h, a=255):
	h = h.lstrip("#")
	return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# Цвета — из art/PALETTE.md; несколько своих (небо, хвоя) там, где в палитре игры нет подходящих.
C = {
	"ink": hexc("#150E09"),
	"soil_shadow": hexc("#3E2A1A"), "soil_base": hexc("#6B4428"),
	"soil_light": hexc("#8F6238"), "soil_warm": hexc("#B4854E"),
	"stone_shadow": hexc("#3A3A44"), "stone_base": hexc("#5C5C68"), "stone_light": hexc("#7E7E8C"),
	"gold_base": hexc("#E8B32E"), "gold_light": hexc("#FFE066"), "gold_hi": hexc("#FFF3B0"),
	"copper_base": hexc("#C2703A"), "copper_light": hexc("#E89A5E"),
	"steel": hexc("#9AA6BC"), "steel_dark": hexc("#5C6A84"), "steel_light": hexc("#F4F7FA"),
	"diamond": hexc("#6FE0D8"), "ruby": hexc("#C21E3A"),
	"parchment": hexc("#E8D8B0"), "parchment_border": hexc("#A4835A"),
	"ui_dark": hexc("#241E2C"), "skin": hexc("#F2CDA0"), "skin_shadow": hexc("#D4A070"),
	"grass": hexc("#4F7A34"), "grass_dark": hexc("#365423"), "grass_light": hexc("#7FA84A"),
	"pine_far": hexc("#3F6B58"), "pine_far_hi": hexc("#4F7F68"),
	"pine_near": hexc("#1F3F2A"), "pine_near_hi": hexc("#2F5A38"),
	"cloud": hexc("#F4F7FA"), "cloud_shadow": hexc("#BCD0E6"),
}


class Px:
	"""Холст в родных пикселях: без сглаживания, всё через set()."""

	def __init__(self, w, h, fill=(0, 0, 0, 0)):
		self.w, self.h = w, h
		self.im = Image.new("RGBA", (w, h), fill)
		self.px = self.im.load()

	def set(self, x, y, c):
		x, y = int(x), int(y)
		if 0 <= x < self.w and 0 <= y < self.h:
			self.px[x, y] = c

	def get(self, x, y):
		if 0 <= x < self.w and 0 <= y < self.h:
			return self.px[x, y]
		return (0, 0, 0, 0)

	def rect(self, x, y, w, h, c):
		for j in range(h):
			for i in range(w):
				self.set(x + i, y + j, c)

	def disc(self, cx, cy, r, c):
		for j in range(int(cy - r - 1), int(cy + r + 2)):
			for i in range(int(cx - r - 1), int(cx + r + 2)):
				if (i + 0.5 - cx) ** 2 + (j + 0.5 - cy) ** 2 <= r * r:
					self.set(i, j, c)

	def opaque(self, x, y):
		return self.get(x, y)[3] > 0

	def outline(self, c, diag=True):
		"""Контур на прозрачных пикселях рядом с залитыми."""
		add = []
		for y in range(-1, self.h + 1):
			for x in range(-1, self.w + 1):
				if self.opaque(x, y):
					continue
				nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
				if diag:
					nb += [(1, 1), (-1, 1), (1, -1), (-1, -1)]
				if any(self.opaque(x + dx, y + dy) for dx, dy in nb):
					add.append((x, y))
		for x, y in add:
			self.set(x, y, c)

	def paste(self, other, x, y):
		self.im.alpha_composite(other.im, (x, y))
		self.px = self.im.load()

	def save(self, path, scale=1):
		im = self.im if scale == 1 else self.im.resize((self.w * scale, self.h * scale), Image.NEAREST)
		im.save(path, optimize=True)


def rows_to_px(rows, legend):
	p = Px(max(len(r) for r in rows), len(rows))
	for y, r in enumerate(rows):
		for x, ch in enumerate(r):
			if ch in legend:
				p.set(x, y, C[legend[ch]] if isinstance(legend[ch], str) else legend[ch])
	return p


# ---------------------------------------------------------------- шрифт

# Общие глифы: одинаковые по начертанию латинские и кириллические буквы.
_A = (".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#")
_B = ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.")
_E = ("#####", "#....", "#....", "####.", "#....", "#....", "#####")
_K = ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#")
_M = ("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#")
_H = ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#")
_O = (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.")
_P = ("####.", "#...#", "#...#", "####.", "#....", "#....", "#....")
_S = (".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.")
_T = ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..")
_X = ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#")

GLYPHS = {
	"А": _A, "В": _B, "Е": _E, "К": _K, "М": _M, "Н": _H, "О": _O, "Р": _P, "С": _S, "Т": _T, "Х": _X,
	"Б": ("#####", "#....", "#....", "####.", "#...#", "#...#", "####."),
	"Г": ("#####", "#....", "#....", "#....", "#....", "#....", "#...."),
	"Д": (".####", ".#..#", ".#..#", ".#..#", ".#..#", "#####", "#...#"),
	"Ж": ("#.#.#", "#.#.#", ".###.", "..#..", ".###.", "#.#.#", "#.#.#"),
	"З": (".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."),
	"И": ("#...#", "#...#", "#..##", "#.#.#", "##..#", "#...#", "#...#"),
	"Й": ("#.#.#", ".###.", "#..##", "#.#.#", "##..#", "#...#", "#...#"),
	"Л": ("..###", ".#..#", ".#..#", ".#..#", ".#..#", "#...#", "#...#"),
	"П": ("#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#"),
	"У": ("#...#", "#...#", "#...#", ".####", "....#", "#...#", ".###."),
	"Ф": ("..#..", ".###.", "#.#.#", "#.#.#", "#.#.#", ".###.", "..#.."),
	"Ц": ("#..#.", "#..#.", "#..#.", "#..#.", "#..#.", "#####", "....#"),
	"Ч": ("#...#", "#...#", "#...#", ".####", "....#", "....#", "....#"),
	"Ш": ("#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#####"),
	"Щ": ("#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#####", "....#"),
	"Ъ": ("##...", ".#...", ".#...", ".###.", ".#..#", ".#..#", ".###."),
	"Ы": ("#....#", "#....#", "#....#", "###..#", "#..#.#", "#..#.#", "###..#"),
	"Ь": ("#...", "#...", "#...", "###.", "#..#", "#..#", "###."),
	"Э": (".###.", "#...#", "....#", ".####", "....#", "#...#", ".###."),
	"Ю": ("#..##.", "#.#..#", "#.#..#", "###..#", "#.#..#", "#.#..#", "#..##."),
	"Я": (".####", "#...#", "#...#", ".####", ".#..#", "#...#", "#...#"),
	"0": (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
	"1": ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
	"2": (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
	"3": (".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."),
	"4": ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
	"5": ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
	"6": ("..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."),
	"7": ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
	"8": (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
	"9": (".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."),
	".": (".", ".", ".", ".", ".", ".", "#"),
	",": ("..", "..", "..", "..", ".#", ".#", "#."),
	"!": ("#", "#", "#", "#", "#", ".", "#"),
	"?": (".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."),
	":": (".", ".", "#", ".", ".", "#", "."),
	"-": ("...", "...", "...", "###", "...", "...", "..."),
	"%": ("##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"),
	"/": ("....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."),
	"…": (".....", ".....", ".....", ".....", ".....", ".....", "#.#.#"),
	" ": ("...", "...", "...", "...", "...", "...", "..."),
}
# Ё рисуется как Е — глифа с двумя точками над буквой в 5x7 нет.
ALIASES = {"Ё": "Е", "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М", "O": "О",
	"P": "Р", "T": "Т", "X": "Х"}


def glyph_for(ch):
	ch = ch.upper()
	ch = ALIASES.get(ch, ch)
	return GLYPHS.get(ch, GLYPHS[" "])


def text_cells(text, gap=1):
	"""Список (x, y) включённых клеток шрифта и ширина текста в клетках."""
	cells = []
	x = 0
	for ch in text:
		g = glyph_for(ch)
		for y, row in enumerate(g):
			for i, c in enumerate(row):
				if c == "#":
					cells.append((x + i, y))
		x += len(g[0]) + gap
	return cells, x - gap


def build_font(path):
	try:
		from fontTools.fontBuilder import FontBuilder
		from fontTools.pens.ttGlyphPen import TTGlyphPen
	except ImportError:
		print("fontTools не найден — шрифт не пересобран (pip install fonttools); остался прежний файл")
		return False
	px = 100  # одна клетка шрифта = 100 единиц; em = 1000, значит font-size 10*N px даёт клетку N px
	order = [".notdef"]
	cmap = {}
	metrics = {}

	def make(rows, extra=2):
		pen = TTGlyphPen(None)
		for y, row in enumerate(rows):
			x = 0
			while x < len(row):
				if row[x] != "#":
					x += 1
					continue
				x2 = x
				while x2 < len(row) and row[x2] == "#":
					x2 += 1
				top = (7 - y) * px + extra
				bottom = (7 - y - 1) * px
				pen.moveTo((x * px, bottom))
				pen.lineTo((x * px, top))
				pen.lineTo((x2 * px + extra, top))
				pen.lineTo((x2 * px + extra, bottom))
				pen.closePath()
				x = x2
		return pen.glyph()

	glyphs = {".notdef": make(("#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#####"))}
	metrics[".notdef"] = (6 * px, 0)
	names = {}
	for ch, rows in GLYPHS.items():
		name = "uni%04X" % ord(ch) if ch != " " else "space"
		names[ch] = name
		order.append(name)
		glyphs[name] = make(rows)
		metrics[name] = ((len(rows[0]) + 1) * px, 0)
		cmap[ord(ch)] = name
		if ch.lower() != ch.upper():
			cmap[ord(ch.lower())] = name
	for src, dst in ALIASES.items():
		cmap[ord(src)] = names[dst]
		if src.lower() != src.upper():
			cmap[ord(src.lower())] = names[dst]
	fb = FontBuilder(1000, isTTF=True)
	fb.setupGlyphOrder(order)
	fb.setupCharacterMap(cmap)
	fb.setupGlyf(glyphs)
	fb.setupHorizontalMetrics(metrics)
	fb.setupHorizontalHeader(ascent=800, descent=-200)
	fb.setupNameTable({"familyName": "RaskopkiPixel", "styleName": "Regular"})
	fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, sxHeight=700, sCapHeight=700)
	fb.setupPost()
	# фиксированные даты: иначе каждая сборка даёт другой файл, и web/shell.html «устаревает» на пустом месте
	fb.font["head"].created = fb.font["head"].modified = 3600 * 24 * 365 * 120
	fb.font.flavor = "woff"
	fb.save(str(path))
	return True


# ---------------------------------------------------------------- эмблема: кирка и самородок

def draw_pickaxe(p, s):
	"""Кирка наискось: рукоять «/», голова — дуга сверху справа. Координаты в сетке 34, умножаются на s."""
	k = s / 34.0
	d = (math.cos(math.radians(-45)), math.sin(math.radians(-45)))
	n = (-d[1], d[0])
	p0 = (3.5 * k, 31 * k)
	top = (24 * k, 10.5 * k)
	half = 1.7 * k + 0.4
	for y in range(p.h):
		for x in range(p.w):
			cx, cy = x + 0.5, y + 0.5
			# проекция точки на ось рукояти
			vx, vy = cx - p0[0], cy - p0[1]
			along = vx * d[0] + vy * d[1]
			across = vx * n[0] + vy * n[1]
			L = (top[0] - p0[0]) * d[0] + (top[1] - p0[1]) * d[1]
			if 0 <= along <= L + 1.2 * k and abs(across) <= half:
				if across < -half * 0.35:
					col = C["soil_warm"]
				elif across > half * 0.35:
					col = C["soil_shadow"]
				else:
					col = C["soil_light"]
				p.set(x, y, col)
	# голова: дуга с утончением к кончикам
	R = 14.0 * k
	cx_, cy_ = top[0] - d[0] * (R - 3.2 * k), top[1] - d[1] * (R - 3.2 * k)
	theta0 = math.atan2(d[1], d[0])
	span = math.radians(62)
	pts = []
	steps = 240
	for i in range(steps + 1):
		t = -span + 2 * span * i / steps
		r = (2.1 * (1 - abs(t) / span) + 0.75) * max(k, 0.8)
		a = theta0 + t
		pts.append((cx_ + R * math.cos(a), cy_ + R * math.sin(a), r))
	shape = {}
	for (x, y, r) in pts:
		for j in range(int(y - r - 1), int(y + r + 2)):
			for i in range(int(x - r - 1), int(x + r + 2)):
				if (i + 0.5 - x) ** 2 + (j + 0.5 - y) ** 2 <= r * r:
					shape[(i, j)] = True
	for (i, j) in shape:
		dist = math.hypot(i + 0.5 - cx_, j + 0.5 - cy_) - R
		if dist > 0.55 * max(k, 0.8):
			col = C["steel_light"]
		elif dist < -0.7 * max(k, 0.8):
			col = C["steel_dark"]
		else:
			col = C["steel"]
		p.set(i, j, col)


def draw_nugget(p, cx, cy, s):
	"""Самородок: многоугольник с гранями; (cx, cy) — центр, s — ширина в пикселях."""
	k = s / 18.0
	base = [(2, 9), (1, 6), (4, 3), (8, 1), (12, 2), (15, 4), (17, 7), (16, 11), (12, 13), (6, 13), (3, 12)]
	light = [(4, 4), (8, 2), (12, 3), (8, 6), (5, 8)]
	dark = [(17, 7), (16, 11), (12, 13), (9, 12), (13, 9), (15, 6)]
	mid = [(5, 8), (8, 6), (12, 3), (15, 5), (13, 9), (9, 12), (5, 11)]

	def tr(poly):
		return [(cx + (x - 9) * k, cy + (y - 7) * k) for x, y in poly]

	layer = Image.new("RGBA", (p.w, p.h), (0, 0, 0, 0))
	dr = ImageDraw.Draw(layer)
	dr.polygon(tr(base), fill=C["gold_base"])
	dr.polygon(tr(dark), fill=C["copper_base"])
	dr.polygon(tr(mid), fill=C["gold_base"])
	dr.polygon(tr(light), fill=C["gold_light"])
	# блики и грани
	for x, y in [(6, 4), (7, 4), (5, 5), (6, 5)]:
		dr.rectangle([cx + (x - 9) * k, cy + (y - 7) * k, cx + (x - 9) * k + max(k, 1) - 1, cy + (y - 7) * k + max(k, 1) - 1], fill=C["gold_hi"])
	dr.line([(cx + (8 - 9) * k, cy + (6 - 7) * k), (cx + (9 - 9) * k, cy + (11 - 7) * k)], fill=C["copper_light"], width=1)
	p.im.alpha_composite(layer)
	p.px = p.im.load()


def sparkle(p, x, y, c=None):
	c = c or C["gold_hi"]
	for dx, dy in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
		p.set(x + dx, y + dy, c)


def emblem(size):
	"""Кирка + самородок с тёмным контуром, обрезанные по содержимому; size — сторона исходной сетки."""
	tmp = Px(size + 4, size + 4)
	pick = Px(size, size)
	draw_pickaxe(pick, size)
	tmp.paste(pick, 2, 2)
	draw_nugget(tmp, 2 + size * 0.40, 2 + size * 0.76, size * 0.52)
	tmp.outline(C["ink"])
	tmp.im = tmp.im.crop(tmp.im.getbbox())
	tmp.w, tmp.h = tmp.im.size
	tmp.px = tmp.im.load()
	return tmp


# ---------------------------------------------------------------- логотип

TITLE_GRAD = ["#FFF1A8", "#FFE066", "#E8B32E", "#E8B32E", "#D99A25", "#C2703A", "#C2703A"]


def draw_title(text, scale):
	cells, wcells = text_cells(text)
	w = wcells * scale
	h = 7 * scale
	pad = 4
	p = Px(w + pad * 2 + 2, h + pad * 2 + 3)
	mask = set()
	for (cx, cy) in cells:
		for j in range(scale):
			for i in range(scale):
				mask.add((pad + cx * scale + i, pad + cy * scale + j))
	ext = set()
	for (x, y) in mask:
		for d in (1, 2):
			ext.add((x, y + d))
	allm = mask | ext
	for (x, y) in allm:
		for dx in (-1, 0, 1):
			for dy in (-1, 0, 1):
				if (x + dx, y + dy) not in allm:
					p.set(x + dx, y + dy, C["ink"])
	for (x, y) in ext:
		if (x, y) not in mask:
			p.set(x, y, C["soil_shadow"])
	for (x, y) in mask:
		row = (y - pad) // scale
		col = hexc(TITLE_GRAD[row])
		if (x, y - 1) not in mask:
			col = C["gold_hi"]
		elif (x, y + 1) not in mask:
			col = hexc("#B8641F")
		p.set(x, y, col)
	return p


def draw_ribbon(text):
	cells, wcells = text_cells(text)
	w = wcells + 12
	h = 7 + 8
	p = Px(w, h)
	p.rect(0, 0, w, h, C["ink"])
	p.rect(1, 1, w - 2, h - 2, C["gold_base"])
	p.rect(2, 2, w - 4, h - 4, C["ui_dark"])
	for (cx, cy) in cells:
		p.set(6 + cx, 4 + cy, C["parchment"])
	for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
		p.set(x, y, (0, 0, 0, 0))
	return p


def make_logo():
	em = emblem(40)
	title = draw_title("РАСКОПКИ", 2)
	ribbon = draw_ribbon("НА КАНИКУЛАХ")
	W = max(title.w, ribbon.w, em.w) + 2
	H = em.h - 2 + title.h - 3 + ribbon.h - 2
	logo = Px(W + 2, H + 2)
	logo.paste(em, (logo.w - em.w) // 2, 0)
	sparkle(logo, logo.w // 2 - 20, 8)
	sparkle(logo, logo.w // 2 + 22, 24, C["steel_light"])
	logo.paste(title, (logo.w - title.w) // 2, em.h - 5)
	logo.paste(ribbon, (logo.w - ribbon.w) // 2, em.h - 5 + title.h - 4)
	bbox = logo.im.getbbox()
	logo.im = logo.im.crop(bbox)
	logo.w, logo.h = logo.im.size
	logo.px = logo.im.load()
	return logo


# ---------------------------------------------------------------- значки

def make_tap():
	rows = [
		"......OO........",
		".....OccO.......",
		".....OccO.......",
		".....OccO.......",
		".....OccOOO.....",
		".....OccOccOO...",
		".OO..OccOccOccO.",
		"OccOOOccscsccscO",
		"OcccOccccccccccO",
		".OcccccccccccscO",
		"..OccccccccccscO",
		"..OcccccccccccsO",
		"...OccccccccccsO",
		"...OcccccccccsO.",
		"....OccccccccsO.",
		"....OccccccccsO.",
		".....OOOOOOOOO..",
	]
	hand = rows_to_px(rows, {"O": "ink", "c": "skin", "s": "skin_shadow"})
	# светлый ореол: рука с тёмным контуром должна читаться и на тёмной земле
	halo = Px(hand.w + 2, hand.h + 2)
	halo.paste(hand, 1, 1)
	halo.outline(C["gold_hi"], diag=False)
	return halo


def make_rotate():
	"""Телефон «книжкой»: экран с мини-сценой неба и земли."""
	w, h = 14, 24
	p = Px(w, h)
	p.rect(0, 0, w, h, C["ink"])
	p.rect(1, 1, w - 2, h - 2, C["steel"])
	p.rect(2, 2, w - 4, h - 5, hexc("#62AADF"))
	p.rect(2, 12, w - 4, 2, C["grass"])
	p.rect(2, 14, w - 4, h - 17, C["soil_base"])
	p.rect(4, 15, 2, 1, C["soil_light"])
	p.rect(8, 17, 2, 1, C["gold_base"])
	p.rect(5, h - 2, 4, 1, C["steel_dark"])
	for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
		p.set(x, y, (0, 0, 0, 0))
	return p


def make_cloud(seed, w):
	rnd = random.Random(seed)
	p = Px(w, w // 2 + 4)
	base_y = p.h - 4
	for _ in range(5 + w // 14):
		cx = rnd.uniform(w * 0.18, w * 0.82)
		r = rnd.uniform(w * 0.10, w * 0.2)
		cy = base_y - r * rnd.uniform(0.5, 1.1)
		p.disc(cx, cy, r, C["cloud"])
	# плоское дно и тень снизу
	for x in range(p.w):
		for y in range(base_y, p.h):
			p.set(x, y, (0, 0, 0, 0))
	for x in range(p.w):
		for y in range(base_y - 3, base_y):
			if p.opaque(x, y):
				p.set(x, y, C["cloud_shadow"])
	return p


def make_treeline(w=96, h=44):
	rnd = random.Random(11)
	p = Px(w, h)

	def pine(cx, base, ht, wd, col, hi):
		layers = max(3, ht // 7)
		for i in range(layers):
			y0 = base - ht + int(i * ht / layers * 0.78)
			ly = int(ht / layers * 1.5)
			half = max(2, int(wd / 2 * (i + 1) / layers))
			for dy in range(ly):
				frac = dy / max(1, ly - 1)
				hw = int(1 + (half - 1) * (0.25 + 0.75 * frac))
				for dx in range(-hw, hw + 1):
					x, y = cx + dx, y0 + dy
					c = hi if dx < -hw // 3 and dy % 3 != 2 else col
					p.set(x % w, y, c)
		for y in range(base - 4, base):
			p.set(cx % w, y, col)
			p.set((cx + 1) % w, y, col)

	xs = list(range(4, w, 11))
	for x in xs:
		pine(x + rnd.randint(-2, 2), h - 8, rnd.randint(18, 26), rnd.randint(10, 13), C["pine_far"], C["pine_far_hi"])
	for x in range(10, w, 15):
		pine(x + rnd.randint(-3, 3), h - 1, rnd.randint(26, 40), rnd.randint(13, 18), C["pine_near"], C["pine_near_hi"])
	for x in range(w):
		for y in range(h - 5, h):
			p.set(x, y, C["pine_near"])
	return p


def make_soil(n=48):
	rnd = random.Random(5)
	p = Px(n, n, C["soil_base"])

	def wdisc(cx, cy, r, c):
		for j in range(-int(r) - 1, int(r) + 2):
			for i in range(-int(r) - 1, int(r) + 2):
				if (i + 0.5) ** 2 + (j + 0.5) ** 2 <= r * r:
					p.px[(int(cx) + i) % n, (int(cy) + j) % n] = c

	for _ in range(34):
		wdisc(rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(1.6, 4.2), C["soil_light"])
	for _ in range(36):
		wdisc(rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(1.0, 3.0), C["soil_shadow"])
	for _ in range(22):
		wdisc(rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(0.9, 1.8), C["soil_warm"])
	# камешки и крошки руды
	for _ in range(5):
		x, y = rnd.randrange(n), rnd.randrange(n)
		for dx, dy, c in [(0, 0, "stone_base"), (1, 0, "stone_light"), (0, 1, "stone_shadow"), (1, 1, "stone_base")]:
			p.px[(x + dx) % n, (y + dy) % n] = C[c]
	for col, cnt in (("gold_base", 3), ("copper_base", 2), ("diamond", 1)):
		for _ in range(cnt):
			x, y = rnd.randrange(n), rnd.randrange(n)
			for dx, dy in [(0, 0), (1, 0), (0, 1)]:
				p.px[(x + dx) % n, (y + dy) % n] = C[col]
			p.px[(x + 1) % n, (y + 1) % n] = C["gold_hi"] if col == "gold_base" else C["steel_light"]
	return p


# ---------------------------------------------------------------- иконки приложения

def icon_base(n, emblem_size, rnd_seed=3):
	"""Квадрат n x n в родных пикселях: земля с вкраплениями и эмблема по центру."""
	rnd = random.Random(rnd_seed)
	p = Px(n, n)
	bands = [C["soil_warm"], hexc("#9C703F"), C["soil_light"], hexc("#7A5230"), C["soil_base"], hexc("#523720"), C["soil_shadow"]]
	for y in range(n):
		b = bands[min(len(bands) - 1, y * len(bands) // n)]
		for x in range(n):
			p.set(x, y, b)
	for _ in range(n * 2):
		x, y = rnd.randrange(n), rnd.randrange(n)
		r = rnd.choice([1, 1, 2])
		p.disc(x, y, r, rnd.choice([C["soil_light"], C["soil_shadow"], C["soil_warm"]]))
	# виньетка по краям
	for y in range(n):
		for x in range(n):
			dx, dy = (x - n / 2) / (n / 2), (y - n / 2) / (n / 2)
			if dx * dx + dy * dy > 1.25:
				c = p.get(x, y)
				p.set(x, y, (c[0] * 2 // 3, c[1] * 2 // 3, c[2] * 2 // 3, 255))
	em = emblem(emblem_size)
	p.paste(em, (n - em.w) // 2, (n - em.h) // 2)
	return p


def make_icons():
	native = 64
	base = icon_base(native, 46)
	big = base.im.resize((512, 512), Image.NEAREST)
	big.save(OUT / "icon-512.png", optimize=True)
	base.im.resize((192, 192), Image.NEAREST).save(OUT / "icon-192.png", optimize=True)
	# apple-touch-icon: iOS сам скругляет углы и не любит прозрачность; 180 не кратно 64 — берём ресемпл
	big.convert("RGB").resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png", optimize=True)
	# maskable: Android обрезает до круга ~80% — эмблема меньше, фон на всю плоскость
	mask = icon_base(native, 34)
	mask.im.resize((512, 512), Image.NEAREST).save(OUT / "icon-maskable-512.png", optimize=True)
	fav = icon_base(32, 30, rnd_seed=4)
	fav.im.save(OUT / "favicon-32.png", optimize=True)
	big.resize((48, 48), Image.LANCZOS).save(OUT / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


# ---------------------------------------------------------------- сборка

def main():
	OUT.mkdir(parents=True, exist_ok=True)
	(OUT / ".gdignore").write_text("", encoding="utf-8")
	logo = make_logo()
	logo.save(OUT / "logo.png")
	make_tap().save(OUT / "tap.png")
	make_rotate().save(OUT / "rotate.png")
	make_treeline().save(OUT / "treeline.png")
	make_soil().save(OUT / "soil.png")
	make_cloud(1, 44).save(OUT / "cloud_1.png")
	make_cloud(2, 30).save(OUT / "cloud_2.png")
	make_icons()
	build_font(OUT / "pixel_font.woff")
	if "--preview" in sys.argv:
		i = sys.argv.index("--preview")
		preview(pathlib.Path(sys.argv[i + 1]))
	print("art/brand: готово, логотип", logo.w, "x", logo.h)


def preview(path):
	names = ["logo", "tap", "rotate", "treeline", "soil", "cloud_1", "cloud_2"]
	S = 4
	imgs = [Image.open(OUT / (n + ".png")).convert("RGBA") for n in names]
	W = sum(i.width * S + 16 for i in imgs) + 16
	H = max(i.height * S for i in imgs) + 32
	sheet = Image.new("RGBA", (W, H + 540), (70, 110, 150, 255))
	x = 8
	for im in imgs:
		sheet.alpha_composite(im.resize((im.width * S, im.height * S), Image.NEAREST), (x, 8))
		x += im.width * S + 16
	x = 8
	for n in ["icon-512", "icon-maskable-512", "apple-touch-icon", "icon-192", "favicon-32"]:
		im = Image.open(OUT / (n + ".png")).convert("RGBA")
		if im.width > 200:
			im = im.resize((256, 256), Image.NEAREST)
		else:
			im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
		sheet.alpha_composite(im, (x, H + 20))
		x += im.width + 16
	sheet.save(path)


if __name__ == "__main__":
	main()
