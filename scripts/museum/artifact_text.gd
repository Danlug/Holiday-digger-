class_name ArtifactText
extends RefCounted
## Тексты артефактов, веток и ультимативного сета на нужном языке.
##
## ПОЧЕМУ отдельный класс: язык выбирает игрок (Settings.language), а тексты
## лежат в data/artifacts.json парами name_ru/name_en, desc_ru/desc_en,
## hint_ru/hint_en. Все экраны берут строки только отсюда — тогда добавить
## третий язык значит дописать поля в JSON и ничего не править в интерфейсе.
## Если английского поля нет (или оно пустое), берётся русское: лучше русская
## строка, чем пустая подсказка.


static func lang() -> String:
	return Settings.language


## Значение поля base_<язык> со сползанием на русский.
static func pick(d: Dictionary, base: String) -> String:
	var code := lang()
	if code != "ru":
		var v := String(d.get("%s_%s" % [base, code], ""))
		if not v.is_empty():
			return v
	return String(d.get("%s_ru" % base, ""))


static func name_of(artifact: Dictionary) -> String:
	var s := pick(artifact, "name")
	return s if not s.is_empty() else String(artifact.get("id", ""))


static func desc_of(artifact: Dictionary) -> String:
	return pick(artifact, "desc")


## Намёк для ненайденного предмета: название не раскрывает.
static func hint_of(artifact: Dictionary) -> String:
	return pick(artifact, "hint")


static func branch_name(branch: Dictionary) -> String:
	return pick(branch, "name")


static func set_name() -> String:
	return pick(Balance.artifacts.get("ultimate_set", {}), "name")


## Название слота ультимативного сета (шлем, нагрудник, щит, амулет, перчатка).
static func set_piece_name(piece: String) -> String:
	var names: Dictionary = Balance.artifacts.get("ultimate_set", {}).get("piece_names", {})
	var entry: Dictionary = names.get(piece, {})
	var code := lang()
	var s := String(entry.get(code, ""))
	if s.is_empty():
		s = String(entry.get("ru", ""))
	return s if not s.is_empty() else piece


## Артефакт ветки branch_num в слоте slot (1..5) или {}.
static func artifact_in_slot(branch_num: int, slot: int) -> Dictionary:
	for a in Balance.get_artifacts_in_branch(branch_num):
		if int(a.get("slot", 0)) == slot:
			return a
	return {}
