class_name Sfx
extends RefCounted
## Sfx — фасад звука. Любой скрипт зовёт Sfx.play("coin") и ничего не знает о
## том, есть ли в сцене проигрыватель: сервис — узел из группы "svc_sfx"
## (его создаёт владелец звука), а без него вызов молча ничего не делает —
## поэтому безопасно и в headless-тестах, и в режиме --script, где автозагрузок
## нет. Неизвестные id сервис тоже молча игнорирует: добавлять новые события
## можно, не дожидаясь, пока для них появится звук.
##
## Каталог событий (договорённость между ветками; новые — добавляйте сюда):
##   интерфейс : ui_tap ui_open ui_close ui_tab ui_toggle ui_buy ui_deny ui_slider
##   деньги    : coin coins_big sell
##   копка     : dig_dirt dig_stone dig_ore dig_gold dig_hard tile_break
##   движение  : step jump land fly_start fly_stop thud
##   герой     : hurt die respawn eat drink heal warn_low
##   прогресс  : pickup pickup_rare levelup skill_buy artifact quest_done reward
##   мир       : quake collapse lava_hiss door phone
##   бой       : swing hit_enemy enemy_die boss_roar hurt_armor
##   музыка    : mus_surface mus_mine_1 mus_mine_2 mus_deep mus_boss mus_story
##               mus_shop mus_menu

const GROUP := &"svc_sfx"


static func play(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var n := _service()
	if n != null:
		n.call("play", id, pitch, volume_db)


static func music(id: String, fade: float = 1.0) -> void:
	var n := _service()
	if n != null:
		n.call("music", id, fade)


static func stop_music(fade: float = 1.0) -> void:
	var n := _service()
	if n != null:
		n.call("stop_music", fade)


static func _service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP)
