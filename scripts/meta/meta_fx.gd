class_name MetaFx
extends RefCounted
## «Сочность» получения награды: взрыв значков из плитки, полёт в кошелёк,
## звук и вибро. Звук, вибро и летящие иконки идут через общие фасады
## (Sfx/Haptics/Fx): когда ветка «звук и сок» поднимет сервисы, они заработают
## без правки здесь. Собственный взрыв значков рисуется всегда — на случай, если
## сервиса Fx ещё нет, награда всё равно должна «взорваться» в руках.

const LAYER := 98
static var _overlay: Control = null


static func _root(tree: SceneTree) -> Control:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	layer.name = "MetaFxLayer"
	tree.root.add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	return _overlay


static func _fx_service_exists(tree: SceneTree) -> bool:
	return tree.get_first_node_in_group(Fx.GROUP) != null


## Награда забрана: origin — центр плитки в экранных координатах, anchors —
## {coins, dollars, xp: Vector2} куда лететь (по умолчанию — кошелёк HUD).
## over_modal — забирают в окне поверх игры: значки летят на своём слое (98),
## а не через Fx — слой полёта сервиса (59) лежит под окнами мета-слоя (92–94)
## и под затемнением шахты, и полёт там не виден.
static func claim(tree: SceneTree, origin: Vector2, reward: Dictionary, big: bool = false, anchors: Dictionary = {},
		over_modal: bool = false) -> void:
	if tree == null:
		return
	var r := MetaRewards.normalize(reward)
	Sfx.play("coins_big" if big else "reward")
	Sfx.play("quest_done")
	Haptics.tap()
	if big:
		Fx.flash(Color(1.0, 0.9, 0.5, 0.22), 0.18)
	var parent := _root(tree)
	var own_fly := over_modal or not _fx_service_exists(tree)
	for key in ["coins", "dollars", "xp", "item"]:
		if not r.has(key):
			continue
		var item_id: String = String(r["item"]["id"]) if key == "item" else ""
		var t: Texture2D = MetaUiKit.reward_tex(key, item_id)
		var n := 1
		match key:
			"coins":
				n = 9 if big else 6
			"dollars", "xp":
				n = 3
		var to: Vector2 = anchors.get(key, MetaUiKit.anchor("dollars" if key == "dollars" else "coins"))
		if not own_fly:
			Fx.fly_to(t, origin, to, n)
		_pop(parent, t, origin, to, n, own_fly)


## Значки летят из from в to на слое мета-слоя — поверх HUD, окон и темноты шахты.
static func fly(tree: SceneTree, t: Texture2D, from: Vector2, to: Vector2, n: int = 3) -> void:
	if tree == null or t == null:
		return
	_pop(_root(tree), t, from, to, n, true)


static func _pop(parent: Control, t: Texture2D, origin: Vector2, to: Vector2, n: int, fly: bool) -> void:
	for i in range(n):
		var spr := TextureRect.new()
		spr.texture = t
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.size = Vector2(32, 32)
		spr.pivot_offset = Vector2(16, 16)
		spr.scale = Vector2(0.25, 0.25)
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.position = origin - Vector2(16, 16)
		parent.add_child(spr)
		var ang := (TAU * float(i) / float(n)) + randf_range(-0.35, 0.35)
		var burst_to := origin + Vector2(cos(ang), sin(ang)) * randf_range(16.0, 34.0) - Vector2(16, 16)
		var tw := spr.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "position", burst_to, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "scale", Vector2(0.5, 0.5), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().set_parallel(true)
		if fly:
			var delay := 0.08 + 0.05 * float(i)
			tw.tween_property(spr, "position", to - Vector2(16, 16), 0.5).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(spr, "scale", Vector2(0.25, 0.25), 0.5).set_delay(delay).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(spr.queue_free)
		else:
			tw.tween_property(spr, "modulate:a", 0.0, 0.3).set_delay(0.1)
			tw.chain().tween_callback(spr.queue_free)
