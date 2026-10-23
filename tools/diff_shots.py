#!/usr/bin/env python3
"""Сверка двух каталогов скриншотов (до/после): сколько пикселей отличается в каждом кадре.

  python3 tools/diff_shots.py /tmp/shots_before /tmp/shots_after [--save-diff /tmp/diff]

Код возврата 0 — все одноимённые PNG совпали пиксель в пиксель, 1 — есть отличия, 2 — нечего
сравнивать. С --save-diff для каждого отличающегося кадра пишется картинка: красным — отличия.
"""
import os
import sys

import numpy as np
from PIL import Image


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	save = None
	if "--save-diff" in sys.argv:
		save = sys.argv[sys.argv.index("--save-diff") + 1]
		args = [a for a in args if a != save]
		os.makedirs(save, exist_ok=True)
	if len(args) != 2:
		print(__doc__)
		return 2
	a_dir, b_dir = args
	names = sorted(n for n in os.listdir(a_dir) if n.endswith(".png") and os.path.exists(os.path.join(b_dir, n)))
	if not names:
		print("нечего сравнивать: общих PNG нет")
		return 2
	bad = 0
	for n in names:
		a = np.array(Image.open(os.path.join(a_dir, n)).convert("RGB")).astype(int)
		b = np.array(Image.open(os.path.join(b_dir, n)).convert("RGB")).astype(int)
		if a.shape != b.shape:
			print("%-16s РАЗНЫЙ РАЗМЕР %s и %s" % (n, a.shape, b.shape))
			bad += 1
			continue
		d = np.abs(a - b).sum(axis=2) > 0
		cnt = int(d.sum())
		if cnt:
			bad += 1
			ys, xs = np.nonzero(d)
			print("%-16s ОТЛИЧИЙ %d пикселей (%.3f%%), рамка x %d..%d, y %d..%d" % (
				n, cnt, 100.0 * cnt / d.size, xs.min(), xs.max(), ys.min(), ys.max()))
			if save:
				out = b.copy().astype(np.uint8)
				out[d] = (255, 0, 255)
				Image.fromarray(out).save(os.path.join(save, n))
		else:
			print("%-16s совпало пиксель в пиксель" % n)
	print("итого: %d кадров, отличается %d" % (len(names), bad))
	return 1 if bad else 0


if __name__ == "__main__":
	sys.exit(main())
