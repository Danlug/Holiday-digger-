#!/usr/bin/env bash
# Веб-сборка одной командой: воспроизводит docs/BUILD.md («Сборка веб-версии»).
# НЕ коммитит и НЕ выкладывает — только собирает build/web.
#
#   tools/build_web.sh                  # метка → экспорт → штамп кэша → отчёт о размерах
#   KEEP_BUILD_INFO=0 tools/build_web.sh  # после сборки вернуть data/build_info.json как был в git
#   GODOT=/путь/к/godot tools/build_web.sh
#
# data/build_info.json — отслеживаемый файл; метка попадает в пак, поэтому её
# пишем ДО экспорта. Для проверочных сборок (не для выкладки) ставь
# KEEP_BUILD_INFO=0: рабочее дерево останется чистым.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=build/web
INFO=data/build_info.json

command -v "$GODOT" >/dev/null || { echo "build_web: нет godot ($GODOT)" >&2; exit 2; }
TPL="${HOME}/.local/share/godot/export_templates/4.4.stable/web_nothreads_release.zip"
[ -f "$TPL" ] || echo "build_web: предупреждение: нет $TPL (экспорт, скорее всего, упадёт; см. docs/BUILD.md)" >&2

# Новые class_name видны экспорту только после импорта.
if [ ! -d .godot/imported ]; then
	echo "[build_web] импорт проекта…"
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

backup=""
if [ "${KEEP_BUILD_INFO:-1}" = 0 ] && [ -f "$INFO" ]; then
	backup="$(mktemp)"
	cp "$INFO" "$backup"
fi

# Каталог чистим целиком: иначе в раздачу уходит мусор прошлой сборки, а
# штамп кэша отказывается работать на уже проштампованном index.html.
rm -rf "$OUT"
mkdir -p "$OUT"
touch build/.gdignore   # иначе Godot реимпортирует свой же экспорт и пакует его в pck

python3 tools/make_build_info.py
log="$(mktemp)"
if ! "$GODOT" --headless --path . --export-release "Web" "$OUT/index.html" >"$log" 2>&1; then
	echo "build_web: экспорт упал, хвост лога:" >&2
	tail -30 "$log" >&2
	[ -n "$backup" ] && cp "$backup" "$INFO"
	exit 1
fi
# Godot может вернуть 0 при ошибках скриптов в проекте — страхуемся по логу.
if grep -qE 'SCRIPT ERROR|Parse Error|ERROR: .*export' "$log"; then
	echo "build_web: в логе экспорта есть ошибки:" >&2
	grep -E 'SCRIPT ERROR|Parse Error|ERROR:' "$log" | head -20 >&2
	[ -n "$backup" ] && cp "$backup" "$INFO"
	exit 1
fi
for f in index.html index.js index.wasm index.pck; do
	[ -s "$OUT/$f" ] || { echo "build_web: нет $OUT/$f после экспорта" >&2; exit 1; }
done
python3 tools/stamp_web_build.py

[ -n "$backup" ] && { cp "$backup" "$INFO"; rm -f "$backup"; }

echo "--- build/web ---"
ls -l "$OUT" | awk 'NR>1 {printf "%10d  %s\n", $5, $9}'
du -sh "$OUT" | awk '{print "итого: " $1}'
gzip_total=0
for f in index.wasm index.pck index.js; do
	s=$(gzip -6 -c "$OUT/$f" | wc -c)
	gzip_total=$((gzip_total + s))
	printf '  gzip %-11s %10d\n' "$f" "$s"
done
echo "  gzip итого (то, что реально качает игрок при сжатии): $gzip_total"
echo "OK: $OUT/index.html"
