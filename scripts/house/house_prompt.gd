extends CanvasLayer
## HousePrompt — модальное окно на весь экран (сцена scenes/house_prompt.tscn).
##
## Нужно там, где игру надо ОСТАНОВИТЬ и заставить сделать одно действие:
## второе истощение в шахте (ГДД п.9) выдаёт батончик в портфель и не
## отпускает, пока герой не поест. Поэтому слой выше всех остальных экранов —
## обучение не должно оказаться под шторкой магазина или инвентаря.
##
## Вид — значок в пульсирующей рамке и одна кнопка (HouseForcedCard), без
## абзаца; объяснение — в подсказке значка. Окно ничего не решает само:
## нажатие уходит сигналом confirmed наружу.

signal confirmed

var _card: HouseForcedCard


func _ready() -> void:
	layer = 30
	_card = HouseForcedCard.new()
	_card.name = "Card"
	add_child(_card)
	_card.confirmed.connect(func(): confirmed.emit())
	visible = false


## text — описание для подсказки значка, button_text — заголовок подсказки
## кнопки; title — заголовок подсказки значка (пусто — берётся button_text).
func show_prompt(text: String, button_text: String, title: String = "",
		icon: Texture2D = null, icon_px: float = 64.0) -> void:
	_card.setup(icon, icon_px, title if title != "" else button_text, text, button_text)
	visible = true
	_card.open()


func hide_prompt() -> void:
	if _card != null:
		_card.close()
	visible = false
