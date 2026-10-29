class_name Haptics
extends RefCounted
## Haptics — вибро-отклик (телефон; на ПК и в вебе без поддержки — тишина).
## Выключатель — Haptics.enabled (его привязывает экран настроек).
## В iOS Safari (веб-сборка на iPhone) вибро нет вовсе: вибро — только добавка к звуку
## и картинке, никогда не единственный отклик.

static var enabled: bool = true


static func tap() -> void:
	_pulse(12)


static func thud() -> void:
	_pulse(35)


static func buzz(ms: int = 60) -> void:
	_pulse(ms)


static func _pulse(ms: int) -> void:
	if enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
