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


# --- Артефакт в породе (ArtifactLayer) ---------------------------------------
# Строится из той же иконки при первом показе, а не лежит отдельным PNG: художник
# заменит иконку — сменится и вид в земле. Это заглушка уровня «программист»:
# нижняя треть предмета срезана волнистой кромкой (утоплен в породу), по кромке —
# комья земли, вокруг видимой части — тёмная обводка, чтобы предмет читался на
# любой руде.
const BURY_FROM := 0.64                       # с какой доли высоты силуэта предмет уходит в породу
const GROUND_OUTLINE := Color8(0x14, 0x0E, 0x0A, 230)
const GROUND_DIRT := [Color8(0x3A, 0x2A, 0x1A), Color8(0x5E, 0x42, 0x28), Color8(0x7A, 0x58, 0x36)]

static var _ground_cache: Dictionary = {}


## Вид артефакта, наполовину утопленного в породу, или null — нет иконки.
static func ground_texture_for(artifact_id: String) -> Texture2D:
	if _ground_cache.has(artifact_id):
		return _ground_cache[artifact_id]
	var src := texture_for(artifact_id)
	var tex: Texture2D = null
	if src != null:
		var img := src.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			tex = ImageTexture.create_from_image(buried_image(img))
	_ground_cache[artifact_id] = tex
	return tex


## Иконка → «торчит из земли». Отдельно от текстуры, чтобы тест мог проверить пиксели.
static func buried_image(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var top := h
	var bottom := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				top = mini(top, y)
				bottom = maxi(bottom, y)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if bottom < 0:
		return out
	var line := top + int(float(bottom - top + 1) * BURY_FROM)
	var cut := PackedInt32Array()
	cut.resize(w)
	for x in range(w):
		cut[x] = line + (1 if (x * 7) % 5 < 2 else 0)   # кромка земли не по линейке
		for y in range(mini(cut[x], h)):
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				out.set_pixel(x, y, p)
	# обводка: прозрачная клетка рядом с видимой частью предмета
	var src := out.duplicate() as Image
	for y in range(h):
		for x in range(w):
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and src.get_pixel(nx, ny).a > 0.5:
					out.set_pixel(x, y, GROUND_OUTLINE)
					break
	# комья земли по кромке там, где предмет уходит в породу (и на пиксель шире)
	for x in range(w):
		var under := false
		for dx in [-1, 0, 1]:
			var sx: int = x + dx
			if sx >= 0 and sx < w and cut[sx] < h and img.get_pixel(sx, cut[sx]).a > 0.5:
				under = true
		if not under:
			continue
		for dy in range(2):
			var y := cut[x] + dy - 1
			if y >= 0 and y < h and (dy == 1 or (x * 3 + y) % 4 != 0):
				out.set_pixel(x, y, GROUND_DIRT[(x * 5 + y * 3) % GROUND_DIRT.size()])
	return out


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
