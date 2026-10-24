class_name ShopPlaceHint
extends RefCounted
## ShopPlaceHint — как HUD и меню подсказывают правило «где можно покупать»
## (ShopService.can_buy): подсказка кнопки «Магазин», красная цифра «осталось
## роликов» на ней под землёй и строка пункта «Мастерская» в меню «•••».
## Только тексты и числа; решает всё ShopService, сюда логика не дублируется.


## [заголовок, описание, дополнение] подсказки кнопки «Магазин» в шапке HUD.
static func button_tip() -> Array:
	var gate := ShopService.can_buy({"kind": "good"})
	match String(gate["place"]):
		ShopService.PLACE_UNDERGROUND:
			if bool(gate["ok"]):
				return ["Магазин", "Еда и снаряжение — за ролик.",
					"Осталось сегодня: %d из %d" % [int(gate["left"]), int(gate["limit"])]]
			return ["Магазин", String(gate["reason"]), ""]
		ShopService.PLACE_DOOR:
			return ["Магазин", "У входной двери покупки без ограничений.", ""]
	return ["Магазин", String(gate["reason"]), "Обмен долларов и ролики — здесь"]


## Красная цифра на кнопке: сколько удалённых покупок осталось, только под землёй.
static func button_badge() -> int:
	var gate := ShopService.can_buy({"kind": "good"})
	return int(gate["left"]) if String(gate["place"]) == ShopService.PLACE_UNDERGROUND else 0


## Обновляет кнопку «Магазин»: подсказку и цифру. Дёшево — зовётся по таймеру HUD.
static func sync_button(btn: Control) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var t := button_tip()
	Tip.bind(btn, String(t[0]), String(t[1]), String(t[2]))
	UiBtn.set_badge(btn, button_badge())


## Строка пункта «Мастерская» в меню «•••».
static func menu_body() -> String:
	var gate := ShopService.can_buy({"kind": "good"})
	match String(gate["place"]):
		ShopService.PLACE_UNDERGROUND:
			return "Покупки за ролик: %d из %d" % [int(gate["left"]), int(gate["limit"])]
		ShopService.PLACE_DOOR:
			return "Продажа, верстак, лавка"
	return "Продажа. Покупки — у двери"
