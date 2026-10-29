#!/usr/bin/env bash
# Единый запуск всех автотестов (headless). Код возврата 0 — всё зелёное.
#
#   tools/run_tests.sh              # все тесты, по 4 параллельно
#   tools/run_tests.sh foundation   # только тесты, в имени которых есть "foundation"
#   JOBS=2 tools/run_tests.sh
#
# Тесты-скриншоты (test_screenshot_*, test_qa_screens, test_sky_screenshot_rig)
# сюда не входят: им нужен настоящий рендер (xvfb-run, см. шапку test_qa_screens).
# test_<имя>.tscn запускается как сцена; test_<имя>.gd без соседней .tscn — как
# --script (автозагрузок в нём нет).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
JOBS="${JOBS:-4}"
FILTER="${1:-}"

# Новые class_name видны только после переимпорта (кэш глобальных классов):
# импортируем при первом запуске в этой копии и когда какой-то .gd новее кэша.
CACHE=.godot/global_script_class_cache.cfg
if [ ! -d .godot/imported ] || [ ! -f "$CACHE" ] || \
	[ -n "$(find scripts tests tools -name '*.gd' -newer "$CACHE" 2>/dev/null | head -1)" ]; then
	echo "[run_tests] импорт проекта (первый запуск или новые скрипты)…"
	"$GODOT" --headless --path . --import >/dev/null 2>&1
fi

OUT="$(mktemp -d)"
list=()
for f in tests/test_*.tscn; do
	n="$(basename "$f" .tscn)"
	case "$n" in *screenshot*|test_qa_screens) continue ;; esac
	[ -n "$FILTER" ] && [[ "$n" != *"$FILTER"* ]] && continue
	list+=("scene:$n")
done
for f in tests/test_*.gd; do
	n="$(basename "$f" .gd)"
	[ -f "tests/$n.tscn" ] && continue
	case "$n" in *screenshot*|test_qa_screens) continue ;; esac
	[ -n "$FILTER" ] && [[ "$n" != *"$FILTER"* ]] && continue
	list+=("script:$n")
done

run_one() {
	local kind="${1%%:*}" n="${1#*:}"
	local log="$2/$n.log"
	# user:// (save.json, settings.json) общий на всю машину: у каждого теста свой каталог данных,
	# иначе параллельные тесты и соседние worktree-ветки ломают друг другу сейв.
	export XDG_DATA_HOME="$2/xdg_$n"
	export APPDATA="$2/xdg_$n"   # то же для Windows: там Godot кладёт user:// в %APPDATA%
	if [ "$kind" = scene ]; then
		timeout 240 "$GODOT" --headless --path . "res://tests/$n.tscn" >"$log" 2>&1
	else
		timeout 240 "$GODOT" --headless --path . --script "res://tests/$n.gd" >"$log" 2>&1
	fi
	echo $? >"$2/$n.code"
}
export -f run_one
export GODOT

printf '%s\n' "${list[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} "$OUT"

fail=0
for item in "${list[@]}"; do
	n="${item#*:}"
	code="$(cat "$OUT/$n.code" 2>/dev/null || echo 99)"
	summary="$(grep -E 'Итог:' "$OUT/$n.log" | tail -1)"
	if [ "$code" = 0 ]; then
		printf 'OK    %-34s %s\n' "$n" "${summary:-(без итоговой строки)}"
	else
		printf 'FAIL  %-34s exit=%s %s\n' "$n" "$code" "$summary"
		grep -E '^\[FAIL\]|SCRIPT ERROR|Parse Error' "$OUT/$n.log" | head -8 | sed 's/^/        /'
		fail=1
	fi
done
echo "логи: $OUT"
exit $fail
