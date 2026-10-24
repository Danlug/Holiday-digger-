class_name DailyTasksButton
extends VBoxContainer
## Кнопка ежедневных заданий прямо на экране игры (заказ владельца: «добавь на
## экране кнопку ежедневных заданий»). Стоит в левом столбике HUD под героем и
## кнопкой сюжетного задания — там же, где в мобильных играх живёт «квестовая»
## колонка: не перекрывает кошелёк, глубину, джойстик и стрелки, видна и в шахте,
## и на поверхности. Под кнопкой — полоска дня из сегментов (по одному на
## задание: золото — в процессе, зелёный — выполнено), на кнопке — красный бейдж
## «сколько готово забрать»; пока есть что забрать, кнопка покачивается.
## Новый набор дня, который ещё не открывали, отмечен звёздочкой.
##
## Подключение — одна строка в hud.gd (DailyTasksButton.mount). Состояние читает
## из MetaState сама (опрос раз в 0.4 с — пять чисел), окно открывает через
## MetaService. До конца онбординга (мета-слой выключен) кнопки нет.

const SIZE := Vector2(36, 32)
const POLL_SEC := 0.4
const BAR_H := 5.0

var button: Button = null
var _bar: Control = null
var _new_mark: TextureRect = null
var _acc: float = POLL_SEC
var _claimable: int = -1
var _pulse: Tween = null
var _state_key: String = ""


static func mount(parent: Control) -> DailyTasksButton:
	var b := DailyTasksButton.new()
	b.name = "DailyTasksButton"
	parent.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation", 2)
	button = UiBtn.icon_button(MetaUiKit.tex("tasks"), SIZE, UiBtn.Kind.NORMAL, 28)
	button.name = "Button"
	button.pressed.connect(_on_pressed)
	Tip.bind(button, "Ежедневные задания")
	add_child(button)

	_new_mark = MetaUiKit.icon_rect(MetaUiKit.tex("star"), 12)
	_new_mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_new_mark.position = Vector2(-4, -4)
	_new_mark.visible = false
	button.add_child(_new_mark)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(SIZE.x, BAR_H)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
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
	var svc := MetaService.instance
	if svc != null:
		svc.open_tasks()


## Сверить с состоянием: видимость, бейдж, полоска, «новое», покачивание.
func _sync() -> void:
	var on := MetaService.instance != null and MetaState.is_unlocked() and not QuestEngine.daily().is_empty()
	if visible != on:
		visible = on
	if not on:
		_set_pulse(false)
		return
	var n := QuestEngine.daily_claimable_count()
	if n != _claimable:
		if n > _claimable and _claimable >= 0:
			UiAnim.pulse(button, 0.3, 0.3)   # звук закрытия задания играет тост мета-слоя
		_claimable = n
		UiBtn.set_badge(button, n)
		_set_pulse(n > 0)
	_new_mark.visible = n == 0 and QuestEngine.is_new_today()
	var key := _key()
	if key != _state_key:
		_state_key = key
		_bar.queue_redraw()
		Tip.set_text(button, "Ежедневные задания", "Выполнено: %d из %d" % [QuestEngine.daily_done_count(), QuestEngine.daily().size()],
			"Готово забрать: %d" % n if n > 0 else "")


func _key() -> String:
	var parts: PackedStringArray = []
	for q in QuestEngine.daily():
		parts.append("%d/%d/%s" % [int(q["progress"]), int(q["target"]), str(q["claimed"])])
	return ",".join(parts)


## Сегмент на задание: тёмная канавка, золотая доля прогресса, зелёный — готово.
func _draw_bar() -> void:
	var ds := QuestEngine.daily()
	if ds.is_empty():
		return
	var w := _bar.size.x
	var gap := 1.0
	var seg := (w - gap * float(ds.size() - 1)) / float(ds.size())
	_bar.draw_rect(Rect2(Vector2(-1, -1), Vector2(w + 2, BAR_H + 2)), Color8(0x1A, 0x10, 0x0C))
	for i in range(ds.size()):
		var q: Dictionary = ds[i]
		var x := float(i) * (seg + gap)
		var r := Rect2(x, 0, seg, BAR_H)
		_bar.draw_rect(r, Color(0.16, 0.13, 0.10))
		var f := clampf(float(q["progress"]) / float(maxi(1, int(q["target"]))), 0.0, 1.0)
		if f > 0.0:
			var col := MetaUiKit.GREEN if f >= 1.0 else MetaUiKit.GOLD
			_bar.draw_rect(Rect2(x, 0, seg * f, BAR_H), col)
			_bar.draw_rect(Rect2(x, 0, seg * f, 1), col.lightened(0.35))


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
