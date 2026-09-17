#!/usr/bin/env python3
"""Сброс кэша в готовой веб-сборке: build/web/index.html.

Зачем. Имена файлов у экспорта Godot постоянные — index.js, index.wasm,
index.pck. Браузер, один раз забравший 43-мегабайтный wasm и пак, охотно
отдаёт их из кэша и после обновления раздачи: игрок открывает игру и видит
прошлую сборку, а по переписке это неотличимо от «сборку не выложили».
Заголовки на GitHub Pages нам не подчиняются, поэтому меняем то, что в
нашей власти, — сами адреса: к каждому дописывается ?v=<метка сборки>.

Движок просит wasm и пак сам, через fetch, поэтому правки тега <script>
мало: fetch подменяется рядом, до загрузки index.js. Аудио-ворклеты идут
через audioWorklet.addModule — его подменяем тем же способом.

Запуск: python3 tools/stamp_web_build.py   (после экспорта)
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = ROOT / "build" / "web" / "index.html"
INFO = ROOT / "data" / "build_info.json"

MARK = "<!-- cache-bust -->"


def main() -> None:
    if not HTML.exists():
        sys.exit(f"нет {HTML} — сначала экспорт веб-сборки, см. docs/BUILD.md")
    if not INFO.exists():
        sys.exit(f"нет {INFO} — сначала python3 tools/make_build_info.py")
    build = str(json.loads(INFO.read_text(encoding="utf-8")).get("build", "")).strip()
    if not build:
        sys.exit(f"в {INFO} пустое поле build")

    html = HTML.read_text(encoding="utf-8")
    if MARK in html:
        sys.exit("index.html уже проштампован — экспортируйте заново")

    patch = f"""{MARK}
\t\t<script>
// Сброс кэша: у экспорта Godot постоянные имена файлов, и браузер отдаёт
// прошлую сборку из кэша. Адреса получают ?v=<метка>, и старый кэш до них
// не дотягивается. Подмена стоит ДО загрузки index.js: движок просит wasm,
// пак и ворклеты сам.
(function () {{
\tconst V = "{build}";
\tconst TOUCH = /index(\\.[a-z.]+)?\\.(js|wasm|pck)(\\?|$)/;
\tfunction bust(url) {{
\t\tif (typeof url !== "string" || !TOUCH.test(url) || url.indexOf("v=" + V) !== -1) {{
\t\t\treturn url;
\t\t}}
\t\treturn url + (url.indexOf("?") === -1 ? "?" : "&") + "v=" + V;
\t}}
\tconst _fetch = window.fetch;
\twindow.fetch = function (input, init) {{
\t\ttry {{
\t\t\tif (typeof input === "string") {{
\t\t\t\tinput = bust(input);
\t\t\t}} else if (input && typeof input.url === "string") {{
\t\t\t\tconst next = bust(input.url);
\t\t\t\tif (next !== input.url) {{
\t\t\t\t\tinput = new Request(next, input);
\t\t\t\t}}
\t\t\t}}
\t\t}} catch (e) {{ /* адрес не наш — пусть идёт как есть */ }}
\t\treturn _fetch.call(this, input, init);
\t}};
\tif (window.AudioWorklet && AudioWorklet.prototype.addModule) {{
\t\tconst _add = AudioWorklet.prototype.addModule;
\t\tAudioWorklet.prototype.addModule = function (url, options) {{
\t\t\treturn _add.call(this, bust(url), options);
\t\t}};
\t}}
}}());
\t\t</script>
\t\t<script src="index.js?v={build}"></script>"""

    old = '<script src="index.js"></script>'
    if old not in html:
        sys.exit("в index.html не найден тег загрузки index.js — экспорт изменился")
    html = html.replace(old, patch, 1)
    HTML.write_text(html, encoding="utf-8")
    print(f"build/web/index.html: метка v={build}")


if __name__ == "__main__":
    main()
