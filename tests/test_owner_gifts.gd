extends Node
## test_owner_gifts — владелец 29.10: «добавь мне 500 долларов на счёт игры».
## Подарок из data/gifts.json приходит уже игравшему сейву при загрузке один раз;
## новая игра (сброс прогресса) его не получает.
##
## Запуск: godot --headless --path . res://tests/test_owner_gifts.tscn

var failures := 0
var total := 0


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_owner_gifts ===")
	await get_tree().process_frame
	var owner_gift := {}
	for g in OwnerGifts.gifts():
		if String(g.get("id", "")) == "owner_2026_10_29":
			owner_gift = g
	check("в data/gifts.json есть подарок владельца на 500 долларов", int(owner_gift.get("dollars", 0)) == 500)

	# Сейв, записанный до подарка: о нём ничего не знает.
	GameState.reset_progress()
	GameState.dollars = 100
	GameState.ext = {}
	var got := OwnerGifts.apply_on_load()
	check("уже игравший сейв: пришло 500 (%d)" % got, got == 500 and GameState.dollars == 600)
	check("подарок записан в сейв как забранный", (GameState.ext.get("gifts_claimed", []) as Array).has("owner_2026_10_29"))
	got = OwnerGifts.apply_on_load()
	check("вторая загрузка: ничего (%d), долларов по-прежнему 600" % got, got == 0 and GameState.dollars == 600)

	GameState.reset_progress()
	check("новая игра (сброс): подарок сразу помечен забранным",
		(GameState.ext.get("gifts_claimed", []) as Array).has("owner_2026_10_29"))
	got = OwnerGifts.apply_on_load()
	check("новая игра подарка не получает (%d)" % got, got == 0 and GameState.dollars == 0)

	GameState.reset_progress()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)
