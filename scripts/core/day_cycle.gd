extends Node
## DayCycle — автолоад суточного цикла (см. задание владельца про свет/небо).
##
## ЕДИНСТВЕННЫЙ источник правды о часе — GameState.game_clock_hours (тот же
## счётчик, что копит house_view.gd для "День N, HH:MM"). DayCycle НЕ ведёт
## собственных часов: hour/day каждый кадр (и сразу после set_hour())
## пересчитываются из game_clock_hours же формулой
## fmod(6.0 + game_clock_hours, 24.0) — игра стартует в 6 утра, поэтому
## сдвиг на 6 часов зашит здесь же, в одном месте, а не размазан по HUD/дому/
## этому файлу тремя разными копиями.
##
## time_scale (сценарии вроде интро деда, гоняющие 6:00→22:00 за секунды
## показа) применяется в GameState._tick_game_clock — там же, где часы и
## так тикают каждый кадр, — чтобы game_clock_hours двигался РОВНО ОДИН РАЗ
## за кадр, а не дважды (второй раз здесь), что рассинхронило бы книгу
## сна/еды/рекламных лимитов с тем, что показывает эффект неба.
##
## Все геймплейные окна темноты — общие для grade()/sky_dark()/stars_alpha():
## с 18:00 плавно (2 игровых часа) темнеет, с 20:00 до 04:00 — полная ночь,
## с 04:00 плавно (2 игровых часа) светлеет. _phase() считает эту рампу
## один раз (0 днём .. 1 ночью), остальные функции — линейная интерполяция
## по ней, числа сверены с тестами владельца (19:00 и 05:00 дают одинаковые
## 0.6/0.6/1.25 — симметрия вечера/утра не случайна, а из одной формулы).

## Плавный переход "в темноту"/"из темноты" — 2 игровых часа с каждой
## стороны (ГДД задания владельца: "с 6 вечера до 8 вечера" / "с 4 до 6
## утра").
const DUSK_START := 18.0
const NIGHT_START := 20.0
const DAWN_START := 4.0
const DAWN_END := 6.0

## Звёзды проявляются/гаснут за 10 ИГРОВЫХ минут у границ полной темноты.
const STAR_RAMP_HOURS := 10.0 / 60.0

## Дуга светил: солнце 06:00→20:00 (14 игровых часов), месяц 20:00→06:00
## (10 часов, через полночь). -0.1..1.1 — доля ширины экрана с небольшим
## запасом за края (задание: "приходит слева из-за границы экрана" и
## "пропадает справа за границей").
const SUN_START := 6.0
const SUN_END := 20.0
const MOON_START := 20.0
const MOON_SPAN := 10.0
const ARC_FROM := -0.1
const ARC_TO := 1.1

var hour: float = 6.0
var day: int = 1
var time_scale: float = 1.0


func _ready() -> void:
	_recompute()


func _process(_delta: float) -> void:
	_recompute()


func _recompute() -> void:
	var total: float = 6.0 + GameState.game_clock_hours
	hour = fmod(total, 24.0)
	if hour < 0.0:
		hour += 24.0
	day = int(floor(total / 24.0)) + 1


## Сдвигает игровые часы так, чтобы стал час h (0..24). Только ВПЕРЁД — даже
## если h "раньше" текущего часа по циферблату, это следующие сутки, а не
## отмотка назад (день не откатывается, задание владельца/тест).
func set_hour(h: float) -> void:
	var target := fmod(h, 24.0)
	if target < 0.0:
		target += 24.0
	var delta := target - hour
	if delta < 0.0:
		delta += 24.0
	GameState.game_clock_hours += delta
	_recompute()


func set_time_scale(x: float) -> void:
	time_scale = maxf(0.0, x)


## 0.0 днём (06:00–18:00) .. 1.0 глубокой ночью (20:00–04:00), с линейной
## рампой на стыках. Общая форма для grade()/sky_dark()/эффектов освещения.
func _phase() -> float:
	if hour >= NIGHT_START or hour < DAWN_START:
		return 1.0
	if hour >= DUSK_START and hour < NIGHT_START:
		return (hour - DUSK_START) / (NIGHT_START - DUSK_START)
	if hour >= DAWN_START and hour < DAWN_END:
		return 1.0 - (hour - DAWN_START) / (DAWN_END - DAWN_START)
	return 0.0


## Цветокоррекция картинок забора/горы (их рисует Backdrop, читая этот
## словарь через /root/DayCycle, см. контракт агентов): день — нейтраль,
## ночь — экспозиция и сатурация просажены на 80%, контраст поднят на 50%.
func grade() -> Dictionary:
	var t := _phase()
	return {
		"exposure": lerpf(1.0, 0.2, t),
		"saturation": lerpf(1.0, 0.2, t),
		"contrast": lerpf(1.0, 1.5, t),
	}


## Затемнение подложки синего неба: 0 днём .. 0.9 глубокой ночью (та же
## рампа 18–20/4–6, что и grade()).
func sky_dark() -> float:
	return lerpf(0.0, 0.9, _phase())


## Видимость звёзд: 0 пока не стемнело полностью, за 10 игровых минут после
## 20:00 плавно проявляются до 1, держатся всю ночь, за 10 игровых минут до
## 04:00 плавно гаснут обратно до 0.
func stars_alpha() -> float:
	if hour >= NIGHT_START:
		var since: float = hour - NIGHT_START
		return clampf(since / STAR_RAMP_HOURS, 0.0, 1.0)
	if hour < DAWN_START:
		var until: float = DAWN_START - hour
		return clampf(until / STAR_RAMP_HOURS, 0.0, 1.0)
	return 0.0


## Доля ширины экрана (-0.1..1.1, за кадром по краям) для солнца. Вне окна
## 06:00–20:00 солнца на небе нет — SkyView такое значение не рисует.
func sun_t() -> float:
	if hour < SUN_START or hour > SUN_END:
		return -1.0
	return lerpf(ARC_FROM, ARC_TO, (hour - SUN_START) / (SUN_END - SUN_START))


## То же самое для месяца: дуга 20:00 -> 06:00 через полночь.
func moon_t() -> float:
	if hour > SUN_START and hour < MOON_START:
		return -1.0
	var elapsed: float = fmod(hour - MOON_START + 24.0, 24.0)
	return lerpf(ARC_FROM, ARC_TO, elapsed / MOON_SPAN)
