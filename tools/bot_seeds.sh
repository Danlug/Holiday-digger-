#!/usr/bin/env bash
# Гоняет бота онбординга на нескольких сидах мира и скоростях — ловит «плавающие»
# поломки, которые на одном сиде не видны (камень на пути, самородок у края).
#
#   tools/bot_seeds.sh                    # сиды 1 777 424242 20260101, ×4
#   tools/bot_seeds.sh 5 6 7              # свои сиды
#   SCALE=3 tools/bot_seeds.sh            # другая скорость игрового времени
#
# Каждый прогон — отдельный процесс и отдельный XDG_DATA_HOME (чистый сейв).
# Код возврата 0 — все зелёные. Смотрим ИМЕННО на код процесса: порча кучи при
# выходе движка (134) строка «Итог» не покажет.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SCALE="${SCALE:-4}"
SEEDS=("$@")
[ ${#SEEDS[@]} -eq 0 ] && SEEDS=(1 777 424242 20260101)
OUT="$(mktemp -d)"

run_one() {
	local seed="$1" out="$2"
	export XDG_DATA_HOME="$out/xdg_$seed"
	timeout 300 "$GODOT" --headless --path . res://tests/test_bot_onboarding.tscn -- --inproc --seed="$seed" --scale="$SCALE" >"$out/seed_$seed.log" 2>&1
	echo $? >"$out/seed_$seed.code"
}
export -f run_one
export GODOT SCALE

printf '%s\n' "${SEEDS[@]}" | xargs -P 4 -I{} bash -c 'run_one "$@"' _ {} "$OUT"

fail=0
for s in "${SEEDS[@]}"; do
	code="$(cat "$OUT/seed_$s.code" 2>/dev/null || echo 99)"
	summary="$(grep -E 'Итог:' "$OUT/seed_$s.log" | tail -1)"
	errs="$(grep -cE 'SCRIPT ERROR|Parse Error' "$OUT/seed_$s.log")"
	if [ "$code" = 0 ] && [ "$errs" = 0 ]; then
		printf 'OK    сид %-10s %s\n' "$s" "$summary"
	else
		printf 'FAIL  сид %-10s код=%s ошибок скрипта=%s %s\n' "$s" "$code" "$errs" "$summary"
		grep -E '^\[FAIL\]|SCRIPT ERROR' -A8 "$OUT/seed_$s.log" | head -24 | sed 's/^/        /'
		fail=1
	fi
done
echo "логи: $OUT"
exit $fail
