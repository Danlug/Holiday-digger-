class_name NewbieStreakButton
extends VBoxContainer
## Кнопка стрика новичка на главном экране — сразу под кнопкой ежедневных
## миссий (владелец 27.10: «стрик 30 дней должен быть на главном экране под
## ежедневными миссиями»). Под кнопкой — «отмечено N/30»; красный бейдж —
## отмеченные дни, чью награду ещё не забрали; пока есть что забрать, кнопка
## покачивается. Нажатие открывает экран-календарь (NewbieStreakService).
##
## Подключение — одна строка в hud.gd (NewbieStreakButton.mount). Видна, пока
## мета-слой включён и стрик не закрыт целиком (все 30 отмечены и забраны).

const SIZE := Vector2(36, 32)
const POLL_SEC := 0.5

var button: Button = null
var _count: Label = null
var _acc: float = POLL_SEC
var _claimable: int = -1
var _pulse: Tween = null
var _state_key: String = ""


static func mount(parent: Control) -> NewbieStreakButton:
	var b := NewbieStreakButton.new()
	b.name = "NewbieStreakButton"
	parent.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation", 0)
	button = UiBtn.icon_button(MetaUiKit.tex("newbie"), SIZE, UiBtn.Kind.NORMAL, 28)
	button.name = "Button"
	button.pressed.connect(_on_pressed)
	add_child(button)

	_count = MetaUiKit.label("", 9, MetaUiKit.GOLD_LIGHT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.custom_minimum_size = Vector2(SIZE.x, 0)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	visible = false
	_sync()


func _process(delta: float) -> void:
	_acc += delta
	if _acc < POLL_SEC:
		return
	_acc = 0.0
	_sync()


func _on_pressed() -> void:
	if Tip.swallowed():
		return
	var svc := NewbieStreakService.instance
	if svc != null and is_instance_valid(svc):
		svc.open()


func _sync() -> void:
	var n := NewbieStreak.claimable_count() if MetaState.is_unlocked() else 0
	var on := NewbieStreakService.instance != null and MetaState.is_unlocked() \
		and (not NewbieStreak.all_done() or n > 0)
	if visible != on:
		visible = on
	if not on:
		_set_pulse(false)
		return
	if n != _claimable:
		_claimable = n
		UiBtn.set_badge(button, n)
		_set_pulse(n > 0)
	var done := NewbieStreak.done_count()
	var total := NewbieStreak.days_total()
	var key := "%d/%d/%d/%d" % [done, total, n, NewbieStreak.today_n()]
	if key == _state_key:
		return
	_state_key = key
	_count.text = "%d/%d" % [done, total]
	var today := NewbieStreak.today_n()
	Tip.set_text(button, NewbieStreak.text("title"),
		NewbieStreak.text("menu_body") % [today, total, done] if today > 0 else NewbieStreak.text("menu_body_over") % [done, total],
		NewbieStreak.text("about"))


## Покачивание — как у кнопки ежедневных миссий: награда ждёт.
func _set_pulse(on: bool) -> void:
	if on == (_pulse != null):
		return
	if _pulse != null:
		_pulse.kill()
		_pulse = null
		button.scale = Vector2.ONE
		return
	if UiAnim.reduced():
		return
	button.pivot_offset = SIZE * 0.5
	_pulse = button.create_tween().set_loops()
	_pulse.tween_property(button, "scale", Vector2.ONE * 1.1, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse.tween_property(button, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pulse.tween_interval(0.9)
