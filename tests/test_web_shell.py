#!/usr/bin/env python3
"""Проверки веб-оболочки без браузера (не Godot-тест: в tools/run_tests.sh не входит).

Что стережёт:
  - web/shell.html собран из актуального web/shell.src.html и art/brand;
  - в оболочке остались все подстановки Godot и тот самый тег <script src="$GODOT_URL"></script>,
    по которому tools/stamp_web_build.py вставляет сброс кэша; штамп на «экспорте» отрабатывает;
  - manifest.webmanifest и иконки на месте, ни CDN, ни service worker, веб-пресет смотрит на оболочку.
Браузерная проверка (загрузка, «нажмите», телефон, десктоп) — tools/smoke_shell.js.

Запуск:  python3 tests/test_web_shell.py
"""
import importlib.util
import json
import pathlib
import re
import sys
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build_web_shell  # noqa: E402

failures = []
checks = 0


def check(label, ok):
	global checks
	checks += 1
	print(("[OK] " if ok else "[FAIL] ") + label)
	if not ok:
		failures.append(label)


def load_stamp():
	spec = importlib.util.spec_from_file_location("stamp_web_build", ROOT / "tools" / "stamp_web_build.py")
	mod = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(mod)
	return mod


def godot_export(html: str) -> str:
	"""Подстановки, которые делает экспорт Godot 4.4 (см. misc/dist/html в движке)."""
	cfg = '{"args":[],"canvasResizePolicy":0,"ensureCrossOriginIsolationHeaders":true,"executable":"index","experimentalVK":false,"fileSizes":{"index.pck":100,"index.wasm":200},"focusCanvas":true,"gdextensionLibs":[]}'
	return (html.replace("$GODOT_PROJECT_NAME", "Раскопки на каникулах").replace("$GODOT_HEAD_INCLUDE", "")
		.replace("$GODOT_URL", "index.js").replace("$GODOT_CONFIG", cfg).replace("$GODOT_THREADS_ENABLED", "false"))


def test_built():
	shell = ROOT / "web" / "shell.html"
	check("web/shell.html существует", shell.exists())
	html = shell.read_text(encoding="utf-8")
	check("web/shell.html собран из актуального исходника (tools/build_web_shell.py)", html == build_web_shell.build_html())
	check("в готовой оболочке не осталось {{ASSET:…}}", "{{ASSET:" not in html)
	check("оболочка небольшая (< 64 КБ)", len(html.encode("utf-8")) < 64 * 1024)
	for ph in ("$GODOT_PROJECT_NAME", "$GODOT_HEAD_INCLUDE", "$GODOT_URL", "$GODOT_CONFIG", "$GODOT_THREADS_ENABLED"):
		check("подстановка Godot " + ph, ph in html)
	check('ровно один тег <script src="$GODOT_URL"></script> (по нему работает штамп сборки)',
		html.count('<script src="$GODOT_URL"></script>') == 1)
	# Таймер «engine init timeout» считает от конца скачивания: от открытия страницы он ронял
	# игру на 99% на мобильной сети без кэша (iPhone, инкогнито, скачивание дольше 90 с).
	check("сторож запуска считает от конца скачивания, а не от открытия страницы",
		"downloadedAt" in html and "performance.now() - t0 > 90000" not in html)
	return html


def test_stamp(html):
	stamp = load_stamp()
	with tempfile.TemporaryDirectory() as tmp:
		tmp = pathlib.Path(tmp)
		(tmp / "web").mkdir()
		index = tmp / "web" / "index.html"
		index.write_text(godot_export(html), encoding="utf-8")
		info = tmp / "build_info.json"
		info.write_text(json.dumps({"build": "20990101-0000"}), encoding="utf-8")
		stamp.HTML, stamp.INFO = index, info
		stamp.main()
		out = index.read_text(encoding="utf-8")
		check("штамп: index.js получает ?v=<метка>", '<script src="index.js?v=20990101-0000"></script>' in out)
		check("штамп: подмена fetch стоит ДО index.js", out.index("window.fetch = function") < out.index('src="index.js?v='))
		check("штамп: подмена идёт и для аудио-ворклетов", "AudioWorklet.prototype.addModule" in out)
		check("штамп: version.json с меткой лёг рядом (проверка свежести страницы)",
			json.loads((index.parent / "version.json").read_text(encoding="utf-8")).get("build") == "20990101-0000")
		check("штамп: страница сверяется с version.json мимо кэша и уходит на ?b=<метка>",
			'version.json?t=' in out and 'cache: "no-store"' in out and 'searchParams.set("b"' in out)
		check("штамп: проверка свежести стоит ДО index.js", out.index("version.json?t=") < out.index('src="index.js?v='))
		check("штамп: manifest и иконки легли рядом с index.html",
			all((tmp / "web" / n).exists() for n in ["manifest.webmanifest"] + build_web_shell.PWA_FILES))
		try:
			stamp.main()
			again = False
		except SystemExit:
			again = True
		check("штамп: повторный запуск отказывается (защита от двойной подмены)", again)


def test_no_external_and_no_sw(html):
	check("нет CDN и внешних стилей/шрифтов/скриптов",
		not re.search(r'(?:src|href)="https?://', html) and not re.search(r"url\(\s*['\"]?https?://", html)
		and "fonts.googleapis" not in html and "<link rel=\"stylesheet\"" not in html)
	check("service worker не регистрируется (иначе вечный кэш старой сборки)",
		"serviceWorker.register" not in html and "installServiceWorker" not in html)


def test_mobile_contract(html):
	for label, needle in [
		("viewport-fit=cover", "viewport-fit=cover"),
		("запрет масштабирования щипком (user-scalable=no)", "user-scalable=no"),
		("высота по 100dvh", "100dvh"),
		("безопасные зоны env(safe-area-inset-*)", "env(safe-area-inset-top"),
		("touch-action: none на холсте и странице", "touch-action:none"),
		("нет вызова меню по долгому нажатию (-webkit-touch-callout)", "-webkit-touch-callout:none"),
		("нет выделения текста (user-select: none)", "user-select:none"),
		("overscroll-behavior: none (оттяжка страницы)", "overscroll-behavior:none"),
		("блок жестов iOS (gesturestart)", "gesturestart"),
		("contextmenu гасится", "'contextmenu'"),
		("плашка «поверни телефон» по media-запросу", "@media (orientation:landscape) and (pointer:coarse)"),
		("iOS: apple-mobile-web-app-capable", "apple-mobile-web-app-capable"),
		("iOS: apple-touch-icon", 'rel="apple-touch-icon"'),
		("manifest подключён", 'rel="manifest"'),
		("image-rendering: pixelated на холсте", "image-rendering:pixelated"),
		("полноэкранный режим: requestFullscreen", "requestFullscreen"),
		("звук разблокируется жестом: AudioContext", "unlockAudio"),
		("прогресс по Engine: onProgress", "onProgress"),
		("canvasResizePolicy=0 — размером холста управляет оболочка", "canvasResizePolicy: 0"),
		("WebGL2/WASM: сообщения об ошибке", "Нет графики"),
		("падение: кнопка «Перезагрузить»", "Перезагрузить"),
	]:
		check(label, needle in html)


def test_manifest_and_icons():
	m = json.loads((ROOT / "web" / "pwa" / "manifest.webmanifest").read_text(encoding="utf-8"))
	check("manifest: name и short_name", m.get("name") == "Раскопки на каникулах" and bool(m.get("short_name")))
	check("manifest: display fullscreen/standalone", m.get("display") in ("fullscreen", "standalone"))
	check("manifest: orientation portrait", m.get("orientation") == "portrait")
	check("manifest: theme_color и background_color", bool(m.get("theme_color")) and bool(m.get("background_color")))
	sizes = {}
	for icon in m.get("icons", []):
		p = ROOT / "art" / "brand" / icon["src"]
		check("manifest: иконка " + icon["src"] + " существует", p.exists())
		if p.exists():
			sizes[(icon["src"], icon.get("purpose"))] = Image.open(p).size
	check("manifest: есть 192, 512 и maskable 512",
		sizes.get(("icon-192.png", "any")) == (192, 192) and sizes.get(("icon-512.png", "any")) == (512, 512)
		and sizes.get(("icon-maskable-512.png", "maskable")) == (512, 512))
	check("apple-touch-icon 180x180", Image.open(ROOT / "art" / "brand" / "apple-touch-icon.png").size == (180, 180))
	check("favicon-32 32x32", Image.open(ROOT / "art" / "brand" / "favicon-32.png").size == (32, 32))
	check("favicon.ico на месте", (ROOT / "art" / "brand" / "favicon.ico").exists())
	check("art/brand закрыт .gdignore (Godot не тащит его в пак)", (ROOT / "art" / "brand" / ".gdignore").exists())


def test_preset():
	cfg = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
	web = cfg.split("[preset.1]")[0]
	check('пресет Web: html/custom_html_shell="res://web/shell.html"', 'html/custom_html_shell="res://web/shell.html"' in web)
	check("пресет Web: canvas_resize_policy=0", "html/canvas_resize_policy=0" in web)
	check("пресет Web: PWA-экспорт Godot выключен (он ставит service worker)", "progressive_web_app/enabled=false" in web)
	check("пресет Web: без потоков (GitHub Pages не шлёт COOP/COEP)", "variant/thread_support=false" in web)


def test_font():
	woff = ROOT / "art" / "brand" / "pixel_font.woff"
	check("шрифт art/brand/pixel_font.woff существует", woff.exists())
	try:
		from fontTools.ttLib import TTFont
	except ImportError:
		print("[SKIP] fontTools не установлен — покрытие шрифта не проверено")
		return
	cmap = TTFont(str(woff)).getBestCmap()
	need = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюяёЁ0123456789 .,!?:-%/…"
	missing = [c for c in need if ord(c) not in cmap]
	check("шрифт: вся кириллица, цифры и знаки есть" + (" (нет: %s)" % "".join(missing) if missing else ""), not missing)


if __name__ == "__main__":
	html = test_built()
	test_stamp(html)
	test_no_external_and_no_sw(html)
	test_mobile_contract(html)
	test_manifest_and_icons()
	test_preset()
	test_font()
	print("=== Итог: %d проверок, %d провалов ===" % (checks, len(failures)))
	sys.exit(1 if failures else 0)
