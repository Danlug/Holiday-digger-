#!/usr/bin/env bash
# Бот-игрок на настоящей игре (tests/bot_play.gd): онбординг, шахта, дом, покупки, сюжет —
# с телеметрией и детекторами. Одна команда, перезапускать после слияний веток.
#
#   tools/bot_play.sh [сид] [игровых_минут] [характер]     # по умолчанию 20260101 60 cautious
#   tools/bot_play.sh 7 240 greedy
#   tools/bot_play.sh all 120                               # 3 характера × 2 сида параллельно
#   SHOTS=1 tools/bot_play.sh 7 30 hasty                    # с настоящим рендером и снимками (xvfb)
#   OUT=/каталог JOBS=3 WALL=1800 tools/bot_play.sh ...
#
# Характеры: cautious (осторожный), greedy (жадный), hasty (торопливый).
# Результат: build/bot/<метка>/ — telemetry.json, log.txt, summary.txt (и shots/ при SHOTS=1);
# для «all» — ещё общий build/bot/<метка>/ALL.txt. Код возврата 0 — без находок P0.
# Время: --fixed-fps 31 — кадр = 1/31 игровой секунды, кадры идут так быстро, как тянет
# процессор (headless ×15–25 к реальному); под рендером — в темпе отрисовки.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SEED="${1:-20260101}"
MIN="${2:-60}"
CHAR="${3:-cautious}"
SHOTS="${SHOTS:-0}"
WALL="${WALL:-2400}"
JOBS="${JOBS:-3}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BASE="${OUT:-build/bot/$STAMP}"
mkdir -p "$BASE"

# Новые class_name видны после переимпорта (как в run_tests.sh).
CACHE=.godot/global_script_class_cache.cfg
if [ ! -d .godot/imported ] || [ ! -f "$CACHE" ] || \
	[ -n "$(find scripts tests tools -name '*.gd' -newer "$CACHE" 2>/dev/null | head -1)" ]; then
	echo "[bot_play] импорт проекта…"
	"$GODOT" --headless --path . --import >/dev/null 2>&1
fi

run_one() {
	local seed="$1" min="$2" char="$3" out="$4"
	mkdir -p "$out"
	out="$(realpath "$out")"
	export XDG_DATA_HOME="$out/xdg"
	mkdir -p "$XDG_DATA_HOME"
	local extra=()
	local runner=()
	if [ "${SHOTS}" = 1 ]; then
		extra=(--rendering-driver opengl3 --resolution 448x960)
		runner=(xvfb-run -a -s "-screen 0 1280x1024x24")
	else
		extra=(--headless)
	fi
	local args=(--seed="$seed" --minutes="$min" --char="$char" --out="$out" --wall="$WALL")
	[ -n "${TRACE:-}" ] && args+=(--trace="$TRACE")
	[ "${SHOTS}" = 1 ] && args+=(--shots)
	timeout $(( WALL + 120 )) "${runner[@]}" "$GODOT" "${extra[@]}" --fixed-fps 31 --path . \
		res://tests/bot_play.tscn -- "${args[@]}" >"$out/log.txt" 2>&1
	echo $? >"$out/exit_code"
	python3 tools/bot_report.py "$out" >/dev/null 2>&1 || echo "bot_report.py упал на $out" >"$out/summary.txt"
}
export -f run_one
export GODOT SHOTS WALL

if [ "$SEED" = all ]; then
	jobs=()
	for c in cautious greedy hasty; do
		for s in 7 424242; do
			jobs+=("$s $MIN $c $BASE/s${s}_$c")
		done
	done
	printf '%s\n' "${jobs[@]}" | xargs -P "$JOBS" -L 1 bash -c 'run_one "$@"' _
	: >"$BASE/ALL.txt"
	code=0
	for d in "$BASE"/s*_*; do
		echo "===== $(basename "$d") =====" >>"$BASE/ALL.txt"
		cat "$d/summary.txt" >>"$BASE/ALL.txt" 2>/dev/null
		echo >>"$BASE/ALL.txt"
		[ "$(cat "$d/exit_code" 2>/dev/null || echo 99)" = 0 ] || code=1
	done
	python3 tools/bot_report.py --merge "$BASE" >>"$BASE/ALL.txt" 2>/dev/null
	cat "$BASE/ALL.txt"
	echo "итоги: $BASE"
	exit $code
fi

DIR="$BASE/s${SEED}_${CHAR}"
run_one "$SEED" "$MIN" "$CHAR" "$DIR"
cat "$DIR/summary.txt"
echo "каталог: $DIR"
[ "$(cat "$DIR/exit_code" 2>/dev/null || echo 99)" = 0 ]
