class_name DeathCause
extends RefCounted
## Причина смерти для окна смерти (ГДД §7 «Цена смерти», владелец 26.10: «ты умер —
## причина смерти (с голоду, от падения, сгорел, убит мобом…)»).
##
## Причину не угадывают по обстановке: добивший удар сам называет себя в
## GameState.take_damage(amount, source, info), die() кладёт DeathCause.make(...) в
## GameState.death_cause. Источники урона в коде (всё, что зовёт take_damage):
##   starvation / exhaustion — GameState._tick_survival (пустая сытость / пустая бодрость);
##   fall {cells}            — Player._land (высота от верхней точки полёта);
##   lava                    — Heat.burn_digger;
##   monster:<id> {guard}    — CombatDirector, удар монстра (guard — страж полости);
##   projectile:<вид> {id}   — CombatDirector, снаряд; id — кто стрелял;
##   boss:<удар> {id}        — CombatDirector, удары Идола Бездны.
## Фразы на будущие источники (жара, ртуть, перегрев бура — ГДД §7, §13) уже есть в
## data/death_window.json: новому источнику достаточно передать своё имя.

const DATA_PATH := "res://data/death_window.json"
const DEFAULT_LANG := "ru"

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func lang() -> String:
	var code := String(Settings.language)
	return code if data().has(code) else DEFAULT_LANG


## Строка интерфейса окна на языке игрока; нет перевода — русская.
static func text(key: String, group: String = "") -> String:
	for code in [lang(), DEFAULT_LANG]:
		var d: Dictionary = data().get(code, {})
		if group != "":
			d = d.get(group, {})
		if d.has(key):
			return String(d[key])
	return ""


# ---------------------------------------------------------------------------
# Причина из источника урона
# ---------------------------------------------------------------------------

## «monster:cave_bat» + {guard: true} → {source: "monster", id: "cave_bat", guard: true}.
## Пустой источник — {source: "unknown"}.
static func make(source: String, info: Dictionary = {}) -> Dictionary:
	var kind := source
	var detail := ""
	var colon := source.find(":")
	if colon >= 0:
		kind = source.substr(0, colon)
		detail = source.substr(colon + 1)
	var c := info.duplicate()
	c["source"] = kind if kind != "" else "unknown"
	match kind:
		"monster":
			c["id"] = detail
		"projectile":
			c["kind"] = detail
		"boss":
			c["attack"] = detail
			if String(c.get("id", "")) == "":
				c["id"] = String(CombatData.section("boss").get("id", "abyss_boss"))
	return c


# ---------------------------------------------------------------------------
# Фраза и значок
# ---------------------------------------------------------------------------

## «Убит монстром: Гротовая мышь», «Разбился при падении с высоты 42 клеток».
## glued — для окна: имя монстра и «42 клеток» не рвутся переносом строки.
static func phrase(cause: Dictionary, glued: bool = false) -> String:
	var src := String(cause.get("source", "unknown"))
	var id := String(cause.get("id", ""))
	match src:
		"fall":
			var cells := int(cause.get("cells", 0))
			if cells > 0:
				return text("fall_cells", "causes") % _glue(cells_text(cells), glued)
			return text("fall", "causes")
		"monster", "projectile":
			if id == "":
				return text("projectile", "causes")
			var key := "guard" if bool(cause.get("guard", false)) or CombatData.is_cave_monster(id) else "monster"
			return text(key, "causes") % _glue(monster_name(id), glued)
		"boss":
			return text("boss", "causes") % _glue(monster_name(id), glued)
	var s := text(src, "causes")
	return s if s != "" else text("unknown", "causes")


static func _glue(s: String, on: bool) -> String:
	return s.replace(" ", "\u00a0") if on else s


## Подсказка (Tip) к значку причины: как не умереть так снова.
static func hint(cause: Dictionary) -> String:
	var src := String(cause.get("source", "unknown"))
	if src == "projectile":
		src = "monster"
	return text(src, "hints")


## «42 клеток» / «21 клетки» (после «с высоты»: родительный падеж), «1 cell» / «42 cells».
static func cells_text(n: int) -> String:
	var one := n == 1
	if lang() == "ru":
		one = n % 10 == 1 and n % 100 != 11
	return text("cells_one" if one else "cells_many") % n


## Имя монстра или босса на языке игрока (русское — из data/combat.json).
static func monster_name(id: String) -> String:
	if lang() != DEFAULT_LANG:
		var names: Dictionary = data().get(lang(), {}).get("monsters", {})
		if names.has(id):
			return String(names[id])
	if id == String(CombatData.section("boss").get("id", "")):
		return String(CombatData.section("boss").get("name", id))
	return String(CombatData.monster(id).get("name", id))


## Значок причины: портрет монстра (первый кадр покоя), голод, бодрость, пламя, ртуть…
static func icon(cause: Dictionary) -> Texture2D:
	var src := String(cause.get("source", "unknown"))
	var id := String(cause.get("id", ""))
	match src:
		"starvation":
			return UiIcons.tex("hunger")
		"exhaustion":
			return UiIcons.tex("stamina")
		"fall":
			return UiIcons.tex("fall")
		"lava", "heat", "overheat":
			return MetaUiKit.tex("flame")
		"mercury":
			return UiIcons.item("mercury")
		"monster", "projectile", "boss":
			var portrait := monster_portrait(id, src == "boss")
			if portrait != null:
				return portrait
			return MetaUiKit.tex("fang")
	return MetaUiKit.tex("skull")


## Первый кадр анимации покоя из листа монстра (art/monsters/<sprite>.png).
static func monster_portrait(id: String, boss: bool = false) -> Texture2D:
	if id == "":
		return null
	var sprite := String(CombatData.section("boss").get("sprite", id)) if boss else id
	var sheet := MonsterSheet.get_sheet(sprite)
	if sheet == null or sheet.texture == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = sheet.region("idle", 0.0)
	return at
