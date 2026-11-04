#!/usr/bin/env python3
"""Брендовая графика для самой игры (не для веб-оболочки) -> art/ui/brand/.

Каталог art/brand закрыт файлом .gdignore (его видит только веб-оболочка), поэтому всё,
что нужно движку — иконка приложения, системная заставка, логотип экранной заставки —
кладётся сюда отдельно, из тех же рисунков tools/gen_brand.py:

  logo.png            логотип 96x68 (копия art/brand/logo.png; экранная заставка SplashScreen)
  boot_splash.png     системная заставка 448x960: логотип x4 на тёмном фоне (project.godot → boot_splash)
  icon.png            иконка приложения 512x512 (project.godot → config/icon; iOS/Android берут её)
  icon_192.png        иконка 192x192 (Android launcher_icons/main_192x192)
  adaptive_fg.png     адаптивная иконка Android 432x432: эмблема в безопасной зоне, фон прозрачный
  adaptive_bg.png     адаптивная иконка Android 432x432: земля на всю плоскость

Всё рисуется кодом, руками PNG не правим. Это аккуратная замена-заглушка «программист нарисовал»,
не работа художника владельца. После запуска: godot --headless --path . --import (новые .import — коммитить).

Запуск: python3 tools/gen_app_brand.py
"""
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_brand  # noqa: E402  — эмблема, земля и палитра те же, что у веб-оболочки

ROOT = HERE.parent
SRC = ROOT / "art" / "brand"
OUT = ROOT / "art" / "ui" / "brand"

SPLASH_W, SPLASH_H = 448, 960       # 2x от проектных 224x480, та же пропорция
SPLASH_BG = (0x0D, 0x0A, 0x07, 255)  # фон страницы веб-оболочки и экранной заставки (SplashScreen.BG)
LOGO_SCALE = 4                      # x2 от экранной заставки (там логотип x2 в вьюпорте 224)
LOGO_Y = 0.42                       # центр логотипа по высоте — как в SplashScreen.LOGO_Y


def make_boot_splash(logo: Image.Image) -> Image.Image:
	im = Image.new("RGBA", (SPLASH_W, SPLASH_H), SPLASH_BG)
	big = logo.resize((logo.width * LOGO_SCALE, logo.height * LOGO_SCALE), Image.NEAREST)
	x = (SPLASH_W - big.width) // 2
	y = int(SPLASH_H * LOGO_Y) - big.height // 2
	im.alpha_composite(big, (x, y))
	return im


def make_adaptive() -> None:
	# Android показывает внутренние 66% адаптивной иконки (круг/капля): эмблема — в этой зоне.
	native = 72
	bg_im = _soil_square(native).resize((432, 432), Image.NEAREST)
	bg_im.save(OUT / "adaptive_bg.png", optimize=True)
	em = gen_brand.emblem(40)
	fg = Image.new("RGBA", (native, native), (0, 0, 0, 0))
	fg.alpha_composite(em.im, ((native - em.w) // 2, (native - em.h) // 2))
	fg.resize((432, 432), Image.NEAREST).save(OUT / "adaptive_fg.png", optimize=True)


def _soil_square(n: int) -> Image.Image:
	"""Земля с вкраплениями без эмблемы: icon_base рисует её вместе с эмблемой, берём только фон."""
	p = gen_brand.icon_base(n, 2)   # эмблема в 2 пикселя — незаметная точка в центре, закрасим
	c = p.get(0, n // 2)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			p.set(n // 2 + dx, n // 2 + dy, c)
	return p.im


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	logo = Image.open(SRC / "logo.png").convert("RGBA")
	logo.save(OUT / "logo.png", optimize=True)
	make_boot_splash(logo).save(OUT / "boot_splash.png", optimize=True)
	icon = Image.open(SRC / "icon-512.png").convert("RGBA")
	icon.save(OUT / "icon.png", optimize=True)
	icon.resize((192, 192), Image.NEAREST).save(OUT / "icon_192.png", optimize=True)
	make_adaptive()
	for f in sorted(OUT.glob("*.png")):
		im = Image.open(f)
		print("%-18s %dx%d" % (f.name, im.width, im.height))


if __name__ == "__main__":
	main()
