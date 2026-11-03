#!/usr/bin/env bash
# iOS-экспорт одной командой (docs/BUILD.md, раздел «Сборка iOS»; подача — docs/APPSTORE.md).
#
#   tools/export_ios.sh            # build/ios: Xcode-проект (Linux/Windows) или сразу .ipa (macOS с Xcode)
#   GODOT=/путь/к/godot tools/export_ios.sh
#
# На Linux Godot 4.4 честно доходит до конца: распаковывает шаблон ios.zip, кладёт
# pck, иконки, PrivacyInfo.xcprivacy и генерирует Raskopki.xcodeproj; собрать и
# подписать .ipa может только Xcode на macOS — там та же команда делает и это.
# НЕ коммитит и НЕ выкладывает. Версия в паке — та, что лежит в data/build_info.json
# (штамп последней веб-сборки); отдельный штамп для iOS не пишем.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=build/ios

# Пустой (но заданный) XDG_DATA_HOME уводит Godot от ~/.local/share, где лежат
# шаблоны экспорта, и экспорт падает «configuration errors» без текста.
[ -n "${XDG_DATA_HOME:-}" ] || unset XDG_DATA_HOME

command -v "$GODOT" >/dev/null || { echo "export_ios: нет godot ($GODOT)" >&2; exit 2; }
TPL="${HOME}/.local/share/godot/export_templates/4.4.stable/ios.zip"
[ -f "$TPL" ] || echo "export_ios: предупреждение: нет $TPL — экспорт откажет (установи шаблоны 4.4.stable)" >&2

if [ ! -d .godot/imported ]; then
	echo "[export_ios] импорт проекта…"
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

rm -rf "$OUT"
mkdir -p "$OUT"
touch build/.gdignore   # иначе Godot реимпортирует свой же экспорт

log="$(mktemp)"
if ! "$GODOT" --headless --path . --export-release "iOS" "$OUT/Raskopki.ipa" >"$log" 2>&1; then
	echo "export_ios: экспорт упал, хвост лога:" >&2
	tail -30 "$log" >&2
	exit 1
fi
if grep -qE 'SCRIPT ERROR|Parse Error|ERROR: .*export' "$log"; then
	echo "export_ios: в логе экспорта есть ошибки:" >&2
	grep -E 'SCRIPT ERROR|Parse Error|ERROR:' "$log" | head -20 >&2
	exit 1
fi

if [ -s "$OUT/Raskopki.ipa" ]; then
	echo "[export_ios] готов пакет: $OUT/Raskopki.ipa"
elif [ -d "$OUT/Raskopki.xcodeproj" ]; then
	echo "[export_ios] Xcode-проект: $OUT/Raskopki.xcodeproj (pck: $(du -h "$OUT/Raskopki.pck" | cut -f1))"
	echo "[export_ios] дальше — на macOS: open $OUT/Raskopki.xcodeproj → Signing → Product → Archive (docs/APPSTORE.md)"
else
	echo "export_ios: нет ни .ipa, ни Xcode-проекта в $OUT" >&2
	tail -20 "$log" >&2
	exit 1
fi
rm -f "$log"
