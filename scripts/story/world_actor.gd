class_name WorldActor
extends Node2D
## Актёр сюжета НА ЖИВОЙ КАРТЕ (дед, бабка — см. cutscene_player.gd, режим
## play(id, {"world": true})).
##
## Не player.gd: тот — герой игрока со своей физикой, инструментами и
## инвентарём, трогать его ради трёхлетней давности сцены нельзя (см.
## задание — "не ломай player.gd"). WorldActor ничего не решает сам: сюжет
## (CutscenePlayer) владеет его x/y/pose кадр за кадром — тот же приём, что
## AutoDigTutorial применяет к самому player.gd, пока тот "заморожен"
## (player.frozen=true, а x/y/anim двигает скрипт снаружи).
##
## Рисовка — тот же приём, что в scripts/player/character_view.gd: лист
## art/character/<dir>/<pose>.png нарезан на кадры 144×144 (ART_SCALE=3
## поверх логических 48×48, см. tools/import_art.py), якорь — по ступням,
## разворот — flip_h. Дед и бабка используют дефолтную линию земли (46*3=138
## снизу кадра) — их листы, в отличие от боевых листов игрока, нарисованы
## равномерной сеткой без штучных поправок ширины/высоты под замах инструмента.

const TILE := 32
const ART_SCALE := 3.0
const CHAR_FRAME := 144.0
const GROUND_Y := 138.0   # 46*ART_SCALE, см. character_view.gd:GROUND_Y
const HH := 0.46          # см. character_view.gd:HH
const ANIM_DIV := 7.0     # см. character_view.gd:ANIM_DIV

## Id актёра из data/story.json → actors.<id>.dir задаёт папку
## art/character/<dir>/. Читает StoryData, отдельного дублирования таблицы
## здесь нет — те же карточки, что использует классический "show".
var actor_id: String = ""
var x: float = 0.0
var y: float = 0.0
var pose: String = "idle"
var flip: bool = false
## Счётчик кадров — ведёт сюжет тем же приёмом, что и player.anim
## (см. auto_dig.gd: "player.anim += 60.0 * dt"), а не свой таймер: так темп
## анимации ходьбы/копки совпадает с тем, что игрок уже видел у героя.
var anim: float = 0.0

var _dir: String = ""
var _sprite: Sprite2D
var _frames: int = 1
var _frame_w: float = CHAR_FRAME
var _frame_h: float = CHAR_FRAME

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	# ВАЖНО: region_enabled=true у Sprite2D требует region_rect — в отличие
	# от TextureRect (см. cutscene_player.gd:_load_pose), где кадр режется
	# AtlasTexture'ом. Sprite2D.region_rect с текстурой-AtlasTexture — это
	# ДВА независимых кропа сразу, и незаполненный region_rect (по умолчанию
	# Rect2(0,0,0,0)) обрезает спрайт в НОЛЬ пикселей — актёр рисуется, но
	# невидимо. Правильный приём — тот же, что в character_view.gd:_process:
	# текстура НЕ через AtlasTexture, кадр вырезает region_rect сам.
	_sprite.region_enabled = true
	_sprite.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	add_child(_sprite)
	if not actor_id.is_empty():
		set_pose(pose, flip)


## Привязывает узел к актёру из таблицы data/story.json:actors. Можно звать
## и до _ready() (сразу после .new()) — тогда лист подгрузится в _ready();
## можно и после — тогда сразу.
func setup(id: String) -> void:
	actor_id = id
	_dir = String(StoryData.actor(id).get("dir", id))
	if _sprite != null:
		set_pose(pose, flip)


## Ширина кадра листов копки шире квадратного 144 (замах инструмента и
## разлетающаяся порода не влезают в 144×144 — та же причина, что у
## character_view.gd:SHEET_FRAME для тех же имён поз). Проверяется ВТОРЫМ
## заходом в set_pose(), после обычного квадратного 144 — так лист остаётся
## квадратным там, где он и правда квадратный (у "дед"/"бабка" dig_shovel.png
## нарезан на 144, см. ниже), и переключается на 192 только там, где 144 не
## делит ширину листа без остатка.
##
## БАГ (отчёт владельца, QA-проход): лист art/character/boy/dig_pick_rusty.png
## (и boy/dig_shovel.png, boy/dig_pick.png — тот же художник резал их шире,
## чем art/character/grandpa/dig_shovel.png) — 1536×144, восемь кадров по 192,
## а не по 144. 1536 не делится на 144 без остатка (в остатке 96) — старая
## проверка молчала и отдавала ОДИН кадр на весь лист. Из-за
## _sprite.region_enabled=true БЕЗ явного region_rect на кадр это не резало
## спрайт в ноль (в отличие от предупреждения в _ready() про AtlasTexture) —
## _sprite.region_rect ставился на ВЕСЬ лист 1536×144, и на экране появлялась
## НЕОБРЕЗАННАЯ полоса из всех восьми кадров анимации подряд, сжатая в кадр
## обычного роста персонажа. Видно это было как "второй мальчик" в сцене
## death (world_dig, поза dig_pick_rusty) — на самом деле два СОСЕДНИХ кадра
## одного нерезаного листа, а не два актёра (см. .qa_screenshots/
## bug_world_actor_wide_dig_frame).
const WIDE_DIG_FRAME_W := 192


## Меняет позу/разворот. Возвращает false молча (как _load_pose в
## cutscene_player.gd), если у актёра нет такого листа — Роберт и родители
## сейчас без спрайтов вообще, и сцена не должна падать, наткнувшись на них.
func set_pose(p_pose: String, p_flip: bool = false) -> bool:
	if _dir.is_empty() or p_pose.is_empty():
		return false
	var path := "res://art/character/%s/%s.png" % [_dir, p_pose]
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	var tex_h: int = int(round(tex.get_height()))
	var tex_w: int = int(round(tex.get_width()))
	_frames = 1
	_frame_w = float(tex_w)
	if tex_h == int(CHAR_FRAME):
		if tex_w % int(CHAR_FRAME) == 0:
			_frames = maxi(1, tex_w / int(CHAR_FRAME))
			_frame_w = float(CHAR_FRAME)
		elif tex_w % WIDE_DIG_FRAME_W == 0:
			_frames = maxi(1, tex_w / WIDE_DIG_FRAME_W)
			_frame_w = float(WIDE_DIG_FRAME_W)
	_frame_h = tex.get_height()
	_sprite.texture = tex
	_sprite.region_rect = Rect2(0, 0, _frame_w, _frame_h)
	pose = p_pose
	flip = p_flip
	_sprite.flip_h = flip
	return true


func _process(_dt: float) -> void:
	position = Vector2(x * TILE, y * TILE)
	# Якорь по ступням: низ кадра (GROUND_Y от верха) ложится на клетку
	# (x, y) так же, как у героя игрока — см. character_view.gd:_process.
	# Центр по ширине — по РЕАЛЬНОЙ ширине текущего кадра (_frame_w), не по
	# фиксированному CHAR_FRAME: у широких кадров копки (см. WIDE_DIG_FRAME_W
	# выше) иначе персонаж сидел бы смещённым от клетки на разницу ширин.
	_sprite.position = Vector2(-_frame_w / (2.0 * ART_SCALE), -HH * TILE - 16.0)
	if _frames <= 1 or _sprite.texture == null:
		return
	var idx: int = int(anim / ANIM_DIV) % _frames
	_sprite.region_rect = Rect2(idx * _frame_w, 0, _frame_w, _frame_h)
