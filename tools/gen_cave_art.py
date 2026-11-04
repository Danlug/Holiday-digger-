#!/usr/bin/env python3
"""gen_cave_art.py — графика полостей-фигур (раунд 5): стражи, снаряды, сундук полости.

Тем же инструментом, что монстры раунда 1 (tools/gen_monsters.py: Canvas — обводка,
световая кромка, тень с дизерингом, 6–8 тонов на деталь) и сундуки тайников
(tools/gen_mechanics_art.py). Заглушки уровня «программист нарисовал аккуратно»,
не работа художника владельца; руками PNG не правим — меняй рисунок здесь.

    python3 tools/gen_cave_art.py [каталог_для_контактных_листов]

Результат:
  art/monsters/cave_bat|cave_toad|shell_beetle|acid_spitter.png + .json — листы кадров
      (строка — анимация idle/move/attack/die, столбец — кадр; читает monster_sheet.gd);
  art/monsters/fx_projectiles.png + .json — снаряды: кислота, камень, искра (2 кадра);
  art/mechanics/chest_cave.png — сундук полости, 5 кадров 96×96: закрыт · приоткрыт ·
      открыт с добычей · пуст · заперт (цепи и замок, пока живы стражи);
  art/mechanics/chest_cave_icon.png — закрытый сундук 32×32; cave_lock.png — замок 16×16.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_monsters as gm  # noqa: E402
import gen_mechanics_art as ma  # noqa: E402

S = gm.S
OL = gm.OL
mix, lighten, darken = gm.mix, gm.lighten, gm.darken


# ---------------------------------------------------------------------------
# Стражи
# ---------------------------------------------------------------------------

@gm.monster("cave_bat", (40, 32), 0, anchor="center")
def bat(c, anim, i, n):
	"""Гротовая мышь: пушистое тельце, перепончатые крылья, большие уши, глаза-фонарики."""
	cx, cy = 20.0, 16.0
	fur = (0x5A, 0x44, 0x6E)
	wing = (0x3E, 0x2C, 0x52)
	wing_l = (0x6A, 0x52, 0x86)
	ph = i / n
	flap = math.cos(ph * math.tau)              # 1 — крылья вверх, -1 — вниз
	if anim == "idle":
		flap = math.cos(ph * math.tau) * 0.5
	mouth = 0.0
	eyes = (0xFF, 0xE0, 0x60)
	droop = 0.0
	if anim == "attack":
		p = i / (n - 1)
		flap = 0.9 - p * 1.9
		mouth = min(1.0, p * 1.6)
		eyes = (0xFF, 0x60, 0x50)
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		flap = -0.3 - 0.7 * p
		droop = 6 * p
		cy += droop
	wy = -flap * 7.0
	for side in (-1, 1):
		# крыло: три «пальца» с перепонкой между ними
		tip = (cx + side * 17.5, cy - 7 + wy)
		mid = (cx + side * 12, cy - 1 + wy * 0.55)
		low = (cx + side * 9, cy + 6 + wy * 0.2)
		root = (cx + side * 3, cy + 1)
		c.part(lambda d, p=[root, (cx + side * 6, cy - 4 + wy * 0.35), tip, mid, low, (cx + side * 4, cy + 4)]: d.poly_l(p),
			wing, outline=darken(wing, 0.55))
		for f in (tip, mid, low):
			c.flat(lambda d, f=f: d.line_l([root, f], 0.9), wing_l)
	# тело и голова
	c.part(lambda d: d.ellipse_l(cx, cy + 2.5, 4.4, 5.6), fur, tex=0.12)
	hy = cy - 3.5
	c.part(lambda d: d.ellipse_l(cx, hy, 5.0, 4.6), lighten(fur, 0.08), tex=0.1)
	# уши
	for side in (-1, 1):
		c.part(lambda d, side=side: d.poly_l([(cx + side * 1.5, hy - 3), (cx + side * 5.5, hy - 10 + droop * 0.3), (cx + side * 5.2, hy - 2)]), fur, shade=False)
		c.flat(lambda d, side=side: d.poly_l([(cx + side * 2.6, hy - 3.6), (cx + side * 4.8, hy - 7.5 + droop * 0.3), (cx + side * 4.6, hy - 3)]), (0xC0, 0x80, 0xA0))
	# глаза и пасть
	if dying:
		c.eye(cx - 2.2, hy, 1.9, x_eye=True)
		c.eye(cx + 2.2, hy, 1.9, x_eye=True)
	else:
		for side in (-1, 1):
			c.glow(lambda d, side=side: d.ellipse_l(cx + side * 2.2, hy, 1.9, 1.9), eyes, 1)
			c.flat(lambda d, side=side: d.ellipse_l(cx + side * 2.2 + 0.3, hy + 0.2, 0.8, 1.1), (0x20, 0x10, 0x28))
	c.flat(lambda d: d.poly_l([(cx - 2.2, hy + 2.6), (cx + 2.2, hy + 2.6), (cx + 1.6, hy + 3.4 + mouth * 2.2), (cx - 1.6, hy + 3.4 + mouth * 2.2)]), (0x2A, 0x10, 0x20))
	for side in (-1, 1):
		c.flat(lambda d, side=side: d.poly_l([(cx + side * 1.6, hy + 2.6), (cx + side * 1.0, hy + 2.6), (cx + side * 1.3, hy + 4.0 + mouth)]), (0xF4, 0xF0, 0xE8))


@gm.monster("cave_toad", (40, 36), 1)
def toad(c, anim, i, n):
	"""Каменная жаба: бугристая спина, глаза-шары сверху, мощные задние лапы."""
	ground = 34.0
	skin = (0x5E, 0x7A, 0x48)
	skin_d = (0x3E, 0x56, 0x34)
	belly = (0xC8, 0xC8, 0x90)
	wart = (0x8A, 0x8C, 0x6C)
	ph = i / n
	sq = 1.0
	air = 0.0
	stretch = 0.0
	if anim == "idle":
		sq = 1.0 + math.sin(ph * math.tau) * 0.05
	if anim == "move":
		air = max(0.0, math.sin(ph * math.tau)) * 4.0
		sq = 1.0 - 0.1 * (0.5 - 0.5 * math.cos(ph * math.tau * 2))
		stretch = max(0.0, math.sin(ph * math.tau)) * 0.3
	if anim == "attack":
		p = i / (n - 1)
		if p < 0.7:
			sq = 1.0 - 0.38 * (p / 0.7)
		else:
			sq = 1.18
			air = 3.0
			stretch = 0.5
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		sq = 0.75 - 0.25 * p
	cx = 20.0
	bw = 12.5 + stretch * 4
	bh = 8.5 * sq
	by = ground - air - bh - 1.5
	# задние лапы: согнутые, крупные
	for side in (-1, 1):
		kx = cx + side * 11
		c.part(lambda d, kx=kx: d.ellipse_l(kx, by + bh * 0.55, 4.6, 4.2 * (0.7 + 0.3 * sq)), skin_d)
		c.part(lambda d, kx=kx, side=side: d.line_l([(kx + side * 1, ground - air - 3.5), (kx + side * 4.5, ground - air - 0.6)], 2.4), skin_d)
	# тело
	c.part(lambda d: d.ellipse_l(cx, by, bw, bh), skin, tex=0.06)
	c.part(lambda d: d.ellipse_l(cx, by + bh * 0.45, bw * 0.7, bh * 0.5), belly, shade=False, outline=darken(belly, 0.5))
	# бугры-камешки на спине
	for (dx, dy, r) in ((-7, -0.55, 1.6), (-2, -0.85, 1.4), (3.5, -0.75, 1.7), (8, -0.4, 1.3), (0.5, -0.3, 1.1)):
		c.part(lambda d, dx=dx, dy=dy, r=r: d.ellipse_l(cx + dx, by + bh * dy, r, r * 0.8), wart, shade=True, rim=0.6)
	# передние лапки
	for side in (-1, 1):
		c.part(lambda d, side=side: d.line_l([(cx + side * 6, by + bh * 0.5), (cx + side * 7.5, ground - air - 0.8)], 2.0), skin_d)
	# глаза сверху на буграх
	ey = by - bh * 0.95
	if dying:
		c.eye(cx - 5, ey + 1, 3.0, x_eye=True)
		c.eye(cx + 5, ey + 1, 3.0, x_eye=True)
	else:
		lid = 0.45 if anim == "attack" and i < n - 1 else 0.1
		c.eye(cx - 5, ey + 1, 3.2, look=(1, 0.2), lid=lid, lid_col=skin, iris=(0xF6, 0xE8, 0x90))
		c.eye(cx + 5, ey + 1, 3.2, look=(1, 0.2), lid=lid, lid_col=skin, iris=(0xF6, 0xE8, 0x90))
	# широкий рот
	mo = 0.0 if anim != "attack" else min(1.0, (i / (n - 1)) * 1.4) * 2.5
	c.flat(lambda d: d.line_l([(cx - bw * 0.7, by + bh * 0.2), (cx, by + bh * 0.45 + mo), (cx + bw * 0.7, by + bh * 0.2)], 0.9), OL)
	if mo > 1.0:
		c.flat(lambda d: d.poly_l([(cx - bw * 0.5, by + bh * 0.25), (cx + bw * 0.5, by + bh * 0.25), (cx, by + bh * 0.45 + mo)]), (0xB0, 0x40, 0x50))


@gm.monster("shell_beetle", (44, 28), 1)
def beetle(c, anim, i, n):
	"""Панцирный жук: бронзовый панцирь с пластинами, рог, шесть ног."""
	ground = 26.0
	shell = (0x9A, 0x6E, 0x38)
	shell_d = (0x5E, 0x40, 0x22)
	plate = (0xC0, 0x92, 0x4A)
	leg = (0x3A, 0x2A, 0x1E)
	ph = i / n
	step = 0.0
	bob = 0.0
	horn = 0.0
	tilt = 0.0
	if anim == "idle":
		bob = math.sin(ph * math.tau) * 0.4
	if anim == "move":
		step = math.sin(ph * math.tau)
		bob = -abs(math.sin(ph * math.tau)) * 0.8
	if anim == "attack":
		p = i / (n - 1)
		if p < 0.65:
			tilt = -p / 0.65 * 3.0     # отводит голову назад и вниз
		else:
			tilt = 4.0                 # выпад: рог вперёд-вверх
			horn = 1.0
	dying = anim == "die"
	cx = 21.0
	if dying:
		p = i / (n - 1)
		# переворачивается на спину, ноги вверх
		c.part(lambda d: d.ellipse_l(cx, ground - 7 + 2 * p, 14, 7.5 - 1.5 * p), shell_d, tex=0.05)
		c.part(lambda d: d.ellipse_l(cx, ground - 7 + 2 * p, 10, 4.5), (0x6E, 0x50, 0x34), shade=False)
		for k in range(6):
			lx = cx - 10 + k * 4
			c.flat(lambda d, lx=lx, k=k: d.line_l([(lx, ground - 12 + 2 * p), (lx + (1 if k % 2 else -1) * 2, ground - 18 + 4 * p + (k % 2) * 2)], 1.4), leg)
		c.eye(cx + 11, ground - 6, 2.2, x_eye=True)
		return
	# ноги (три пары, шагают попеременно)
	for k, dx in enumerate((-10, -3, 4)):
		for side_k, sgn in enumerate((1, -1)):
			s = step * (1 if (k + side_k) % 2 == 0 else -1)
			c.flat(lambda d, dx=dx, s=s, sgn=sgn: d.line_l([(cx + dx, ground - 6 + bob), (cx + dx + s * 2.0 - 1.5, ground - 2.5), (cx + dx + s * 3.0 - 2.5, ground)], 1.5), leg)
	# панцирь: купол с пластинами
	c.part(lambda d: d.ellipse_l(cx, ground - 8 + bob, 14, 8), shell, tex=0.05)
	for k, x0 in enumerate((-9, -3, 3, 9)):
		c.flat(lambda d, x0=x0: d.line_l([(cx + x0, ground - 15.5 + bob + abs(x0) * 0.35), (cx + x0, ground - 1.5 + bob - abs(x0) * 0.1)], 0.9), shell_d)
	c.part(lambda d: d.ellipse_l(cx - 2, ground - 12 + bob, 7.5, 3.0), plate, shade=False, outline=darken(plate, 0.5))
	c.flat(lambda d: d.ellipse_l(cx - 4, ground - 12.5 + bob, 2.2, 1.0), lighten(plate, 0.5))
	# голова с рогом
	hx = cx + 13
	hy = ground - 5.5 + bob + tilt * 0.3
	c.part(lambda d: d.ellipse_l(hx, hy, 5.0, 4.2), shell_d, tex=0.05)
	hx2 = hx + 3 + tilt * 0.8
	hy2 = hy - 4 - (tilt if tilt > 0 else tilt * 0.5)
	c.part(lambda d: d.poly_l([(hx + 1, hy - 2), (hx2 + 3, hy2 - 3 - horn * 2), (hx2 + 5 + horn * 2, hy2 + 1), (hx + 4, hy + 0.5)]), plate, shade=False, outline=OL)
	c.eye(hx + 2, hy + 0.6, 1.8, look=(1, 0), glow_col=(0xFF, 0x80, 0x50) if anim == "attack" else None)
	# жвалы
	c.flat(lambda d: d.line_l([(hx + 4, hy + 2.5), (hx + 7, hy + 3.5 + horn)], 0.9), leg)


@gm.monster("acid_spitter", (40, 36), 1)
def spitter(c, anim, i, n):
	"""Плевун: слизняк с раздувающимся зобом, глаза на стебельках, кислотная пасть."""
	ground = 34.0
	body = (0x8A, 0xA8, 0x3A)
	body_d = (0x5A, 0x72, 0x24)
	throat = (0xC8, 0xE0, 0x60)
	acid = (0x9A, 0xF0, 0x4A)
	ph = i / n
	puff = 0.0
	spit = 0.0
	ripple = 0.0
	if anim == "idle":
		puff = 0.05 + 0.05 * math.sin(ph * math.tau)
	if anim == "move":
		ripple = math.sin(ph * math.tau)
		puff = 0.05
	if anim == "attack":
		p = i / (n - 1)
		if p < 0.7:
			puff = 0.1 + 0.6 * (p / 0.7)
		else:
			puff = 0.0
			spit = 1.0
	dying = anim == "die"
	if dying:
		p = i / (n - 1)
		puff = -0.5 * p
	cx = 19.0
	bh = 9.0 * (1.0 + puff * 0.6)
	bw = 11.0 * (1.0 + puff * 0.25)
	by = ground - bh - 0.5
	if dying:
		bh = 9.0 * (1.0 - 0.6 * (i / (n - 1)))
		bw = 11.0 + 5.0 * (i / (n - 1))
		by = ground - bh - 0.5
	# слизистый след
	c.flat(lambda d: d.ellipse_l(cx - 2, ground - 0.3, bw * 1.15, 1.3), (0xB8, 0xE0, 0x80), 150)
	# тело
	c.part(lambda d: d.ellipse_l(cx, by, bw, bh), body, tex=0.07)
	# брюшная складка (волна при движении)
	for k in range(3):
		yy = by + bh * (0.35 + 0.22 * k) + ripple * (1 if k % 2 else -1) * 0.6
		c.flat(lambda d, yy=yy, k=k: d.line_l([(cx - bw * (0.8 - 0.1 * k), yy), (cx + bw * (0.8 - 0.1 * k), yy)], 0.8), body_d)
	# зоб с кислотой: светится, когда раздут
	if puff > 0.12 or spit:
		c.glow(lambda d: d.ellipse_l(cx + bw * 0.35, by + bh * 0.1, bw * 0.4 * (0.6 + puff), bh * 0.5 * (0.6 + puff)), throat, 1)
	# пасть
	mx = cx + bw * 0.78
	mo = 1.2 + puff * 2.0 + spit * 3.0
	c.flat(lambda d: d.ellipse_l(mx, by + bh * 0.1, 2.4 + spit, mo), (0x2A, 0x24, 0x10))
	if spit:
		c.glow(lambda d: d.ellipse_l(mx + 4, by + bh * 0.05, 2.6, 2.2), acid, 1, core=(0xE8, 0xFF, 0xB0))
	# глаза на стебельках
	for side, dx in ((-1, -3.5), (1, 2.5)):
		top = (cx + dx + side * 0.5, by - bh * 0.9 - 4 + (3 if dying else 0))
		c.part(lambda d, dx=dx, top=top: d.line_l([(cx + dx, by - bh * 0.6), top], 1.4), body_d)
		if dying:
			c.eye(top[0], top[1], 2.0, x_eye=True)
		else:
			c.eye(top[0], top[1], 2.1, look=(1, 0.15), lid=0.3 if anim == "attack" else 0.0, lid_col=body)


gm.ANIMS.update({
	"cave_bat": [("idle", 4, 8, True), ("move", 6, 14, True), ("attack", 4, 10, False), ("die", 5, 8, False)],
	"cave_toad": [("idle", 4, 4, True), ("move", 6, 9, True), ("attack", 4, 8, False), ("die", 5, 8, False)],
	"shell_beetle": [("idle", 4, 4, True), ("move", 6, 10, True), ("attack", 4, 8, False), ("die", 5, 8, False)],
	"acid_spitter": [("idle", 4, 5, True), ("move", 6, 8, True), ("attack", 5, 8, False), ("die", 5, 8, False)],
})
GUARDS = ["cave_bat", "cave_toad", "shell_beetle", "acid_spitter"]


# ---------------------------------------------------------------------------
# Снаряды
# ---------------------------------------------------------------------------

PROJ = {"acid": 0, "stone": 1, "spark": 2}


def build_projectiles():
	fw = fh = 12
	frames = 2
	sheet = Image.new("RGBA", (frames * fw * S, len(PROJ) * fh * S), (0, 0, 0, 0))
	for kind, row in PROJ.items():
		for i in range(frames):
			c = gm.Canvas(fw, fh, seed=3 + i)
			cx, cy = 6.0, 6.0
			if kind == "acid":
				# капля кислоты, вытянутая по полёту, с бликом и ядром посветлее
				c.glow(lambda d: d.ellipse_l(cx + 0.5, cy, 3.6 + 0.4 * i, 2.6 - 0.3 * i), (0x7A, 0xD0, 0x30), 1)
				c.flat(lambda d: d.ellipse_l(cx + 1, cy - 0.3, 2.0, 1.3), (0xC8, 0xFF, 0x80))
				c.flat(lambda d: d.ellipse_l(cx - 0.2 + i * 0.6, cy - 1.0, 0.7, 0.6), (0xFF, 0xFF, 0xE0))
			elif kind == "stone":
				pts = [(cx - 3.5, cy + 1), (cx - 2, cy - 3), (cx + 2.5, cy - 2.5), (cx + 3.5, cy + 1.5), (cx + 0.5, cy + 3.5)]
				if i == 1:
					pts = [(cx - 3.5, cy - 1), (cx, cy - 3.5), (cx + 3.5, cy - 1), (cx + 2.5, cy + 3), (cx - 2.5, cy + 3)]
				c.part(lambda d, pts=pts: d.poly_l(pts), (0x8A, 0x84, 0x7C), tex=0.1)
			else:
				c.glow(lambda d: d.ellipse_l(cx, cy, 2.6, 2.6), (0xFF, 0xA0, 0x30), 2)
				c.flat(lambda d: d.ellipse_l(cx, cy, 1.4 + 0.4 * i, 1.4 + 0.4 * i), (0xFF, 0xF0, 0xA0))
			c.outline_all(1.0)
			sheet.alpha_composite(c.image(), (i * fw * S, row * fh * S))
	os.makedirs(gm.OUT, exist_ok=True)
	sheet.save(os.path.join(gm.OUT, "fx_projectiles.png"))
	meta = {"frame": [fw, fh], "scale": S, "foot": 0, "anchor": "center",
		"anims": {k: {"row": r, "frames": frames, "fps": 9, "loop": True} for k, r in PROJ.items()}}
	with open(os.path.join(gm.OUT, "fx_projectiles.json"), "w", encoding="utf-8") as f:
		json.dump(meta, f, ensure_ascii=False, indent="\t")
	return sheet


# ---------------------------------------------------------------------------
# Сундук полости: обсидиановый корпус, кристальная окантовка, пятый кадр — цепи и замок
# ---------------------------------------------------------------------------

OBSIDIAN = [ma.hexc(c) for c in ("#120a1c", "#231436", "#34204e", "#452c66", "#58397e", "#6c4a96", "#8a66b4", "#b08ad4")]
CRYSTAL = [ma.hexc(c) for c in ("#0c3a46", "#13596a", "#1c7f92", "#27a6ba", "#3ccbdc", "#6fe4ef", "#a8f4f8", "#e6fdff")]
CYAN_GEM = [ma.hexc(c) for c in ("#063a40", "#0c6068", "#148a92", "#1fb6bc", "#3ddcd8", "#8af2ee", "#d6fffc")]
CHAIN = [ma.hexc(c) for c in ("#1a1c22", "#33363e", "#4e525c", "#6a6f7a", "#8a909c", "#b0b6c2", "#d8dde6")]
RED = [ma.hexc(c) for c in ("#4a0c0c", "#8a1a16", "#c43024", "#ee5a3c", "#ff9a6a", "#ffd0b0")]

CAVE_SPEC = {"wood": OBSIDIAN, "band": CRYSTAL, "lock": ma.GOLD, "glow": CRYSTAL, "gem": CYAN_GEM, "studs": True,
	"mid_bands": True, "lid": None}
ma.CHESTS["cave"] = CAVE_SPEC


def cave_chest_frame(frame):
	spec = CAVE_SPEC
	seed = 13
	a = ma.blank()
	if frame in (0, 4):
		ma._body(a, spec, seed)
		ma._lid_closed(a, spec, seed)
		ma._lock(a, 15, ma.BODY_Y0, spec)
	elif frame == 1:
		ma._body(a, spec, seed)
		for x in range(ma.BX0 + 1, ma.BX1):
			a[ma.BODY_Y0 - 1, x] = spec["glow"][6]
			a[ma.BODY_Y0 - 2, x] = spec["glow"][5]
		ma._lid_closed(a, spec, seed, lift=2)
		ma._lock(a, 15, ma.BODY_Y0, spec)
	else:
		ma._lid_open(a, spec)
		ma._body(a, spec, seed)
		ma._interior(a, spec, loot=(frame == 2))
		ma._lock(a, 15, ma.BODY_Y0 + 2, spec, open_=True)
	ma.outline(a, spec["wood"][0])
	if frame == 1:
		ma._rays(a, spec["glow"][6])
	if frame in (0, 2):
		# искры на кристальной окантовке
		for (x, y) in ((8, 13), (23, 20)) if frame == 0 else ((9, 10), (21, 13)):
			ma.px(a, x, y, CRYSTAL[7])
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				if a[y + dy, x + dx, 3] == 0:
					ma.px(a, x + dx, y + dy, (230, 253, 255, 200))
	if frame == 4:
		_chains(a)
	ma._shadow(a)
	if frame in (1, 2):
		a = ma.over(ma._glow_layer(spec["glow"][5], 15.5, 13, 13 if frame == 1 else 10, 0.35 if frame == 1 else 0.22), a)
	if frame == 4:
		a = ma.over(ma._glow_layer(RED[3], 15.5, 22, 9, 0.22), a)
	return a


def _chains(a):
	"""Две цепи крест-накрест через крышку и корпус, спереди — замок с красным глазком."""
	G = ma.G
	for (x0, y0, x1, y1) in ((4, 9, 27, 29), (27, 9, 4, 29)):
		n = 22
		for k in range(n + 1):
			x = int(round(x0 + (x1 - x0) * k / n))
			y = int(round(y0 + (y1 - y0) * k / n))
			link = k % 2 == 0
			col = CHAIN[5] if link else CHAIN[3]
			ma.px(a, x, y, col)
			ma.px(a, x + 1, y, CHAIN[4] if link else CHAIN[2])
			ma.px(a, x, y + 1, CHAIN[2])
	# замок: дужка и корпус
	lx, ly = 15, 21
	m = ma.mask_of(lambda d: d.rectangle([lx - 3, ly - 1, lx + 3, ly + 4], fill=255))
	ma.bevel(a, m, CHAIN, 4, light=2, dark=2)
	for (x, y) in ((lx - 2, ly - 2), (lx + 2, ly - 2), (lx - 2, ly - 3), (lx + 2, ly - 3), (lx - 1, ly - 4), (lx, ly - 4), (lx + 1, ly - 4)):
		ma.px(a, x, y, CHAIN[5])
	ma.px(a, lx, ly + 1, RED[3])
	ma.px(a, lx, ly + 2, RED[2])
	ma.px(a, lx - 1, ly + 1, RED[2])
	ma.px(a, lx + 1, ly + 1, RED[2])
	ma.px(a, lx - 3, ly - 1, CHAIN[6])


def build_cave_chest():
	frames = [cave_chest_frame(f) for f in range(5)]
	G, SC = ma.G, ma.SCALE
	sheet = Image.new("RGBA", (G * SC * 5, G * SC), (0, 0, 0, 0))
	for i, fr in enumerate(frames):
		im = Image.fromarray(fr, "RGBA").resize((G * SC, G * SC), Image.NEAREST)
		sheet.paste(im, (i * G * SC, 0))
	ma.save(sheet, "chest_cave.png")
	ma.save(Image.fromarray(frames[0], "RGBA"), "chest_cave_icon.png")
	return sheet


def build_lock_icon():
	"""Замок 16×16 для всплывающего значка «заперто» (Fx.float_icon)."""
	a = ma.blank(16, 16)
	m = ma.mask_of(lambda d: d.rectangle([3, 7, 12, 14], fill=255), 16, 16)
	ma.bevel(a, m, CHAIN, 4, light=2, dark=2)
	for (x, y) in ((4, 6), (11, 6), (4, 5), (11, 5), (5, 4), (6, 3), (7, 3), (8, 3), (9, 3), (10, 4), (4, 4), (11, 4)):
		ma.px(a, x, y, CHAIN[5])
	ma.px(a, 7, 10, RED[3])
	ma.px(a, 8, 10, RED[3])
	ma.px(a, 7, 11, RED[2])
	ma.px(a, 8, 11, RED[2])
	ma.outline(a, CHAIN[0])
	return ma.save(a, "cave_lock.png")


# ---------------------------------------------------------------------------

def main():
	sheet_dir = sys.argv[1] if len(sys.argv) > 1 else None
	for mid in GUARDS:
		sheet, meta = gm.build_one(mid)
		print(mid, sheet.size)
		if sheet_dir:
			os.makedirs(sheet_dir, exist_ok=True)
			bg = Image.new("RGBA", sheet.size, (0x2A, 0x24, 0x34, 255))
			bg.alpha_composite(sheet)
			bg.save(os.path.join(sheet_dir, "sheet_%s.png" % mid))
	pr = build_projectiles()
	print("fx_projectiles", pr.size)
	ch = build_cave_chest()
	print("chest_cave", ch.size)
	build_lock_icon()
	if sheet_dir:
		bg = Image.new("RGBA", (pr.size[0] * 3 + 20 + ch.size[0], max(pr.size[1] * 3, ch.size[1])), (0x2A, 0x24, 0x34, 255))
		bg.alpha_composite(pr.resize((pr.size[0] * 3, pr.size[1] * 3), Image.NEAREST))
		bg.alpha_composite(ch, (pr.size[0] * 3 + 20, 0))
		bg.save(os.path.join(sheet_dir, "sheet_cave_misc.png"))


if __name__ == "__main__":
	main()
