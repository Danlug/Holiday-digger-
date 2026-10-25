#!/usr/bin/env bash
# Ночной прогон: пять ботов-стратегий играют параллельно, пока не кончится заданное настенное время.
#
#   tools/bot_night.sh <часов> [стратегии…]          # по умолчанию все пять
#   tools/bot_night.sh 8
#   tools/bot_night.sh 2 deep fighter
#   JOBS=5 SHOTS=1 SHOT_POINTS=2 SESSION=60 OUT=/каталог tools/bot_night.sh 8
#
# Стратегии (tests/bot_play.gd → GOALS): deep — как можно глубже; achiever — открыть больше
# достижений; tycoon — максимум денег; collector — музей, артефакты, тайники, мастерство;
# fighter — бой на 4000+, выживание. У каждой свой сид, характер и порядок прокачки.
#
# Каждый бот: headless, --fixed-fps 31, «закрыл игру — вернулся завтра» каждые SESSION игровых
# минут (сейв → загрузка, мета-сутки +1), телеметрия на диск каждые 10 игровых минут (обрыв ночи
# не теряет итог), копия сейва каждые CP игровых минут. Когда время вышло — у каждого summary.txt
# и telemetry.json; затем (SHOTS=1) настоящим рендером под xvfb снимаются SHOT_POINTS сейвов-копий
# каждого бота (по SHOT_MIN игровых минут), и общий отчёт: <каталог>/NIGHT.md и NIGHT.txt
# (tools/bot_report.py --night). Время стены: часы + ~5 мин на каждую точку снимков (параллельно).
set -u
cd "$(dirname "$0")/.."
HOURS="${1:-8}"
shift || true
STRATS=("$@")
[ ${#STRATS[@]} -eq 0 ] && STRATS=(deep achiever tycoon collector fighter)
JOBS="${JOBS:-5}"
SESSION="${SESSION:-60}"
CP="${CP:-120}"
SHOTS_ON="${SHOTS:-1}"
SHOT_POINTS="${SHOT_POINTS:-2}"
SHOT_MIN="${SHOT_MIN:-3}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BASE="${OUT:-build/bot/night-$STAMP}"
mkdir -p "$BASE"
[ -f build/bot/.gdignore ] || { mkdir -p build/bot && : >build/bot/.gdignore; }
: >"$BASE/.gdignore"
BASE="$(realpath "$BASE")"
WALL=$(awk "BEGIN{print int($HOURS*3600)}")

declare -A SEEDS=([deep]=20260101 [achiever]=7 [tycoon]=424242 [collector]=31337 [fighter]=99)

# Импорт, если есть новые скрипты (как в run_tests.sh).
CACHE=.godot/global_script_class_cache.cfg
if [ ! -d .godot/imported ] || [ ! -f "$CACHE" ] || \
	[ -n "$(find scripts tests tools -name '*.gd' -newer "$CACHE" 2>/dev/null | head -1)" ]; then
	echo "[bot_night] импорт проекта…"
	godot --headless --path . --import >/dev/null 2>&1
fi

echo "[bot_night] $(date -u +%H:%M) старт: ${STRATS[*]} на $HOURS ч, каталог $BASE"
for g in "${STRATS[@]}"; do
	seed="${SEEDS[$g]:-7}"
	(
		OUT="$BASE/$g" WALL="$WALL" SESSION="$SESSION" SHOTS=0 FLUSH=10 CP="$CP" \
			tools/bot_play.sh "$seed" 99999 "$g" >/dev/null 2>&1
	) &
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do sleep 5; done
done
wait
echo "[bot_night] $(date -u +%H:%M) игра закончилась"

# Снимки настоящим рендером с копий сейва (ровно по SHOT_POINTS на бота, равномерно по ночи).
if [ "$SHOTS_ON" = 1 ] && command -v xvfb-run >/dev/null; then
	for g in "${STRATS[@]}"; do
		run_dir="$(ls -d "$BASE/$g"/s*_* 2>/dev/null | head -1)"
		[ -n "$run_dir" ] || continue
		mapfile -t cps < <(ls -d "$run_dir"/cp_* 2>/dev/null | sort)
		n=${#cps[@]}
		[ "$n" -eq 0 ] && continue
		for i in $(seq 1 "$SHOT_POINTS"); do
			idx=$(( n * i / (SHOT_POINTS + 1) ))
			[ "$idx" -ge "$n" ] && idx=$((n - 1))
			cp="${cps[$idx]}"
			(
				LP_NUM_THREADS=1 RESUME="$cp" SHOTS=1 WALL=1200 OUT="$run_dir/shots_$(basename "$cp")" \
					tools/bot_play.sh "${SEEDS[$g]:-7}" "$SHOT_MIN" "$g" >/dev/null 2>&1
			) &
			while [ "$(jobs -rp | wc -l)" -ge 4 ]; do sleep 5; done
		done
	done
	wait
	echo "[bot_night] $(date -u +%H:%M) снимки готовы"
fi

python3 tools/bot_report.py --night "$BASE" | tee "$BASE/NIGHT.txt"
echo "[bot_night] отчёт: $BASE/NIGHT.md"
