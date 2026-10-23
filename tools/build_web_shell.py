#!/usr/bin/env python3
"""Сборка оболочки веб-версии.

web/shell.src.html (правим его) + art/brand/* -> web/shell.html: картинки и шрифт вшиваются как data:-адреса,
поэтому оболочка работает и без лишних файлов рядом (обычный экспорт из редактора тоже даёт готовую страницу).
web/shell.html лежит в репозитории, на него смотрит `html/custom_html_shell` веб-пресета.

Что ещё умеет:
  --check          ничего не пишет; код 1, если web/shell.html отстал от исходника или картинок
  --install DIR    положить рядом с экспортом то, что нельзя вшить: manifest.webmanifest и иконки приложения
                   (его же зовёт tools/stamp_web_build.py после экспорта)
"""
import base64
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "web" / "shell.src.html"
OUT = ROOT / "web" / "shell.html"
BRAND = ROOT / "art" / "brand"
MANIFEST = ROOT / "web" / "pwa" / "manifest.webmanifest"
# Файлы рядом с index.html; адреса в manifest и в <head> оболочки — относительные, без путей.
PWA_FILES = ["icon-192.png", "icon-512.png", "icon-maskable-512.png", "apple-touch-icon.png", "favicon-32.png", "favicon.ico"]
MIME = {".png": "image/png", ".woff": "font/woff"}


def build_html() -> str:
	src = SRC.read_text(encoding="utf-8")

	def inline(m):
		path = BRAND / m.group(1)
		mime = MIME[path.suffix]
		return "data:%s;base64,%s" % (mime, base64.b64encode(path.read_bytes()).decode("ascii"))

	return re.sub(r"\{\{ASSET:([A-Za-z0-9_.\-]+)\}\}", inline, src)


def install(dest: pathlib.Path) -> None:
	dest.mkdir(parents=True, exist_ok=True)
	shutil.copyfile(MANIFEST, dest / "manifest.webmanifest")
	for name in PWA_FILES:
		shutil.copyfile(BRAND / name, dest / name)
	print("оболочка: manifest и иконки скопированы в %s" % dest)


def main() -> None:
	args = sys.argv[1:]
	if "--install" in args:
		install(pathlib.Path(args[args.index("--install") + 1]))
		return
	html = build_html()
	if "--check" in args:
		if not OUT.exists() or OUT.read_text(encoding="utf-8") != html:
			sys.exit("web/shell.html устарел — запустите python3 tools/build_web_shell.py")
		print("web/shell.html актуален")
		return
	OUT.write_text(html, encoding="utf-8")
	print("web/shell.html: %.1f КБ" % (len(html.encode("utf-8")) / 1024))


if __name__ == "__main__":
	main()
