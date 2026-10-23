#!/usr/bin/env python3
"""Единый атлас тайлов мира: art/tiles/world_atlas.png + world_atlas.json.

Зачем. Каждый тайл на экране — отдельный спрайт, и соседние клетки с разными текстурами рвут
пакет отрисовки (draw call на каждую смену текстуры): в исследованной шахте это 100-190 вызовов
на кадр только от мира, а в браузере каждый вызов WebGL стоит десятки микросекунд на одной нити.
Когда ВСЕ клетки (тайлы всех поясов и сплошная заливка тумана) берутся из одной текстуры, весь
слой мира — один пакет. Картинка в пикселях та же: нарезка идёт тем же шагом, что у атласов
поясов (cell 96, pad 2), фильтр ближайший.

Что внутри (порядок фиксирован, сначала пояс 0 по алфавиту, потом поясы 1..7 в порядке
art/tiles/deep/atlas.json, последней — белая клетка для заливок):
  * "0/<имя>"  — art/tiles/<имя>.png (пояс «Корни»: земля, камень, руды, лава, трава…);
  * "<i>/<имя>" — вырезка из art/tiles/deep/belt_<i>.png для i = 1..7;
  * "white"     — белая клетка: цвет тумана/серой породы красится modulate поверх неё.

Источники НЕ удаляются: из них атлас пересобирается, а часть кода грузит их напрямую. Тест
tests/test_perf.gd сверяет каждый регион атласа с источником и падает, если атлас устарел —
запусти этот скрипт заново после любой правки тайлов:

  python3 tools/gen_world_atlas.py
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TILES = os.path.join(ROOT, "art", "tiles")
DEEP = os.path.join(TILES, "deep")
CELL = 96
PAD = 2
COLS = 18


def main() -> int:
	meta = json.load(open(os.path.join(DEEP, "atlas.json"), encoding="utf-8"))
	b_cell, b_pad, b_cols = int(meta["cell"]), int(meta["pad"]), int(meta["cols"])
	if b_cell != CELL:
		print("атлас поясов не %dx%d — скрипт надо поправить" % (CELL, CELL))
		return 1
	b_stride = b_cell + 2 * b_pad

	entries = []  # (ключ, изображение 96x96 RGB)
	for path in sorted(glob.glob(os.path.join(TILES, "*.png"))):
		name = os.path.splitext(os.path.basename(path))[0]
		im = Image.open(path).convert("RGB")
		if im.size != (CELL, CELL):
			print("пропущен %s: размер %s, не %dx%d" % (name, im.size, CELL, CELL))
			continue
		entries.append(("0/" + name, im))
	for belt in range(1, 8):
		src = Image.open(os.path.join(DEEP, "belt_%d.png" % belt)).convert("RGB")
		for i, name in enumerate(meta["names"]):
			x = (i % b_cols) * b_stride + b_pad
			y = (i // b_cols) * b_stride + b_pad
			entries.append(("%d/%s" % (belt, name), src.crop((x, y, x + CELL, y + CELL))))
	entries.append(("white", Image.new("RGB", (CELL, CELL), (255, 255, 255))))

	rows = (len(entries) + COLS - 1) // COLS
	stride = CELL + 2 * PAD
	atlas = Image.new("RGB", (COLS * stride, rows * stride), (0, 0, 0))
	index = {}
	for n, (key, im) in enumerate(entries):
		cx, cy = (n % COLS) * stride, (n // COLS) * stride
		# поля в PAD пикселей — повтор края клетки, чтобы ничто не просачивалось с соседа
		arr = np.pad(np.asarray(im), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
		atlas.paste(Image.fromarray(arr), (cx, cy))
		index[key] = n
	out_png = os.path.join(TILES, "world_atlas.png")
	atlas.save(out_png, optimize=True)
	out_json = os.path.join(TILES, "world_atlas.json")
	with open(out_json, "w", encoding="utf-8") as f:
		json.dump({"cell": CELL, "pad": PAD, "cols": COLS, "rows": rows, "tiles": index}, f, ensure_ascii=False, separators=(",", ":"))
		f.write("\n")
	print("атлас %dx%d, %d клеток -> %s (%d КБ)" % (atlas.size[0], atlas.size[1], len(entries),
		os.path.relpath(out_png, ROOT), os.path.getsize(out_png) // 1024))
	return 0


if __name__ == "__main__":
	sys.exit(main())
