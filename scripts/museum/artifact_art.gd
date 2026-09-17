class_name ArtifactArt
extends RefCounted
## Единственное место, которое знает, где лежат спрайты артефактов.
##
## ПОЧЕМУ так: спрайтов артефактов ещё не существует, их рисует художник.
## Витрина не должна знать об этом ничего — она спрашивает текстуру и, если
## её нет, рисует заглушку с названием. Когда художник положит файлы в
## art/artifacts/, картинки появятся сами, без единой правки кода.
##
## Соглашение об именах: res://art/artifacts/<id артефакта>.png,
## где id — поле "id" из data/artifacts.json (antiquity_1 ... legends_5).
## Размер спрайта — SPRITE_PX (32×32, как тайл мира): витрина рисует слот
## 32×32 в рамке 40×40, и в вьюпорт шириной 224 такой ряд влезает пятью
## слотами ровно так, как требует ГДД (5 предметов в ветке).

const DIR := "res://art/artifacts/"
const SPRITE_PX := 32

# Кэш: витрина перерисовывается на каждое открытие, а load() на 25 файлов
# каждый раз — лишняя работа на телефоне.
static var _cache: Dictionary = {}


## Текстура артефакта или null, если художник её ещё не нарисовал.
static func texture_for(artifact_id: String) -> Texture2D:
	if _cache.has(artifact_id):
		return _cache[artifact_id]
	var path := DIR + artifact_id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[artifact_id] = tex
	return tex


static func has_art(artifact_id: String) -> bool:
	return texture_for(artifact_id) != null


## Короткая подпись для заглушки: полное название артефакта в слот 32×32 не
## влезает никогда, поэтому берём первые буквы первых двух слов
## («Религиозный свиток» -> «РС»). Читается как инвентарная метка и сразу
## даёт понять, что это за предмет, если игрок уже видел его в списке.
static func placeholder_initials(name_ru: String) -> String:
	var words := name_ru.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	var out := String(words[0]).substr(0, 1).to_upper()
	if words.size() > 1:
		out += String(words[1]).substr(0, 1).to_upper()
	return out


## Русское название слота ультимативного сета (ГДД раздел 10).
static func set_piece_name_ru(piece: String) -> String:
	match piece:
		"helmet": return "шлем"
		"chestplate": return "нагрудник"
		"shield": return "щит"
		"amulet": return "амулет"
		"glove": return "перчатка"
		_: return piece
