class_name Settings
extends RefCounted
## Настройки игрока: звук/музыка (громкость + мьют), вибро, схема управления,
## видимость радиуса обзора, «меньше движения», язык. Отдельный файл user://settings.json —
## тот же приём, что у StoryState/RecordsStore: своя маленькая система, не
## часть общего сейва (настройки не игровой прогресс, «Сброс» их не трогает
## и не обязан — см. hud.gd:_on_reset_pressed).
##
## Звуковых ресурсов (эффектов/музыки) в игре пока нет вовсе — но шины и
## регуляторы делаем настоящими, не заглушкой: когда звук появится, ему
## достаточно будет играть через шину BUS_SFX/BUS_MUSIC, а громкость и
## мьют уже управляемы и сохраняются.

const PATH := "user://settings.json"
const SCHEMA_VERSION := 1

const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"

## "Пока только русский, дальше — после разрешения владельца — будет
## (английский, украинский, испанский, китайский, индийский)" — задание
## владельца, 2026-09-21. Список уже содержит будущие языки с
## available=false, чтобы панель настроек рисовала их сразу серыми, а не
## переписывалась заново, когда они появятся.
const LANGUAGES := [
	{"code": "ru", "name": "Русский", "available": true},
	{"code": "en", "name": "English", "available": false},
	{"code": "uk", "name": "Українська", "available": false},
	{"code": "es", "name": "Español", "available": false},
	{"code": "zh", "name": "中文", "available": false},
	{"code": "hi", "name": "हिन्दी", "available": false},
]

static var sound_volume: float = 1.0
static var sound_muted: bool = false
static var music_volume: float = 1.0
static var music_muted: bool = false
## "stick" | "hold" | "arrows" — те же три режима, что hud.gd:MODES.
static var control_mode: String = "stick"
static var show_vision_radius: bool = true
static var language: String = "ru"
## Вибро-отклик (Haptics.enabled). Включено по умолчанию: на ПК и в вебе
## без поддержки вибро всё равно молчит.
static var haptics_enabled: bool = true
## «Меньше движения» — гасит лишние твины интерфейса (всплытие шторок, пульс,
## накрутку чисел). Первое значение берём у системы, как prefers-reduced-motion
## в вебе; дальше решает игрок.
static var reduce_motion: bool = false


## Заводит звуковые шины, если их ещё нет (первый запуск процесса — шины
## AudioServer не переживают перезапуск игры, поэтому вызывается из
## main.gd при каждом старте, идемпотентно: находит уже созданные по имени
## и не плодит дубликаты).
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_SFX)
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_MUSIC)


## Переносит текущие значения громкости/мьюта на реальные шины. Зовётся
## после load_from_disk() и после каждого изменения регулятора в панели
## настроек.
static func apply_audio() -> void:
	_apply_bus(BUS_SFX, sound_volume, sound_muted)
	_apply_bus(BUS_MUSIC, music_volume, music_muted)


static func _apply_bus(bus_name: String, volume: float, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# 0.0 через linear_to_db() дал бы -INF — AudioServer его и так молча
	# сводит к полной тишине, но -60 дБ тем же результатом на слух и без
	# сюрприза бесконечности в сохранённом файле/логах.
	AudioServer.set_bus_volume_db(idx, linear_to_db(volume) if volume > 0.001 else -60.0)
	AudioServer.set_bus_mute(idx, muted)


static func set_sound_volume(v: float) -> void:
	sound_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save()


static func set_sound_muted(m: bool) -> void:
	sound_muted = m
	apply_audio()
	save()


static func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save()


static func set_music_muted(m: bool) -> void:
	music_muted = m
	apply_audio()
	save()


static func set_control_mode(m: String) -> void:
	control_mode = m
	save()


static func set_show_vision_radius(v: bool) -> void:
	show_vision_radius = v
	save()


## Язык — пока только "ru" переключаем по-настоящему (единственный
## available: true в LANGUAGES). Остальные коды тоже принимаются (на
## будущее, когда появятся переводы), но интерфейс панели их не предлагает.
static func set_language(code: String) -> void:
	language = code
	save()


static func set_haptics_enabled(v: bool) -> void:
	haptics_enabled = v
	Haptics.enabled = v
	save()


static func set_reduce_motion(v: bool) -> void:
	reduce_motion = v
	save()


## Системное «меньше движения»: есть только в вебе (matchMedia); в остальных
## сборках остаётся false, пока игрок сам не включит в настройках.
static func detect_system_reduce_motion() -> bool:
	if not OS.has_feature("web"):
		return false
	var v = JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches")
	return bool(v)


static func save() -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Settings: не удалось открыть %s на запись" % PATH)
		return false
	f.store_string(JSON.stringify({
		"version": SCHEMA_VERSION,
		"sound_volume": sound_volume,
		"sound_muted": sound_muted,
		"music_volume": music_volume,
		"music_muted": music_muted,
		"control_mode": control_mode,
		"show_vision_radius": show_vision_radius,
		"language": language,
		"haptics_enabled": haptics_enabled,
		"reduce_motion": reduce_motion,
	}, "\t"))
	f.close()
	return true


static func load_from_disk() -> bool:
	if not FileAccess.file_exists(PATH):
		# Первый запуск: «меньше движения» берём у системы, вибро — включено.
		reduce_motion = detect_system_reduce_motion()
		Haptics.enabled = haptics_enabled
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("Settings: %s повреждён — настройки по умолчанию" % PATH)
		return false
	sound_volume = clampf(float(raw.get("sound_volume", 1.0)), 0.0, 1.0)
	sound_muted = bool(raw.get("sound_muted", false))
	music_volume = clampf(float(raw.get("music_volume", 1.0)), 0.0, 1.0)
	music_muted = bool(raw.get("music_muted", false))
	control_mode = String(raw.get("control_mode", "stick"))
	show_vision_radius = bool(raw.get("show_vision_radius", true))
	language = String(raw.get("language", "ru"))
	haptics_enabled = bool(raw.get("haptics_enabled", true))
	reduce_motion = bool(raw.get("reduce_motion", detect_system_reduce_motion()))
	Haptics.enabled = haptics_enabled
	return true
