#!/usr/bin/env python3
"""gen_monsters.py — спрайты монстров, босса и эффектов боя (art/monsters/).

Рисуем кодом (Pillow + numpy), в том же масштабе, что герой: рисунок в
ART_SCALE=3 раза подробнее игровых координат, на экране он уменьшен втрое.
Фигуры — эллипсы и многоугольники без сглаживания; каждая деталь получает
обводку, световую кромку слева сверху, тень справа снизу и шахматный
дизеринг на границе тени (приём «пиксель-арт высокого класса» из ГДД п.15.1).
Лист кадров на монстра: строка — анимация (idle, move, attack, die, у
засадника ещё dormant), столбец — кадр; рядом <id>.json с размером кадра,
линией земли и числом кадров (читает scripts/combat/monster_sheet.gd).

Это заглушки уровня «программист нарисовал аккуратно», не работа художника
владельца. Руками PNG не правим — меняй рисунок здесь и запускай:

    python3 tools/gen_monsters.py [каталог_для_контактных_листов]

Результат: art/monsters/<id>.png + <id>.json, fx_slash.png.
"""

import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "art", "monsters")

S = 3                       # ART_SCALE: пикселей рисунка на логический пиксель
OL = (0x16, 0x0F, 0x1C)     # общая обводка силуэта


def lighten(c, k):
	return tuple(min(255, int(v + (255 - v) * k)) for v in c)


def darken(c, k):
	return tuple(int(v * (1 - k)) for v in c)


def mix(a, b, t):
	return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _shift(m, dx, dy):
	out = np.zeros_like(m)
	h, w = m.shape
	xs0, xs1 = max(0, dx), min(w, w + dx)
	ys0, ys1 = max(0, dy), min(h, h + dy)
	out[ys0:ys1, xs0:xs1] = m[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
	return out


def _dilate(m, r):
	for _ in range(r):
		m = m | _shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)
	return m


class Canvas:
	"""Холст в логических пикселях (w×h); рисует в S раз подробнее."""

	def __init__(self, w, h, seed=1):
		self.w, self.h = w, h
		self.W, self.H = w * S, h * S
		self.px = np.zeros((self.H, self.W, 4), np.uint8)
		self.rng = random.Random(seed)
		yy, xx = np.mgrid[0:self.H, 0:self.W]
		self._checker = (((xx // S) + (yy // S)) % 2 == 0)

	# --- маски ---
	def mask(self, fn):
		im = Image.new("L", (self.W, self.H), 0)
		fn(_Pen(ImageDraw.Draw(im)))
		return np.array(im) > 127

	def _set(self, m, col, alpha=255):
		if alpha >= 255:
			self.px[m] = (col[0], col[1], col[2], 255)
		else:
			a = alpha / 255.0
			dst = self.px[m].astype(np.float32)
			da = dst[:, 3] / 255.0
			oa = a + da * (1 - a)
			for i in range(3):
				dst[:, i] = (col[i] * a + dst[:, i] * da * (1 - a)) / np.maximum(oa, 1e-6)
			dst[:, 3] = oa * 255
			self.px[m] = dst.astype(np.uint8)

	# --- детали ---
	def part(self, fn, base, shade=True, outline=None, rim=1.0, tex=0.0, dither=True, hatch=None):
		m = self.mask(fn)
		if not m.any():
			return m
		oc = outline if outline is not None else darken(base, 0.62)
		ring = _dilate(m, S) & ~m
		self._set(ring, oc)
		self._set(m, base)
		if shade:
			k = max(1, int(S * 1.3 * rim))
			lit = m & ~_shift(m, k, k)
			dk = m & ~_shift(m, -2 * k, -2 * k)
			band = m & ~_shift(m, -4 * k, -4 * k) & ~dk
			if dither:
				self._set(band & self._checker, mix(base, OL, 0.28))
			self._set(dk, mix(base, OL, 0.38))
			self._set(lit & ~dk, lighten(base, 0.38))
		if tex > 0:
			ys, xs = np.nonzero(m[::S, ::S])
			for y, x in zip(ys, xs):
				r = self.rng.random()
				if r < tex:
					cell = np.zeros_like(m)
					cell[y * S:(y + 1) * S, x * S:(x + 1) * S] = True
					cell &= m
					self._set(cell, darken(base, 0.18) if self.rng.random() < 0.6 else lighten(base, 0.12))
		return m

	def flat(self, fn, col, alpha=255):
		m = self.mask(fn)
		self._set(m, col, alpha)
		return m

	def glow(self, fn, col, halo=2, core=None):
		"""Светящаяся деталь: ступенчатое гало вокруг яркой сердцевины."""
		m = self.mask(fn)
		for i in range(halo, 0, -1):
			ring = _dilate(m, S * i)
			self._set(ring & ~m, col, int(60 / i))
		self._set(m, col)
		if core is not None:
			inner = m & ~_dilate(~m, 1) if False else m
			sh = m & _shift(m, S, S) & _shift(m, -S, -S)
			self._set(sh, core)
		return m

	def outline_all(self, thick=1.0):
		a = self.px[:, :, 3] > 0
		ring = _dilate(a, int(S * thick)) & ~a
		self.px[ring] = (OL[0], OL[1], OL[2], 255)

	def eye(self, cx, cy, r, look=(1.0, 0.0), lid=0.0, iris=None, glow_col=None, x_eye=False, lid_col=None):
		"""Большой милый глаз: белок, зрачок, блик."""
		if glow_col is not None:
			self.glow(lambda d: d.ellipse_l(cx, cy, r, r), glow_col, 1)
		self.part(lambda d: d.ellipse_l(cx, cy, r, r), (0xF4, 0xF0, 0xE8) if iris is None else iris, shade=False,
			outline=OL)
		if x_eye:
			for sgn in (1, -1):
				self.flat(lambda d: d.line_l([(cx - r * 0.6, cy - r * 0.6 * sgn), (cx + r * 0.6, cy + r * 0.6 * sgn)], r * 0.35), OL)
			return
		pr = r * 0.62
		px_, py_ = cx + look[0] * r * 0.32, cy + look[1] * r * 0.32
		self.flat(lambda d: d.ellipse_l(px_, py_, pr, pr), (0x1A, 0x10, 0x20))
		self.flat(lambda d: d.ellipse_l(px_ - pr * 0.35, py_ - pr * 0.4, pr * 0.32, pr * 0.32), (0xFF, 0xFF, 0xFF))
		if lid > 0:
			lc = lid_col or (0x30, 0x28, 0x38)
			self.flat(lambda d: d.rect_l(cx - r - 0.3, cy - r - 0.3, cx + r + 0.3, cy - r + 2 * r * lid), lc)
			self.flat(lambda d: d.line_l([(cx - r, cy - r + 2 * r * lid), (cx + r, cy - r + 2 * r * lid)], 0.7), OL)

	def image(self):
		return Image.fromarray(self.px, "RGBA")


class _Pen:
	"""Рисует в логических координатах поверх ImageDraw."""

	def __init__(self, d):
		self.d = d

	def ellipse_l(self, cx, cy, rx, ry):
		self.d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S - 1, (cy + ry) * S - 1], fill=255)

	def rect_l(self, x0, y0, x1, y1):
		self.d.rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=255)

	def poly_l(self, pts):
		self.d.polygon([(x * S, y * S) for x, y in pts], fill=255)

	def line_l(self, pts, width):
		self.d.line([(x * S, y * S) for x, y in pts], fill=255, width=max(1, int(width * S)), joint="curve")
		# круглые концы
		w = max(1, int(width * S)) / 2.0
		for x, y in (pts[0], pts[-1]):
			self.d.ellipse([x * S - w, y * S - w, x * S + w, y * S + w], fill=255)

	def rrect_l(self, x0, y0, x1, y1, r):
		self.d.rounded_rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], radius=r * S, fill=255)


def rot(img, deg, center=None):
	"""Поворот без сглаживания (NEAREST), чтобы пиксели оставались пикселями."""
	return img.rotate(deg, resample=Image.NEAREST, center=center)


# ---------------------------------------------------------------------------
# Описания монстров
# ---------------------------------------------------------------------------

MONSTERS = {}


def monster(mid, frame, foot, anchor="feet"):
	def deco(fn):
		MONSTERS[mid] = {"fn": fn, "frame": frame, "foot": foot, "anchor": anchor}
		return fn
	return deco


def sine(i, n, amp=1.0, phase=0.0):
	return math.sin((i / n + phase) * math.tau) * amp


# --- 1. Угольный червь ------------------------------------------------------

@monster("cinder_grub", (44, 30), 2)
def grub(c, anim, i, n):
	ground = 28.0
	body = (0x55, 0x4C, 0x5C)
	ember = (0xFF, 0x8A, 0x2A)
	hx = 33.5
	segs = [(hx, 8.0), (hx - 7.5, 7.4), (hx - 14.5, 6.4), (hx - 20.5, 5.0), (hx - 25.5, 3.4)]
	lift = 0.0     # подъём головы (замах)
	open_mouth = 0.0
	squash = 1.0
	alpha_embers = 1.0
	if anim == "idle":
		pass
	if anim == "attack":
		p = i / (n - 1)
		lift = 7.5 * min(1.0, p * 1.6) if p < 0.75 else 2.0
		open_mouth = min(1.0, p * 1.5)
		if p >= 0.75:
			hx += 4
	pos = []
	for k, (sx, r) in enumerate(segs):
		wave = 0.0
		if anim == "move":
			wave = math.sin((i / n) * math.tau * 1.0 - k * 0.9) * 2.4
			wave += math.sin((i / n) * math.tau * 2.0 - k * 1.1) * 0.6
		if anim == "idle":
			wave = math.sin((i / n) * math.tau - k * 0.7) * 0.7
		if anim == "die":
			p = i / (n - 1)
			r = r * (1.0 - 0.28 * p)
			wave = 0.0
		cy = ground - r + wave
		if k == 0 and anim == "attack":
			cy -= lift
		if anim == "attack" and k == 1:
			cy -= lift * 0.45
		if anim == "attack" and k == 2:
			cy -= lift * 0.12
		pos.append((sx + (hx - segs[0][0] if k == 0 else 0), cy, r))
	if anim == "die":
		p = i / (n - 1)
		for k in range(len(pos)):
			x, y, r = pos[k]
			pos[k] = (x - p * (k * 0.5), ground - r * (0.75 - 0.2 * p), r)
	order = list(range(len(pos) - 1, -1, -1))
	dying = anim == "die"
	for k in order:
		x, y, r = pos[k]
		col = mix(body, (0x30, 0x2A, 0x36), 0.15 * k / 4.0)
		if dying:
			col = mix(col, (0x2A, 0x26, 0x30), (i / (n - 1)) * 0.8)
		sq = 0.78 if dying else 1.0
		c.part(lambda d, x=x, y=y, r=r, sq=sq: d.ellipse_l(x, y, r, r * sq), col, tex=0.05)
		# тлеющие трещины на спине
		if not dying or i < n - 2:
			a = 1.0 if not dying else 1.0 - i / n
			gx = x - r * 0.15
			c.flat(lambda d, gx=gx, y=y, r=r: d.line_l([(gx - r * 0.5, y - r * 0.55), (gx, y - r * 0.2), (gx + r * 0.45, y - r * 0.6)], 0.9),
				mix(col, ember, 0.9 * a))
	hxp, hyp, hr = pos[0]
	# жвала
	mo = open_mouth
	c.part(lambda d: d.poly_l([(hxp + hr * 0.55, hyp + hr * (0.15 + 0.2 * mo)), (hxp + hr * 1.35, hyp + hr * (0.55 + 0.7 * mo)),
		(hxp + hr * 0.9, hyp + hr * 0.1)]), (0xE6, 0xD6, 0xB0), shade=False, outline=OL)
	c.part(lambda d: d.poly_l([(hxp + hr * 0.55, hyp - hr * 0.05), (hxp + hr * 1.35, hyp - hr * (0.35 + 0.5 * mo)),
		(hxp + hr * 0.95, hyp - hr * 0.4)]), (0xE6, 0xD6, 0xB0), shade=False, outline=OL)
	if mo > 0.1:
		c.glow(lambda d: d.ellipse_l(hxp + hr * 0.8, hyp + hr * 0.2, hr * 0.28 * mo, hr * 0.4 * mo), ember, 1)
	# глаза: огромные и добрые
	if dying:
		c.eye(hxp + hr * 0.15, hyp - hr * 0.3, 3.0, x_eye=True)
	else:
		ec = hyp - hr * 0.32
		c.eye(hxp - hr * 0.1, ec, 3.3, look=(1, 0.1), lid=0.0 if anim != "attack" else 0.35)
		c.eye(hxp + hr * 0.62, ec + 0.6, 2.7, look=(1, 0.1), lid=0.0 if anim != "attack" else 0.35)


# --- 2. Мотылёк Тени ----------------------------------------------------------

@monster("gloom_moth", (48, 44), 0, anchor="center")
def moth(c, anim, i, n):
	cx, cy = 24.0, 24.0
	body = (0x3A, 0x2C, 0x58)
	wing = (0x62, 0x4A, 0x9A)
	wing2 = (0x45, 0x34, 0x74)
	spot = (0xD8, 0xB8, 0xFF)
	ph = i / n
	flap = math.cos(ph * math.tau)                       # -1 вниз .. 1 вверх
	if anim == "move":
		flap = math.cos(ph * math.tau)
	if anim == "idle":
		flap = math.cos(ph * math.tau) * 0.55
	tilt = 0.0
	eyes_red = False
	if anim == "attack":
		p = i / (n - 1)
		flap = 1.0 - p * 0.2 if p < 0.5 else -0.9
		eyes_red = True
		tilt = p * 22
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		flap = -0.2 - 0.8 * p
		cy += 6 * p
	wy = -flap * 9.0   # кончик крыла выше/ниже тела

	def wings(side):
		# верхнее крыло
		top = [(cx + side * 3, cy - 1), (cx + side * 12, cy - 3 + wy * 0.6), (cx + side * 21, cy - 10 + wy),
			(cx + side * 22.5, cy - 4 + wy * 0.9), (cx + side * 14, cy + 3 + wy * 0.2)]
		low = [(cx + side * 3, cy + 1), (cx + side * 12, cy + 5 + wy * 0.25), (cx + side * 17.5, cy + 12 + wy * 0.45),
			(cx + side * 10, cy + 12 + wy * 0.2), (cx + side * 4, cy + 7)]
		return top, low
	for side in (-1, 1):
		top, low = wings(side)
		c.part(lambda d, low=low: d.poly_l(low), wing2, outline=darken(wing2, 0.6))
		c.part(lambda d, top=top: d.poly_l(top), wing, outline=darken(wing, 0.6))
		# глазки на крыльях
		tx = (top[2][0] + top[0][0]) / 2.0 + side * 1.0
		ty = (top[2][1] + top[0][1]) / 2.0 + 2.0
		c.flat(lambda d, tx=tx, ty=ty: d.ellipse_l(tx, ty, 2.4, 2.4), (0x2A, 0x1E, 0x44))
		c.flat(lambda d, tx=tx, ty=ty: d.ellipse_l(tx, ty, 1.4, 1.4), spot if not eyes_red else (0xFF, 0x70, 0x60))
	# тело: пушистый овал
	c.part(lambda d: d.ellipse_l(cx, cy + 3, 4.6, 8.2), body, tex=0.1)
	# голова
	hy = cy - 6.0
	c.part(lambda d: d.ellipse_l(cx, hy, 5.2, 4.8), mix(body, wing, 0.3), tex=0.08)
	# усики
	for side in (-1, 1):
		c.flat(lambda d, side=side: d.line_l([(cx + side * 2.0, hy - 3.5), (cx + side * 5.5, hy - 10 + (1 if not dying else 4)),
			(cx + side * 8, hy - 11 + (1 if not dying else 5))], 0.9), (0xC8, 0xB0, 0xF0))
		c.flat(lambda d, side=side: d.ellipse_l(cx + side * 8.2, hy - 11 + (1 if not dying else 5), 1.1, 1.1), (0xF0, 0xE0, 0xFF))
	# глаза-фонари
	ecol = (0xFF, 0xE8, 0x70) if not eyes_red else (0xFF, 0x58, 0x48)
	if dying:
		c.eye(cx - 2.3, hy + 0.2, 2.3, x_eye=True)
		c.eye(cx + 2.3, hy + 0.2, 2.3, x_eye=True)
	else:
		for side in (-1, 1):
			c.glow(lambda d, side=side: d.ellipse_l(cx + side * 2.4, hy + 0.3, 2.6, 2.6), ecol, 1)
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 2.4, hy + 0.3, 1.1, 1.8), (0x2A, 0x14, 0x30))
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 2.4 - 0.5, hy - 0.4, 0.5, 0.5), (1, 1, 1))
	# мордочка
	c.flat(lambda d: d.line_l([(cx - 1.2, hy + 3.2), (cx, hy + 3.9), (cx + 1.2, hy + 3.2)], 0.5), OL)


# --- 3. Щёлк-прыгунец -----------------------------------------------------------

@monster("rift_hopper", (44, 44), 1)
def hopper(c, anim, i, n):
	ground = 42.0
	body = (0x2C, 0x6E, 0x78)
	belly = (0x9A, 0xD8, 0xC8)
	dot = (0xE8, 0xFF, 0xF0)
	ph = i / n
	sq = 1.0      # приседание
	air = 0.0
	if anim == "idle":
		sq = 1.0 + math.sin(ph * math.tau) * 0.04
	if anim == "move":
		sq = 1.0 - 0.12 * (0.5 - 0.5 * math.cos(ph * math.tau * 2))
		air = max(0.0, math.sin(ph * math.tau)) * 3.0
	if anim == "attack":
		p = i / (n - 1)
		sq = 1.0 - 0.34 * min(1.0, p * 1.4)
		if p > 0.85:
			sq = 1.22
			air = 2.0
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		sq = 0.7 - 0.1 * p
	cx = 21.0
	bh = 10.5 * sq         # половина высоты тела
	by = ground - air - bh - 3.5 * sq
	flip = dying and i >= 2
	eye_y = by - bh * 0.95
	# задняя нога: бедро и голень, согнуты
	hind = (0x1F, 0x52, 0x5C)
	kx, ky = cx - 12.0, by + bh * 0.6
	c.part(lambda d: d.line_l([(kx + 3, ky - 2 * sq), (kx - 6, ground - air - 3.5), (kx + 4, ground - air - 0.5)], 3.2 * (0.8 + 0.2 * sq)), hind)
	c.part(lambda d: d.ellipse_l(kx + 3, ky - 2.5 * sq, 6.2, 6.8 * sq), body)
	c.part(lambda d: d.ellipse_l(kx + 6.0, ground - air - 0.4, 5.2, 1.7), hind, shade=False)
	# корпус
	c.part(lambda d: d.ellipse_l(cx, by, 15.0, bh), body, tex=0.04)
	c.part(lambda d: d.ellipse_l(cx + 3.0, by + bh * 0.35, 9.5, bh * 0.6), belly, shade=False, outline=darken(belly, 0.5))
	# пятна
	for (dx, dy, r) in ((-4, -0.55, 1.5), (0, -0.8, 1.2), (4.5, -0.5, 1.4), (-8, -0.1, 1.1)):
		c.flat(lambda d, dx=dx, dy=dy, r=r: d.ellipse_l(cx + dx, by + bh * dy, r, r), dot)
	# передняя лапа
	c.part(lambda d: d.line_l([(cx + 9, by + bh * 0.4), (cx + 12, ground - air - 1.5)], 2.6), hind)
	# голова-выступ и пасть
	hx = cx + 10.0
	c.part(lambda d: d.ellipse_l(hx + 2, by - bh * 0.2, 7.0, 6.0 * (0.6 + 0.4 * sq)), body)
	mouth_open = 0.0 if anim != "attack" else min(1.0, (i / (n - 1)) * 1.5)
	c.flat(lambda d: d.line_l([(hx - 1, by + 1.2), (hx + 5, by + 1.8 + mouth_open * 1.5), (hx + 8.2, by + 0.6)], 0.8), OL)
	if mouth_open > 0.5:
		c.flat(lambda d: d.poly_l([(hx + 1, by + 1.2), (hx + 7, by + 1.6), (hx + 5, by + 4.5)]), (0xD0, 0x40, 0x48))
	# глаза-бусины сверху
	if dying:
		c.eye(hx - 3.0, eye_y + 1.5, 3.4, x_eye=True)
		c.eye(hx + 3.8, eye_y + 1.5, 3.0, x_eye=True)
	else:
		lid = 0.0 if anim != "attack" else 0.42
		c.eye(hx - 3.0, eye_y + 1.5, 3.4, look=(1, 0.0), lid=lid, lid_col=body)
		c.eye(hx + 3.8, eye_y + 1.5, 3.0, look=(1, 0.0), lid=lid, lid_col=body)
	if anim == "attack" and i > 0:
		c.flat(lambda d: d.line_l([(hx - 5.5, eye_y - 3), (hx + 0.5, eye_y - 1.6)], 0.9), (0xFF, 0x60, 0x50))


# --- 4. Камнеед-засадник ----------------------------------------------------------

@monster("rock_mimic", (48, 40), 1)
def mimic(c, anim, i, n):
	ground = 38.5
	rock = (0x6A, 0x68, 0x78)
	rock_d = (0x4A, 0x48, 0x58)
	maw = (0xFF, 0x7A, 0x28)
	tooth = (0xF0, 0xE8, 0xD0)
	ph = i / n
	if anim == "dormant":
		# только блеск глаз во тьме породы
		blink = 0.0 if i == 0 else 0.55
		for dx in (-4.2, 4.2):
			c.glow(lambda d, dx=dx: d.ellipse_l(24 + dx, 31, 2.0, 1.4 * (1 - blink)), (0xFF, 0xB8, 0x40), 1)
		return
	bob = 0.0
	jaw = 0.0
	leg = 0.0
	if anim == "idle":
		bob = math.sin(ph * math.tau) * 0.5
		jaw = 0.08
	if anim == "move":
		bob = -abs(math.sin(ph * math.tau)) * 1.6
		leg = math.sin(ph * math.tau * 1.0)
		jaw = 0.12
	if anim == "attack":
		p = i / (n - 1)
		jaw = min(1.0, p * 1.5) if p < 0.8 else 0.25
		bob = -2.0 * min(1.0, p * 2.0) if p < 0.8 else 1.0
	dying = anim == "die"
	cx = 24.0
	# ножки-култышки
	for k, dx in enumerate((-12, -5, 5, 12)):
		l = leg * (1 if k % 2 == 0 else -1)
		c.part(lambda d, dx=dx, l=l: d.rrect_l(cx + dx - 2.2 + l * 1.6, ground - 6 + bob, cx + dx + 2.2 + l * 1.6, ground, 1.5), rock_d)
	if dying:
		p = i / (n - 1)
		# рассыпается на глыбы
		rng = random.Random(7)
		for k in range(9):
			a = rng.random() * math.tau
			dist = (4 + rng.random() * 9) * p
			fx = cx + math.cos(a) * dist * 1.4 + (rng.random() - 0.5) * 8
			fy = ground - 7 - abs(math.sin(a)) * dist * 0.5 + 6 * p * p
			sz = 3.8 - 1.4 * p + rng.random() * 1.5
			c.part(lambda d, fx=fx, fy=fy, sz=sz: d.poly_l([(fx - sz, fy + sz * 0.6), (fx - sz * 0.3, fy - sz), (fx + sz, fy - sz * 0.2),
				(fx + sz * 0.7, fy + sz)]), mix(rock, rock_d, rng.random() * 0.6), tex=0.06)
		if p < 0.55:
			c.glow(lambda d: d.ellipse_l(cx, ground - 8, 3 * (1 - p), 2 * (1 - p)), maw, 1)
		return
	top = 8.0 + bob
	# нижняя челюсть/низ валуна
	jy = jaw * 8.0
	c.part(lambda d: d.poly_l([(cx - 18, ground - 6 + bob), (cx - 15, ground - 14 + bob + jy * 0.4), (cx + 15, ground - 14 + bob + jy * 0.4),
		(cx + 18, ground - 6 + bob), (cx + 14, ground - 1 + bob + jy * 0.5), (cx - 14, ground - 1 + bob + jy * 0.5)]), rock_d, tex=0.06)
	# пасть внутри
	if jaw > 0.1:
		c.flat(lambda d: d.poly_l([(cx - 15, ground - 14 + bob + jy * 0.3), (cx + 15, ground - 14 + bob + jy * 0.3),
			(cx + 12, ground - 9 + bob + jy * 0.3), (cx - 12, ground - 9 + bob + jy * 0.3)]), mix(maw, (0x30, 0x10, 0x10), 0.35))
		c.glow(lambda d: d.ellipse_l(cx, ground - 10 + bob + jy * 0.3, 7, 1.5 + 1.8 * jaw), maw, 1)
		# нижние зубы
		for k in range(5):
			tx = cx - 11 + k * 5.5
			c.flat(lambda d, tx=tx: d.poly_l([(tx - 1.5, ground - 9.5 + bob + jy * 0.3), (tx, ground - 12.8 + bob + jy * 0.3 - jaw),
				(tx + 1.5, ground - 9.5 + bob + jy * 0.3)]), tooth)
	# верх: глыба
	lift = jy * 0.4
	c.part(lambda d: d.poly_l([(cx - 19, ground - 14 + bob - lift + jy * 0.35), (cx - 17, top + 5 - lift), (cx - 8, top - lift), (cx + 6, top - 1.5 - lift),
		(cx + 16, top + 3 - lift), (cx + 19, ground - 14 + bob - lift + jy * 0.35), (cx + 12, ground - 11 + bob - lift + jy * 0.35),
		(cx - 12, ground - 11 + bob - lift + jy * 0.35)]), rock, tex=0.07)
	# трещины и кристаллики
	c.flat(lambda d: d.line_l([(cx - 6, top + 2 - lift), (cx - 3, top + 6 - lift), (cx - 5, top + 9 - lift)], 0.7), rock_d)
	c.flat(lambda d: d.line_l([(cx + 8, top + 3 - lift), (cx + 6, top + 7 - lift)], 0.7), rock_d)
	c.part(lambda d: d.poly_l([(cx + 8, top + 1.5 - lift), (cx + 10, top - 4 - lift), (cx + 12, top + 2 - lift)]), (0xFF, 0xA0, 0x48), shade=False, outline=OL)
	# верхние зубы
	if jaw > 0.1:
		for k in range(5):
			tx = cx - 11 + k * 5.5
			c.flat(lambda d, tx=tx: d.poly_l([(tx - 1.6, ground - 11.5 + bob - lift + jy * 0.35), (tx, ground - 7.5 + bob - lift + jy * 0.35 + jaw * 1.5),
				(tx + 1.6, ground - 11.5 + bob - lift + jy * 0.35)]), tooth)
	# глаза: сонные, пока не атакует
	ey = top + 11 - lift
	lid = 0.55 if anim in ("idle", "move") else 0.12
	c.eye(cx - 6.2, ey, 3.5, look=(1, 0.2), lid=lid, lid_col=rock_d, glow_col=(0xFF, 0xB0, 0x40) if anim == "attack" else None)
	c.eye(cx + 4.8, ey + 0.4, 3.0, look=(1, 0.2), lid=lid, lid_col=rock_d, glow_col=(0xFF, 0xB0, 0x40) if anim == "attack" else None)


# --- 5. Искорка -----------------------------------------------------------------------

@monster("spark_swarm", (20, 20), 0, anchor="center")
def spark(c, anim, i, n):
	cx, cy = 10.0, 11.5
	ph = i / n
	core = (0xFF, 0xA0, 0x30)
	hot = (0xFF, 0xE0, 0x70)
	r = 5.2 + math.sin(ph * math.tau) * 0.4
	flick = math.sin(ph * math.tau * 2)
	dying = anim == "die"
	if anim == "attack":
		r += 1.0
		core = (0xFF, 0xD0, 0x60)
		hot = (0xFF, 0xFF, 0xFF)
	if dying:
		p = i / (n - 1)
		ring = 3 + 7 * p
		for k in range(8):
			a = k / 8 * math.tau + 0.4
			c.glow(lambda d, a=a, ring=ring, p=p: d.ellipse_l(cx + math.cos(a) * ring, cy + math.sin(a) * ring, 1.6 * (1 - p) + 0.4, 1.6 * (1 - p) + 0.4),
				hot if k % 2 else core, 1)
		return
	# язычок пламени сверху
	c.glow(lambda d: d.poly_l([(cx - 2.8, cy - r * 0.6), (cx + flick * 1.2, cy - r - 4.2 + flick * 0.6), (cx + 2.8, cy - r * 0.6)]), core, 1)
	c.glow(lambda d: d.ellipse_l(cx, cy, r, r), core, 2)
	c.flat(lambda d: d.ellipse_l(cx, cy + 0.8, r * 0.72, r * 0.62), hot)
	c.eye(cx - 2.2, cy - 0.4, 2.0, look=(0.6, 0.2))
	c.eye(cx + 2.2, cy - 0.4, 2.0, look=(0.6, 0.2))


# --- 6. Страж Бездны ----------------------------------------------------------------------

@monster("abyss_warden", (72, 64), 1)
def warden(c, anim, i, n):
	ground = 62.0
	arm_ang = 0.0
	bob = 0.0
	step = 0.0
	armor = (0xC8, 0xA8, 0x58)
	armor_d = (0x8A, 0x6C, 0x30)
	dark = (0x2A, 0x26, 0x3A)
	glowc = (0xFF, 0x60, 0x50)
	ph = i / n
	slam = 0.0
	if anim == "idle":
		bob = math.sin(ph * math.tau) * 0.7
	if anim == "move":
		bob = -abs(math.sin(ph * math.tau)) * 1.2
		step = math.sin(ph * math.tau)
	if anim == "attack":
		p = i / (n - 1)
		if p < 0.7:
			arm_ang = -p / 0.7 * 1.0     # поднимает кулак над головой
		else:
			arm_ang = 0.9
			slam = 1.0
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		bob = 12 * p
	cx = 33.0
	# ноги
	for k, dx in enumerate((-9, 8)):
		s = step * (1 if k == 0 else -1)
		c.part(lambda d, dx=dx, s=s: d.rrect_l(cx + dx - 5 + s * 2, ground - 16 + bob * 0.3, cx + dx + 5 + s * 2, ground, 2.5), dark)
		c.part(lambda d, dx=dx, s=s: d.rrect_l(cx + dx - 6 + s * 2, ground - 5, cx + dx + 7 + s * 2, ground + 0.5, 2.0), armor_d)
	if dying:
		p = i / (n - 1)
		c.part(lambda d: d.rrect_l(cx - 14, ground - 30 + bob, cx + 14, ground - 12 + bob * 0.6, 4), dark)
		c.part(lambda d: d.poly_l([(cx - 14, ground - 32 + bob), (cx + 14, ground - 32 + bob), (cx + 11, ground - 15 + bob * 0.6), (cx - 11, ground - 15 + bob * 0.6)]), armor, tex=0.06)
		c.eye(cx + 4, ground - 24 + bob, 3.0, x_eye=True)
		for k in range(6):
			rng = random.Random(k + 3)
			fx = cx + (rng.random() - 0.5) * 36 * p
			fy = ground - 3 - rng.random() * 6
			c.part(lambda d, fx=fx, fy=fy: d.poly_l([(fx - 2.5, fy + 2), (fx, fy - 2.5), (fx + 3, fy + 1)]), armor_d, shade=False)
		return
	# задняя рука (левая от зрителя)
	c.part(lambda d: d.rrect_l(cx - 20, ground - 38 + bob, cx - 11, ground - 18 + bob, 3.5), dark)
	c.part(lambda d: d.ellipse_l(cx - 16, ground - 17 + bob, 6.0, 5.5), armor_d)
	# корпус
	c.part(lambda d: d.rrect_l(cx - 15, ground - 40 + bob, cx + 15, ground - 14 + bob, 5), dark)
	c.part(lambda d: d.poly_l([(cx - 17, ground - 41 + bob), (cx + 17, ground - 41 + bob), (cx + 13, ground - 22 + bob), (cx, ground - 16 + bob), (cx - 13, ground - 22 + bob)]), armor, tex=0.06)
	# щель-сердце на груди
	c.glow(lambda d: d.rect_l(cx - 1.4, ground - 36 + bob, cx + 1.4, ground - 24 + bob), glowc, 1)
	c.flat(lambda d: d.line_l([(cx - 11, ground - 33 + bob), (cx - 4, ground - 30 + bob)], 0.9), armor_d)
	c.flat(lambda d: d.line_l([(cx + 11, ground - 33 + bob), (cx + 4, ground - 30 + bob)], 0.9), armor_d)
	# наплечники
	c.part(lambda d: d.ellipse_l(cx - 17, ground - 40 + bob, 7.5, 6.0), armor_d)
	c.part(lambda d: d.ellipse_l(cx + 17, ground - 40 + bob, 7.5, 6.0), armor)
	# голова-шлем с рогами
	hy = ground - 46 + bob
	c.part(lambda d: d.poly_l([(cx - 11, hy - 2), (cx - 16, hy - 9), (cx - 12, hy - 11), (cx - 7, hy - 4)]), armor_d, shade=False)
	c.part(lambda d: d.poly_l([(cx + 11, hy - 2), (cx + 16, hy - 9), (cx + 12, hy - 11), (cx + 7, hy - 4)]), armor, shade=False)
	c.part(lambda d: d.rrect_l(cx - 10, hy - 6, cx + 10, hy + 8, 4.5), armor, tex=0.05)
	c.flat(lambda d: d.rect_l(cx - 8, hy, cx + 8, hy + 3.4), dark)
	eyecol = glowc if anim == "attack" else (0xFF, 0xC8, 0x60)
	for side in (-1, 1):
		c.glow(lambda d, side=side: d.ellipse_l(cx + side * 3.8, hy + 1.7, 1.9, 1.5), eyecol, 1)
	# передняя рука с кулаком-молотом
	sh = (cx + 15.5, ground - 38 + bob)
	ang = arm_ang
	ux, uy = math.sin(ang * 1.9 + 0.35), math.cos(ang * 1.9 + 0.35)
	if anim == "attack":
		# рука идёт вверх (ang<0) и бьёт вниз вперёд
		if slam:
			fx, fy = sh[0] + 13, ground - 3
		else:
			fx, fy = sh[0] + 6 - arm_ang * 6, sh[1] + 20 + arm_ang * 30
	else:
		fx, fy = sh[0] + 7, sh[1] + 20
	c.part(lambda d: d.line_l([sh, ((sh[0] + fx) / 2 + 3, (sh[1] + fy) / 2), (fx, fy)], 7.5), dark)
	c.part(lambda d: d.ellipse_l(fx, fy, 8.0, 7.0), armor, tex=0.05)
	c.flat(lambda d: d.line_l([(fx - 4, fy - 1), (fx + 4, fy - 1)], 0.8), armor_d)
	if slam:
		for k in range(5):
			c.flat(lambda d, k=k: d.ellipse_l(fx + 3 + k * 4.0, ground - 1.5 - (k % 2) * 2.0, 2.0, 1.4), (0xC8, 0xC0, 0xB0), 200)


# --- Босс: Идол Бездны ------------------------------------------------------------------------

@monster("abyss_idol", (128, 120), 2)
def idol(c, anim, i, n):
	ground = 118.0
	cx = 64.0
	stone = (0x6E, 0x66, 0x7C)
	stone_d = (0x4C, 0x46, 0x5C)
	stone_l = (0x8C, 0x84, 0x9C)
	glyph = (0xB8, 0x78, 0xFF)
	heart = (0xFF, 0x5A, 0xA8)
	ph = i / n
	bob = math.sin(ph * math.tau) * 1.0 if anim in ("idle", "exposed", "roar") else 0.0
	shutter = 0.0          # 0 — закрыта, 1 — сердце открыто
	fist_r = (0.0, 0.0)    # смещение правого кулака
	fist_l = (0.0, 0.0)
	eye_glow = 0.5
	crack = 0.4
	dust = False
	rise = 0.0
	if anim == "exposed":
		shutter = 1.0
		crack = 0.9
		eye_glow = 0.35
		bob = math.sin(ph * math.tau) * 0.8
	if anim == "roar":
		bob = -2.5 + math.sin(ph * math.tau * 2) * 1.5
		fist_l = (-2, -9)
		fist_r = (2, -9)
		eye_glow = 1.0
		crack = 1.0
	if anim == "attack":
		p = i / (n - 1)
		# 0..0.66 — замах (кулак поднимается), 0.7+ — удар
		if p <= 0.68:
			k = p / 0.68
			k = k ** 0.55
			fist_r = (-4 * k, -46 * k)
			eye_glow = 0.5 + 0.5 * k
			crack = 0.4 + 0.6 * k
		else:
			fist_r = (-6, 4)
			dust = True
			eye_glow = 1.0
			crack = 1.0
			bob = 2.0
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		bob = 14 * p
		crack = 1.0 - 0.7 * p
		eye_glow = 1.0 - p
		shutter = 1.0 - p * 0.3
	by = bob
	# тень на полу
	c.flat(lambda d: d.ellipse_l(cx, ground + 0.5, 46, 4.5), (0, 0, 0), 90)
	# кулаки (за корпусом левый, перед — правый)
	def fist(x, y, big=1.0, front=False):
		fx, fy = x, y
		c.part(lambda d: d.line_l([(fx > cx and fx - 20 or fx + 20, 70 + by + (fy - 94) * 0.15), (fx, fy)], 12), stone_d, shade=False)
		c.part(lambda d: d.ellipse_l(fx, fy, 15 * big, 14 * big), stone, tex=0.07)
		c.flat(lambda d: d.line_l([(fx - 8, fy - 2), (fx + 8, fy - 2)], 1.2), stone_d)
		c.flat(lambda d: d.line_l([(fx - 6, fy + 5), (fx + 6, fy + 5)], 1.2), stone_d)
		for kx in (-1, 0, 1):
			c.flat(lambda d, kx=kx: d.line_l([(fx + kx * 6, fy - 11), (fx + kx * 6, fy - 4)], 1.1), stone_d)
	lx, ly = 22 + fist_l[0], 100 + by + fist_l[1]
	if dying:
		lx, ly = 20, 108 + by * 0.4
	fist(lx, ly)
	# корпус: массивная трапеция
	c.part(lambda d: d.poly_l([(cx - 34, ground - 4 + by * 0.3), (cx - 38, 74 + by), (cx - 28, 44 + by), (cx + 28, 44 + by), (cx + 38, 74 + by),
		(cx + 34, ground - 4 + by * 0.3)]), stone, tex=0.08)
	c.part(lambda d: d.rrect_l(cx - 24, ground - 12 + by * 0.3, cx - 6, ground, 3), stone_d, shade=False)
	c.part(lambda d: d.rrect_l(cx + 6, ground - 12 + by * 0.3, cx + 24, ground, 3), stone_d, shade=False)
	# вырезанные письмена
	gl = mix(stone_d, glyph, crack)
	for k, (x0, y0, x1, y1) in enumerate(((-30, 60, -22, 70), (-24, 80, -14, 88), (22, 62, 30, 72), (16, 82, 26, 90), (-33, 92, -24, 98), (24, 94, 33, 100))):
		c.flat(lambda d, x0=x0, y0=y0, x1=x1, y1=y1: d.line_l([(cx + x0, y0 + by), (cx + x1, y0 + by), (cx + x1, y1 + by)], 1.1), gl)
	# сердце-ядро в груди за створками
	core_y = 74 + by
	c.part(lambda d: d.ellipse_l(cx, core_y, 15, 17), stone_d, shade=False, outline=OL)
	if shutter > 0.05 or not dying:
		hc = mix((0x40, 0x14, 0x30), heart, max(shutter, crack * 0.35))
		c.glow(lambda d: d.ellipse_l(cx, core_y, 9 + 3 * shutter, 11 + 3 * shutter), hc, 2 if shutter > 0.5 else 1)
		if shutter > 0.5:
			c.flat(lambda d: d.ellipse_l(cx - 2.5, core_y - 3, 3.5, 4.5), (0xFF, 0xD8, 0xEC))
	# створки: две каменные плиты расходятся
	slide = shutter * 12.0
	c.part(lambda d: d.poly_l([(cx - 15 - slide, core_y - 17), (cx - 0.8 - slide, core_y - 17), (cx - 0.8 - slide, core_y + 17), (cx - 15 - slide, core_y + 12)]), stone_l, tex=0.07)
	c.part(lambda d: d.poly_l([(cx + 0.8 + slide, core_y - 17), (cx + 15 + slide, core_y - 17), (cx + 15 + slide, core_y + 12), (cx + 0.8 + slide, core_y + 17)]), stone, tex=0.07)
	# плечи
	c.part(lambda d: d.ellipse_l(cx - 35, 60 + by, 12, 13), stone, tex=0.08)
	c.part(lambda d: d.ellipse_l(cx + 35, 60 + by, 12, 13), stone, tex=0.08)
	# голова: каменная глыба с большими добрыми глазами
	hy = 32 + by
	c.part(lambda d: d.rrect_l(cx - 24, hy - 17, cx + 24, hy + 19, 8), stone, tex=0.08)
	c.part(lambda d: d.poly_l([(cx - 24, hy - 14), (cx - 30, hy - 26), (cx - 18, hy - 19)]), stone_l, shade=False)
	c.part(lambda d: d.poly_l([(cx + 24, hy - 14), (cx + 30, hy - 26), (cx + 18, hy - 19)]), stone_l, shade=False)
	c.part(lambda d: d.rect_l(cx - 18, hy - 22, cx + 18, hy - 15), stone_d, shade=False)
	c.flat(lambda d: d.line_l([(cx - 14, hy - 19), (cx + 14, hy - 19)], 1.0), gl)
	ecol = mix((0x60, 0x30, 0x60), (0xFF, 0xB0, 0xE0), eye_glow)
	if dying:
		c.eye(cx - 11, hy, 7.5, x_eye=True)
		c.eye(cx + 11, hy, 7.5, x_eye=True)
	else:
		for side in (-1, 1):
			c.glow(lambda d, side=side: d.ellipse_l(cx + side * 11, hy, 8.6, 8.6), ecol, 2)
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 11, hy, 6.4, 6.4), mix(ecol, (1, 1, 1), 0.55))
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 11 + 0.5, hy + 0.8, 3.4, 3.8), (0x30, 0x10, 0x34))
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 11 - 1.4, hy - 1.4, 1.5, 1.5), (1, 1, 1))
	# крохотный рот — улыбка
	mouth = 0.0 if anim != "roar" else 1.0
	if anim == "roar":
		c.flat(lambda d: d.ellipse_l(cx, hy + 12, 6.5, 4.0), (0x20, 0x08, 0x20))
		c.flat(lambda d: d.poly_l([(cx - 4, hy + 9), (cx - 2.5, hy + 12), (cx - 1, hy + 9)]), (0xF0, 0xE8, 0xD0))
		c.flat(lambda d: d.poly_l([(cx + 4, hy + 9), (cx + 2.5, hy + 12), (cx + 1, hy + 9)]), (0xF0, 0xE8, 0xD0))
	else:
		c.flat(lambda d: d.line_l([(cx - 4.5, hy + 10.5), (cx, hy + 12.5), (cx + 4.5, hy + 10.5)], 1.0), OL)
		c.flat(lambda d: d.poly_l([(cx - 2.2, hy + 11.2), (cx - 1.0, hy + 14), (cx - 0.1, hy + 11.8)]), (0xF0, 0xE8, 0xD0))
		c.flat(lambda d: d.poly_l([(cx + 2.2, hy + 11.2), (cx + 1.0, hy + 14), (cx + 0.1, hy + 11.8)]), (0xF0, 0xE8, 0xD0))
	# правый кулак — поверх всего (удар)
	rx, ry = 106 + fist_r[0], 100 + by + fist_r[1]
	if dying:
		rx, ry = 108, 108 + by * 0.4
	fist(rx, ry, 1.0, True)
	if dust:
		for k in range(7):
			c.flat(lambda d, k=k: d.ellipse_l(rx + (k - 3) * 6.5, ground - 2 - (k % 3) * 2.5, 4 - abs(k - 3) * 0.4, 2.8), (0xD8, 0xD0, 0xC4), 190)


# ---------------------------------------------------------------------------
# Сборка листов
# ---------------------------------------------------------------------------

ANIMS = {
	"cinder_grub": [("idle", 4, 5, True), ("move", 6, 9, True), ("attack", 4, 10, False), ("die", 5, 8, False)],
	"gloom_moth": [("idle", 4, 8, True), ("move", 6, 14, True), ("attack", 4, 10, False), ("die", 5, 8, False)],
	"rift_hopper": [("idle", 4, 4, True), ("move", 6, 9, True), ("attack", 4, 8, False), ("die", 5, 8, False)],
	"rock_mimic": [("idle", 4, 4, True), ("move", 6, 10, True), ("attack", 4, 9, False), ("die", 5, 8, False), ("dormant", 2, 2, True)],
	"spark_swarm": [("idle", 4, 9, True), ("move", 4, 12, True), ("attack", 3, 10, False), ("die", 4, 12, False)],
	"abyss_warden": [("idle", 4, 4, True), ("move", 6, 8, True), ("attack", 4, 6, False), ("die", 5, 7, False)],
	"abyss_idol": [("idle", 4, 4, True), ("attack", 6, 6, False), ("exposed", 4, 6, True), ("roar", 4, 8, True), ("die", 6, 4, False)],
}


def build_one(mid):
	spec = MONSTERS[mid]
	fw, fh = spec["frame"]
	anims = ANIMS[mid]
	cols = max(a[1] for a in anims)
	sheet = Image.new("RGBA", (cols * fw * S, len(anims) * fh * S), (0, 0, 0, 0))
	meta_anims = {}
	for row, (name, nf, fps, loop) in enumerate(anims):
		for i in range(nf):
			c = Canvas(fw, fh, seed=11 + i)
			spec["fn"](c, name, i, nf)
			c.outline_all(1.0)
			sheet.alpha_composite(c.image(), (i * fw * S, row * fh * S))
		meta_anims[name] = {"row": row, "frames": nf, "fps": fps, "loop": loop}
	os.makedirs(OUT, exist_ok=True)
	sheet.save(os.path.join(OUT, mid + ".png"))
	meta = {"frame": [fw, fh], "scale": S, "foot": spec["foot"], "anchor": spec["anchor"], "anims": meta_anims}
	with open(os.path.join(OUT, mid + ".json"), "w", encoding="utf-8") as f:
		json.dump(meta, f, ensure_ascii=False, indent="\t")
	return sheet, meta


def build_slash():
	"""Взмах героя: четыре кадра 48×48, дуга справа от героя (разворот — флипом)."""
	fw = fh = 48
	sheet = Image.new("RGBA", (4 * fw * S, fh * S), (0, 0, 0, 0))
	for i in range(4):
		c = Canvas(fw, fh)
		a0 = -75 + i * 6
		a1 = a0 + 60 + i * 22
		cx, cy = 10.0, 24.0
		r_out, r_in = 28.0 - i * 1.5, 19.0 - i * 1.0
		pts_out, pts_in = [], []
		steps = 18
		for k in range(steps + 1):
			a = math.radians(a0 + (a1 - a0) * k / steps)
			w = math.sin(math.pi * k / steps)
			ro = r_in + (r_out - r_in) * (0.35 + 0.65 * w)
			pts_out.append((cx + math.cos(a) * ro, cy + math.sin(a) * ro))
			pts_in.append((cx + math.cos(a) * r_in, cy + math.sin(a) * r_in))
		poly = pts_out + pts_in[::-1]
		alpha = 255 if i < 3 else 150
		c.flat(lambda d, poly=poly: d.poly_l(poly), (0xFF, 0xE0, 0x80), alpha)
		inner = []
		for k in range(steps + 1):
			a = math.radians(a0 + (a1 - a0) * k / steps)
			w = math.sin(math.pi * k / steps)
			ro = r_in + (r_out - r_in) * (0.2 + 0.4 * w)
			inner.append((cx + math.cos(a) * ro, cy + math.sin(a) * ro))
		poly2 = inner + pts_in[::-1]
		c.flat(lambda d, poly2=poly2: d.poly_l(poly2), (0xFF, 0xFF, 0xFF), alpha)
		sheet.alpha_composite(c.image(), (i * fw * S, 0))
	sheet.save(os.path.join(OUT, "fx_slash.png"))


def main():
	sheet_dir = sys.argv[1] if len(sys.argv) > 1 else None
	only = sys.argv[2:] if len(sys.argv) > 2 else None
	for mid in MONSTERS:
		if only and mid not in only:
			continue
		sheet, meta = build_one(mid)
		print(mid, sheet.size)
		if sheet_dir:
			os.makedirs(sheet_dir, exist_ok=True)
			bg = Image.new("RGBA", sheet.size, (0x2A, 0x24, 0x34, 255))
			bg.alpha_composite(sheet)
			bg.save(os.path.join(sheet_dir, "sheet_%s.png" % mid))
	if not only:
		build_slash()
		print("fx_slash")


if __name__ == "__main__":
	main()
