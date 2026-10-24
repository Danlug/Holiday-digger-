class_name MetaUiKit
extends RefCounted
## Общие детали оформления экранов мета-слоя: палитра (та же, что в hud.gd и
## ProgressUiKit), значки, плитки, красный бейдж, позиции «кошелька» для
## летящих наград. На плитках — только значки и числа; названия и описания
## живут в Tip.

const GOLD := ProgressUiKit.GOLD
const GOLD_LIGHT := Color8(0xFF, 0xE0, 0x66)
const MUTED := ProgressUiKit.MUTED
const DIM := ProgressUiKit.DIM
const BORDER := ProgressUiKit.BORDER
const BG := ProgressUiKit.BG
const CARD := ProgressUiKit.CARD_BG
const SLOT := Color8(0x24, 0x1E, 0x2C)
const GREEN := ProgressUiKit.GREEN
const GREEN_BTN := Color8(0x2F, 0x6B, 0x3B)
const RED := Color8(0xC2, 0x1E, 0x3A)
const BLUE := Color8(0x6F, 0xE0, 0xD8)
## Рамки достижений: бронза, серебро, золото.
const TIER_COL := [Color8(0xB0, 0x74, 0x3B), Color8(0xB8, 0xC4, 0xC8), Color8(0xE8, 0xB3, 0x2E)]

const ICON_DIR := "res://art/meta/"
## Значки из общей папки интерфейса: монета и доллар нарисованы художником —
## их не дублируем.
const SHARED := {
	"coin": "res://art/ui/icon_coin.png",
	"dollar": "res://art/ui/icon_dollar.png",
	"stamina": "res://art/ui/icon_stamina.png",
}
## Предметы-награды без собственной иконки показываются значком энергии.
const ITEM_ICON := {"energy_drink": "stamina", "energy_bar": "stamina"}

static var _tex: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var path: String = SHARED.get(name, "%s%s.png" % [ICON_DIR, name])
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[name] = t
	return t


## Значок награды по ключу: coins, dollars, xp, points или item (id предмета).
static func reward_tex(key: String, item_id: String = "") -> Texture2D:
	match key:
		"coins":
			return tex("coin")
		"dollars":
			return tex("dollar")
		"xp":
			return tex("xp")
		"points":
			return tex("star")
		"item":
			return tex(String(ITEM_ICON.get(item_id, "gift")))
	return tex("gift")


static func icon_rect(t: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func box(bg: Color, border: Color = BORDER, border_w: int = 1, radius: int = 6) -> StyleBoxFlat:
	return ProgressUiKit.box(bg, border, ProgressUiKit.snap_radius(radius), border_w)


static func label(text: String, size: int = 9, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Значок + число в ряд: «монета 130».
static func chip(t: Texture2D, text: String, color: Color = Color.WHITE, px: float = 12.0, size: int = 9) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon_rect(t, px))
	var l := label(text, size, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


## Ряд значков награды: монеты, доллары, опыт, предмет (без слов).
static func reward_row(reward: Dictionary, px: float = 12.0, size: int = 9) -> HBoxContainer:
	var r := MetaRewards.normalize(reward)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if r.has("coins"):
		row.add_child(chip(reward_tex("coins"), compact(int(r["coins"])), GOLD_LIGHT, px, size))
	if r.has("dollars"):
		row.add_child(chip(reward_tex("dollars"), str(int(r["dollars"])), Color8(0x4D, 0xE0, 0x94), px, size))
	if r.has("xp"):
		row.add_child(chip(reward_tex("xp"), compact(int(r["xp"])), BLUE, px, size))
	if r.has("item"):
		row.add_child(chip(reward_tex("item", String(r["item"]["id"])), "×%d" % int(r["item"]["count"]), Color.WHITE, px, size))
	return row


## 1500 -> «1.5k», чтобы число влезало в плитку.
static func compact(n: int) -> String:
	if n >= 10000:
		return "%dk" % (n / 1000)
	if n >= 1000:
		var s := "%.1fk" % (float(n) / 1000.0)
		return s.replace(".0k", "k")
	return str(n)


## Куда лететь награде: якорь HUD (coins, dollars, backpack, menu…).
static func anchor(id: String) -> Vector2:
	return HudAnchors.get_anchor(id)
