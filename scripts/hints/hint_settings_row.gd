class_name HintSettingsRow
extends RefCounted
## Строка шторки настроек «подсказки»: лампочка — режим «не мешать» (Settings.hints_enabled),
## кружок-стрелка — «показать подсказки заново» (сбрасывает GameState.ext["hints"]).
## Только значки; слова — в Tip. Внешний вид строки — как у остальных строк SettingsSheet.

var toggle: Button
var replay: Button


static func build(body: Control) -> HintSettingsRow:
	var row := HintSettingsRow.new()
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SettingsSheet.ROW_BG
	sb.border_color = Color8(0x3A, 0x2E, 0x22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	body.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)

	row.toggle = UiBtn.icon_button(HintArt.tex("bulb_on"), Vector2(0, 32))
	row.toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.toggle.pressed.connect(row._on_toggle_pressed)
	h.add_child(row.toggle)

	row.replay = UiBtn.icon_button(HintArt.tex("replay"), Vector2(0, 32))
	row.replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tip.bind(row.replay, "Показать подсказки заново", "Все подсказки и метки «new» появятся снова")
	row.replay.pressed.connect(row._on_replay_pressed)
	h.add_child(row.replay)
	row.refresh()
	return row


func refresh() -> void:
	var on := Settings.hints_enabled
	toggle.icon = HintArt.tex("bulb_on" if on else "bulb_off")
	UiBtn.set_kind(toggle, UiBtn.Kind.ACCENT if on else UiBtn.Kind.NORMAL)
	toggle.modulate = Color(1, 1, 1, 1.0 if on else 0.55)
	Tip.bind(toggle, "Подсказки", "Включены: подскажу, где что нажать" if on else "Выключены: не мешаю")


func _on_toggle_pressed() -> void:
	if Tip.swallowed():
		return
	Settings.set_hints_enabled(not Settings.hints_enabled)
	refresh()


func _on_replay_pressed() -> void:
	if Tip.swallowed():
		return
	HintState.reset()
	if not Settings.hints_enabled:
		Settings.set_hints_enabled(true)
	refresh()
	Sfx.play("reward")
	UiAnim.pulse(replay, 0.25, 0.3)
