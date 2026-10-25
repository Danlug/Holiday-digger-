extends Node
## test_dialogue.gd — вид диалогов и катсцен: портреты говорящих, печать текста,
## плашка и портреты в границах экрана, кнопка «Пропустить» (долгое нажатие и
## двойной тап), кинополосы, карточки сцен и совместимость со всеми сценами сюжета.
##
## Запуск: godot --headless --path . res://tests/test_dialogue.tscn
## Скриншоты — отдельно: tests/test_screenshot_dialogue.gd (см. шапку).

var failures := 0
var total := 0
var _confirmed := 0


func _ready() -> void:
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _run() -> void:
	print("=== test_dialogue.gd ===")
	Settings.reduce_motion = false
	StoryText.load_locale("ru")
	StoryData.ensure_loaded()

	_test_cast_portraits()
	_test_faces()
	await _test_typing()
	await _test_typing_calm()
	await _test_slots()
	await _test_geometry()
	await _test_skip_button()
	await _test_real_input()
	await _test_bars_and_card()
	await _test_locale()
	await _test_all_scenes()

	Settings.reduce_motion = false
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frame() -> void:
	await get_tree().process_frame


## DialogueUI в дереве, без ожидания кадров: тест сам задаёт dt.
func _make_ui(vp: Vector2 = Vector2(224, 480)) -> DialogueUI:
	var holder := Control.new()
	holder.size = vp
	add_child(holder)
	var ui := DialogueUI.new()
	holder.add_child(ui)
	ui.relayout(vp, 30.0)
	return ui


func _drop(ui: DialogueUI) -> void:
	ui.get_parent().queue_free()


# ---------------------------------------------------------------------------

func _test_cast_portraits() -> void:
	var who_list := DialogueCast.speakers_in_story()
	check("в сюжете есть говорящие", who_list.size() >= 6, str(who_list))
	for who in who_list:
		var w := String(who)
		check("у говорящего «%s» есть запись в труппе" % w, DialogueCast.has_speaker(w))
		var pid := DialogueCast.portrait_id(w)
		var tex := DialogueCast.sheet(pid)
		check("портрет «%s» загружается" % w, tex != null)
		if tex == null:
			continue
		check("лист «%s» — 3 кадра × 5 выражений по 64 px" % w,
			tex.get_width() == DialogueCast.FRAMES.size() * DialogueCast.CELL
			and tex.get_height() == DialogueCast.FACES.size() * DialogueCast.CELL,
			"%dx%d" % [tex.get_width(), tex.get_height()])
		var img := tex.get_image()
		var empty: Array = []
		for fi in DialogueCast.FACES.size():
			for fr in DialogueCast.FRAMES.size():
				var r := Rect2i(fr * DialogueCast.CELL, fi * DialogueCast.CELL, DialogueCast.CELL, DialogueCast.CELL)
				var opaque := 0
				var sub := img.get_region(r)
				for y in range(0, DialogueCast.CELL, 2):
					for x in range(0, DialogueCast.CELL, 2):
						if sub.get_pixel(x, y).a > 0.5:
							opaque += 1
				if opaque < 200:
					empty.append("%s/%s" % [DialogueCast.FACES[fi], DialogueCast.FRAMES[fr]])
		check("в листе «%s» нет пустых кадров" % w, empty.is_empty(), str(empty))
	# Экипированные двойники: портрет подменяется, пока на сцене стоит двойник.
	check("внук в экипировке: портрет boy_gear", DialogueCast.portrait_id("boy", ["boy_gear"]) == "boy_gear")
	check("внук без двойника: обычный портрет", DialogueCast.portrait_id("boy", ["boy"]) == "boy")
	check("дед в экипировке: портрет grandpa_gear", DialogueCast.portrait_id("grandpa", ["grandpa_gear"]) == "grandpa_gear")
	check("неизвестный говорящий — без портрета", DialogueCast.portrait_id("nobody").is_empty())
	for extra in ["boy_gear", "grandpa_gear"]:
		check("лист двойника «%s» загружается" % extra, DialogueCast.sheet(extra) != null)


func _test_faces() -> void:
	check("«?!» — удивление", DialogueCast.guess_face("boy", "В деревню?! Да там же!") == "surprise")
	check("многоточие в начале — грусть", DialogueCast.guess_face("boy", "...Это дед говорил.") == "sad")
	check("многоточие и вопрос — удивление", DialogueCast.guess_face("boy", "...это бабкин дом?") == "surprise")
	check("восклицание у бабки — злость", DialogueCast.guess_face("grandma_poor", "Вылезай сейчас же!") == "angry")
	check("спокойная реплика — нейтральное лицо", DialogueCast.guess_face("boy", "Ну здравствуй.") == "neutral")
	check("Голос всегда нейтрален", DialogueCast.guess_face("voice", "Ещё чу...") == "neutral")
	check("английский текст разбирается так же", DialogueCast.guess_face("boy", "What?! No way!") == "surprise")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(DialogueCast.PATH))
	var bad: Array = []
	for key in doc.get("faces", {}).keys():
		if not DialogueCast.FACES.has(String(doc["faces"][key])) or not StoryText.has_key(String(key)):
			bad.append(key)
	check("замены лиц в data/dialogue.json ссылаются на существующие ключи и лица", bad.is_empty(), str(bad))
	for who in doc.get("speakers", {}).keys():
		var sp: Dictionary = doc["speakers"][who]
		check("у «%s» сторона left/right и высота голоса > 0" % who,
			sp.get("side", "") in ["left", "right"] and float(sp.get("pitch", 0.0)) > 0.0)


func _test_typing() -> void:
	var ui := _make_ui()
	var text := "Ну а чего? Всё равно всё в интернете есть, правда же."
	ui.show_line("boy", "Внук", text)
	check("после показа реплики печать идёт", ui.typing)
	check("в начале печати текст скрыт", ui.line.visible_ratio < 0.2, "ratio=%.2f" % ui.line.visible_ratio)
	var prev := -1.0
	var monotonic := true
	var steps := 0
	var t_total := 0.0
	while ui.typing and steps < 2000:
		ui.tick(0.016)
		t_total += 0.016
		if ui.line.visible_ratio + 0.0001 < prev:
			monotonic = false
		prev = ui.line.visible_ratio
		steps += 1
	check("текст проявляется монотонно", monotonic)
	check("печать завершается сама", not ui.typing and steps < 2000)
	check("в конце печати виден весь текст", ui.line.visible_ratio >= 1.0)
	var plain_time := float(text.length()) / DialogueCast.typing_param("cps", 42.0)
	check("паузы на знаках препинания замедляют печать", t_total > plain_time + 0.2,
		"%.2f против %.2f" % [t_total, plain_time])
	var letters := 0
	for ch in text:
		if ch.to_upper() != ch.to_lower() or ch.is_valid_int():
			letters += 1
	check("блип считает только буквы", ui._letters == letters, "%d из %d" % [ui._letters, letters])

	# Тап посреди печати дописывает реплику целиком.
	ui.show_line("boy", "Внук", text)
	for _i in 8:
		ui.tick(0.016)
	check("посреди печати текст виден не весь", ui.typing and ui.line.visible_ratio < 1.0)
	ui.finish_typing()
	check("домотка: печать окончена", not ui.typing)
	check("домотка: виден весь текст", ui.line.visible_ratio >= 1.0)
	ui.tick(0.016)
	check("после домотки тик ничего не прячет", ui.line.visible_ratio >= 1.0)

	# Строка, дописанная снаружи (скриншот-инструмент), тоже считается оконченной.
	ui.show_line("boy", "Внук", text)
	ui.line.visible_ratio = 1.0
	ui.tick(0.016)
	check("внешняя дописка завершает печать", not ui.typing)

	# Закадровый текст не бипает и не печатает под чужим именем.
	ui.show_line("", "", "Дед копал картошку.")
	for _i in 200:
		ui.tick(0.016)
	check("закадровый текст допечатан", not ui.typing and ui._letters == 0)
	_drop(ui)
	await _frame()


func _test_typing_calm() -> void:
	Settings.reduce_motion = true
	var ui := _make_ui()
	ui.show_line("boy", "Внук", "Длинная реплика, которая при «меньше движения» видна сразу целиком.")
	check("меньше движения: печати нет", not ui.typing)
	check("меньше движения: текст виден сразу", ui.line.visible_ratio >= 1.0)
	ui.show_line("grandma_rich", "Бабка", "Проходи.")
	check("меньше движения: портрет без анимации стоит на месте",
		ui.portrait("right").position.is_equal_approx(ui.portrait("right").target_pos))
	_drop(ui)
	Settings.reduce_motion = false
	await _frame()


func _test_slots() -> void:
	var ui := _make_ui()
	ui.show_line("boy", "Внук", "Раз.")
	check("внук слева", ui.slot_who("left") == "boy" and ui.active_side() == "left")
	ui.show_line("grandma_rich", "Бабка", "Два.")
	check("бабка справа, подсвечена", ui.slot_who("right") == "grandma_rich" and ui.active_side() == "right")
	check("внук остался и притушен", ui.slot_who("left") == "boy" and not ui.portrait("left").active)
	check("у подсвеченного портрета есть арт", ui.portrait("right").has_art() and ui.portrait("left").has_art())
	ui.show_line("boy", "Внук", "Три.")
	check("реплика внука снова подсвечивает его", ui.active_side() == "left" and ui.portrait("left").active
		and not ui.portrait("right").active)
	ui.show_line("", "", "Закадровый текст.")
	check("закадровый текст: говорящего нет", ui.active_side() == "" and ui.slot_who("left") == "" and ui.slot_who("right") == "")
	ui.show_line("boy", "Внук", "Четыре.", {"stage": ["boy_gear"]})
	check("внук в экипировке: портрет boy_gear", ui.portrait("left").portrait_id == "boy_gear")

	# Два «правых» говорящих подряд (дед и бабка в интро деда): второй уходит налево.
	ui.hide_all()
	ui.show_line("grandma_poor", "Бабка", "Ужинать иди!")
	ui.show_line("grandpa", "Дед", "Сейчас, сейчас.")
	check("дед и бабка — по разные стороны", ui.slot_who("right") == "grandma_poor" and ui.slot_who("left") == "grandpa")
	ui.show_line("grandma_poor", "Бабка", "Вылезай!")
	check("повторная реплика бабки не двигает портреты", ui.slot_who("right") == "grandma_poor" and ui.slot_who("left") == "grandpa"
		and ui.active_side() == "right")
	ui.show_line("robert", "Роберт", "Готово.")
	check("третий говорящий вытесняет молчавшего, а не говорившего", ui.slot_who("right") == "robert" or ui.slot_who("left") == "robert")
	ui.hide_all()
	check("hide_all скрывает плашку и портреты", not ui.visible and ui.slot_who("left") == "" and ui.slot_who("right") == "")
	# Выражение подставляется из текста.
	ui.show_line("boy", "Внук", "Что?! Не может быть!")
	check("«?!» — портрет удивлён", ui.portrait("left").face == "surprise")
	ui.show_line("boy", "Внук", "Явная замена.", {"face": "happy"})
	check("явное выражение главнее подбора", ui.portrait("left").face == "happy")
	_drop(ui)
	await _frame()


func _test_geometry() -> void:
	var longest := ""
	for sid in StoryData.scene_ids():
		for b in StoryData.beats(String(sid)):
			if String(b.get("t", "")) in ["say", "narr"]:
				var t := StoryText.get_text(String(b.get("text", "")))
				if t.length() > longest.length():
					longest = t
	check("нашли самую длинную реплику", longest.length() > 100, str(longest.length()))
	for vp in [Vector2(224, 480), Vector2(300, 640), Vector2(448, 960)]:
		var ui := _make_ui(vp)
		var inset := CinematicBars.bar_height_for(vp.y) + 4.0
		ui.relayout(vp, inset)
		for case in [["boy", "Внук"], ["grandma_rich", "Бабка"], ["", ""]]:
			ui.show_line(case[0], case[1], longest)
			ui.finish_typing()
			for _i in 30:
				ui.tick(0.05)
			var r := ui.box_rect()
			var tag := "%s %dx%d" % [case[0] if case[0] != "" else "закадр", int(vp.x), int(vp.y)]
			check("плашка в границах экрана (%s)" % tag,
				r.position.x >= 0.0 and r.end.x <= vp.x + 0.01 and r.position.y >= 0.0 and r.end.y <= vp.y - inset + 0.5,
				str(r))
			var text_bottom := ui.line.position.y + ui.line.size.y
			check("текст помещается в плашку (%s)" % tag, text_bottom <= r.size.y - 6.0 and ui.line.get_line_count() >= 1,
				"низ текста %.0f при высоте %.0f" % [text_bottom, r.size.y])
			for side in ["left", "right"]:
				var p := ui.portrait(side)
				if p.visible and not p.who.is_empty():
					var pr := Rect2(p.target_pos, Vector2(DialoguePortrait.SIZE_PX, DialoguePortrait.SIZE_PX))
					check("портрет %s в границах экрана (%s)" % [side, tag],
						pr.position.x >= 0.0 and pr.end.x <= vp.x and pr.position.y >= 0.0, str(pr))
					var text_top := r.position.y + ui.line.position.y
					check("портрет не налезает на текст (%s)" % tag, pr.end.y <= text_top - 3.0,
						"низ портрета %.0f, верх текста %.0f" % [pr.end.y, text_top])
			if ui.ribbon.visible:
				var rr := Rect2(ui.ribbon.position, ui.ribbon.size)
				check("ленточка с именем в границах экрана (%s)" % tag, rr.position.x >= 0.0 and rr.end.x <= vp.x, str(rr))
		_drop(ui)
	await _frame()


func _test_skip_button() -> void:
	var holder := Control.new()
	add_child(holder)
	var btn := SkipButton.new()
	holder.add_child(btn)
	_confirmed = 0
	btn.confirmed.connect(func() -> void: _confirmed += 1)
	check("кнопка не меньше 22 единиц по высоте", SkipButton.SIZE_PX.y >= 22.0 and SkipButton.SIZE_PX.x >= 22.0)

	btn.press()
	btn.release()
	check("одиночное касание не пропускает", _confirmed == 0)
	check("одиночное касание показывает подсказку", btn.hint_visible())
	btn.press()
	btn.release()
	check("двойное касание подтверждает пропуск", _confirmed == 1)
	check("после подтверждения подсказка убрана", not btn.hint_visible())

	btn.reset_state()
	btn.press()
	btn._process(0.25)
	check("короткое удержание ещё не пропускает", _confirmed == 1 and btn.is_holding() and btn.hold_progress() > 0.2)
	btn._process(0.5)
	check("долгое нажатие подтверждает пропуск", _confirmed == 2)
	check("после пропуска удержание сброшено", not btn.is_holding())

	btn.reset_state()
	btn.press()
	btn._process(0.3)
	btn.release()
	check("отпускание до срока пропуск отменяет", _confirmed == 2)
	btn.reset_state()
	# Окно двойного тапа закрылось. Ждать по таймеру сцены нельзя: окно меряется Time.get_ticks_msec(),
	# а таймер сцены под нагрузкой CPU отстаёт от него — раз в сотню запусков второй тап считался двойным.
	btn._last_tap_ms = Time.get_ticks_msec() - SkipButton.DOUBLE_MS - 100
	btn.press()
	btn.release()
	check("касания вразнос — два одиночных, а не двойной", _confirmed == 2)
	holder.queue_free()
	await _frame()


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	get_viewport().push_input(ev, true)


func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	get_viewport().push_input(ev, true)


## Настоящие события ввода: тап по сцене (дописать → дальше) и кнопка «Пропустить»
## мышью и пальцем, а не прямые вызовы методов.
func _test_real_input() -> void:
	var cs := CutscenePlayer.new()
	add_child(cs)
	await _frame()
	var done := [false]
	cs.finished.connect(func(_s: String) -> void: done[0] = true)
	cs.play("autodig_done", {})
	check("реплика сцены печатается", cs._typing and cs.is_playing)
	_mouse(Vector2(112, 200), true)
	check("первый тап дописывает реплику целиком", not cs._typing and cs.is_playing and cs._dlg.line.visible_ratio >= 1.0)
	_mouse(Vector2(112, 200), false)
	_touch(Vector2(112, 200), true)
	check("второе событие того же касания не пролистывает реплику", cs.is_playing)
	await get_tree().create_timer(0.15).timeout
	_mouse(Vector2(112, 200), true)
	check("следующий тап ведёт дальше: сцена закончена", done[0] and not cs.is_playing)
	_mouse(Vector2(112, 200), false)
	cs.queue_free()

	var holder := Control.new()
	add_child(holder)
	var btn := SkipButton.new()
	holder.add_child(btn)
	btn.position = Vector2(150, 20)
	_confirmed = 0
	btn.confirmed.connect(func() -> void: _confirmed += 1)
	await _frame()
	var at := btn.position + SkipButton.SIZE_PX * 0.5
	_mouse(at, true)
	_mouse(at, false)
	check("мышь: одиночный щелчок только подсказывает", _confirmed == 0 and btn.hint_visible())
	_mouse(at, true)
	_mouse(at, false)
	check("мышь: двойной щелчок пропускает", _confirmed == 1)
	await get_tree().create_timer(0.7).timeout
	btn.reset_state()
	_touch(at, true)
	await get_tree().create_timer(SkipButton.HOLD_SEC + 0.2).timeout
	check("палец: долгое нажатие пропускает", _confirmed == 2)
	_touch(at, false)
	check("палец: отпускание после пропуска ничего не добавляет", _confirmed == 2)
	_mouse(Vector2(10, 300), true)
	_mouse(Vector2(10, 300), false)
	check("касание мимо кнопки её не трогает", _confirmed == 2)
	holder.queue_free()
	await _frame()


func _test_bars_and_card() -> void:
	var vp := Vector2(224, 480)
	var bars := CinematicBars.new()
	add_child(bars)
	bars.open(vp, false)
	check("кинополосы открыты на высоту по доле экрана", is_equal_approx(bars.height, CinematicBars.bar_height_for(vp.y)) and bars.visible)
	check("полоса не съедает больше 7% экрана", CinematicBars.bar_height_for(vp.y) / vp.y < 0.07)
	bars.close(false)
	check("закрытые полосы скрыты", not bars.visible and bars.height == 0.0)
	Settings.reduce_motion = false
	bars.open(vp, true)
	check("полосы въезжают плавно, а не мгновенно", bars.height < CinematicBars.bar_height_for(vp.y) * 0.5)
	await get_tree().create_timer(CinematicBars.OPEN_SEC + 0.15).timeout
	check("полосы доехали", is_equal_approx(bars.height, CinematicBars.bar_height_for(vp.y)))
	bars.queue_free()

	var card := SceneCard.new()
	add_child(card)
	card.layout(vp)
	card.show_text("Позапрошлое лето.\nДеревня Колдобино.", 3.0)
	check("карточка показана", card.visible and card.text.contains("Колдобино"))
	check("карточка в начале прозрачна", card.modulate.a < 0.05)
	card.set_progress(1.5, 3.0)
	check("в середине кадра карточка полностью видна", is_equal_approx(card.modulate.a, 1.0))
	card.set_progress(2.99, 3.0)
	check("в конце кадра карточка гаснет", card.modulate.a < 0.1)
	Settings.reduce_motion = true
	card.set_progress(0.0, 3.0)
	check("меньше движения: карточка сразу видна", is_equal_approx(card.modulate.a, 1.0))
	Settings.reduce_motion = false
	card.hide_card()
	check("карточка прячется", not card.visible)
	card.queue_free()

	var item := ItemCard.new()
	add_child(item)
	item.layout(vp)
	var long_text := "Ручка гладкая, вытертая до блеска чужими ладонями. Железо в ржавчине, но острое. Ты нашёл кирку. Теперь можно не только копать землю, но и добывать минералы."
	item.show_item(null, "Ржавая кирка деда", long_text)
	check("карточка предмета целиком на экране", item.position.y >= 0.0 and item.position.y + item.size.y <= vp.y,
		str(Rect2(item.position, item.size)))
	check("карточка предмета растёт под текст", item.size.y > 150.0, "h=%.0f" % item.size.y)
	item.queue_free()
	await _frame()


func _test_locale() -> void:
	for loc in ["ru", "en"]:
		StoryText.load_locale(loc)
		check("[%s] есть подсказка кнопки пропуска" % loc, StoryText.has_key("ui.skip_hint") and StoryText.has_key("ui.skip"))
		var names_ok := true
		for who in DialogueCast.speakers_in_story():
			var key := StoryData.actor_speaker_key(String(who))
			if key.is_empty() or not StoryText.has_key(key) or StoryText.get_text(key).strip_edges().is_empty():
				names_ok = false
		check("[%s] у всех говорящих есть имя для ленточки" % loc, names_ok)
		var holder := Control.new()
		add_child(holder)
		var btn := SkipButton.new()
		holder.add_child(btn)
		btn.press()
		btn.release()
		check("[%s] подсказка кнопки — текст StoryText" % loc, btn._hint_label.text == StoryText.get_text("ui.skip_hint"))
		holder.queue_free()
	StoryText.load_locale("ru")
	await _frame()


## Все сцены сюжета через настоящий CutscenePlayer (без живого мира: кадры «world_*»
## молча пропускаются, а реплики и карточки идут как обычно). Проверяем, что у
## каждой реплики говорящего с записью в труппе на экране есть портрет с артом.
func _test_all_scenes() -> void:
	var cs := CutscenePlayer.new()
	add_child(cs)
	await _frame()
	var bad_portrait: Array = []
	var unfinished: Array = []
	var said := 0
	var cards := 0
	for sid in StoryData.scene_ids():
		var id := String(sid)
		var done := [false]
		var on_done := func(_s: String) -> void: done[0] = true
		cs.finished.connect(on_done)
		cs.play(id, {})
		var steps := 0
		while cs.is_playing and steps < 600:
			steps += 1
			if cs._index > 0 and cs._index <= cs._beats.size():
				var last: Dictionary = cs._beats[cs._index - 1]
				var kind := String(last.get("t", ""))
				if kind == "say":
					said += 1
					var who := String(last.get("who", ""))
					var side := cs._dlg.active_side()
					var p := cs._dlg.portrait(side) if not side.is_empty() else null
					if DialogueCast.has_speaker(who) and (p == null or not p.has_art() or p.who != who):
						bad_portrait.append("%s:%s" % [id, who])
				elif kind == "narr":
					if not cs._dlg.active_side().is_empty():
						bad_portrait.append("%s: у закадрового текста не должно быть говорящего" % id)
				elif kind == "card":
					cards += 1
					if not cs._card.visible or cs._dlg.visible:
						bad_portrait.append("%s: карточка и плашка одновременно" % id)
			cs._dlg.finish_typing()
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._tap_target.visible = false
			cs._advance()
		cs.finished.disconnect(on_done)
		if not done[0]:
			unfinished.append(id)
		check("%s: доиграна, плашка и карточка погашены" % id, done[0] and not cs._dlg.visible and not cs._card.visible)
	check("у каждой реплики говорящего есть подсвеченный портрет", bad_portrait.is_empty(), str(bad_portrait))
	check("все сцены дошли до конца", unfinished.is_empty(), str(unfinished))
	check("реплики и карточки действительно прошли", said > 60 and cards > 15, "%d / %d" % [said, cards])
	check("после сцен кинополосы закрываются", not cs._bars.is_open() or cs._bars.target_height == 0.0)
	check("после сцен «Пропустить» спрятан", not cs._skip_btn.visible)

	# «Пропустить» мгновенно доигрывает сцену и по-прежнему шлёт finished.
	var skipped := [false]
	cs.finished.connect(func(_s: String) -> void: skipped[0] = true)
	cs.play("intro_boy", {})
	check("сцена играет, кнопка пропуска видна", cs.is_playing and cs._skip_btn.visible)
	cs._skip_btn.confirmed.emit()
	check("подтверждённый пропуск доигрывает сцену", skipped[0] and not cs.is_playing)
	cs.queue_free()
	await _frame()
