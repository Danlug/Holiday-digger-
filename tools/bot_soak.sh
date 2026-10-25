#!/usr/bin/env bash
# Бот после онбординга живёт N игровых минут на живой сцене: копает шахту, поднимается на
# ранце, продаёт, покупает ступени, ест и спит, закрывает всплывающие окна.
#
#   tools/bot_soak.sh            # 30 игровых минут, ускорение ×5 (~6 минут настенных)
#   tools/bot_soak.sh 10         # 10 минут
#   SEED=777 SCALE=4 tools/bot_soak.sh 30
#
# Дольше ~3 игровых минут не входит в run_tests.sh (там лимит 240 с на тест), поэтому отдельно.
# Свой XDG_DATA_HOME на прогон: сейв начинается с чистого и ничего чужого не трогает.
# Код возврата 0 — зелёное; смотрим на код процесса, не только на строку «Итог».
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MIN="${1:-30}"
SEED="${SEED:-20260101}"
SCALE="${SCALE:-5}"
export XDG_DATA_HOME="$(mktemp -d)"
LOG="$(mktemp)"
timeout $(( (MIN * 60 / ${SCALE%.*}) * 3 + 300 )) "$GODOT" --headless --path . res://tests/test_bot_onboarding.tscn -- \
	--inproc --soak="$MIN" --seed="$SEED" --scale="$SCALE" >"$LOG" 2>&1
code=$?
grep -E '^\[FAIL\]|SCRIPT ERROR|итог:|^  (куплено|окно)|Итог:' -A12 "$LOG" | head -80
errs="$(grep -cE 'SCRIPT ERROR|Parse Error' "$LOG")"
echo "код=$code, ошибок скрипта=$errs, лог: $LOG"
[ "$code" = 0 ] && [ "$errs" = 0 ]
