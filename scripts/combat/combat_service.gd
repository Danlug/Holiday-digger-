class_name CombatService
extends RefCounted
## CombatService — логика снаряжения и урона без узлов и окна: что надето,
## сколько защиты/урона, снижение урона бронёй, крафт на верстаке, сокеты
## Перчатки Мироздания, прогресс босса. Всё сохраняемое лежит в
## GameState.ext["combat"] (SaveSystem не правился); JSON возвращает числа
## float, поэтому всё приводится int()/float() на чтении.
##
## Снаряжение не теряется при смерти: теряется только рюкзак (ГДД п.7), а
## надетое и собранное — часть героя, а не добычи.

const KEY := "combat"
const ACC_SLOTS := ["acc1", "acc2"]

## Интеграция с миром: сюда приходит main.gd одной строкой (см. attach()).
static var director: Node = null


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

static func state() -> Dictionary:
	var st = GameState.ext_get(KEY, null)
	if typeof(st) != TYPE_DICTIONARY:
		st = _default_state()
		GameState.ext[KEY] = st
	for k in ["owned", "equipped", "sockets", "boss", "kills"]:
		if typeof(st.get(k)) != TYPE_DICTIONARY:
			st[k] = {}
	return st


static func _default_state() -> Dictionary:
	return {
		"version": 1,
		"owned": {},
		"equipped": {},
		"sockets": {},
		"boss": {"defeated": false, "attempts": 0, "best_phase": 0},
		"kills": {},
	}


static func _save() -> void:
	GameState.ext_set(KEY, state())


static func in_war_zone(depth: int) -> bool:
	return depth >= CombatData.start_depth()


# ---------------------------------------------------------------------------
# Что у героя есть и что надето
# ---------------------------------------------------------------------------

## Предмет у героя: скрафчен/получен либо (для ультимативного сета) найден
## как артефакт в музее — ГДД п.10: пятые предметы веток образуют комплект.
static func is_owned(id: String) -> bool:
	if not CombatData.has_gear(id):
		return false
	if int(state()["owned"].get(id, 0)) > 0:
		return true
	var art := String(CombatData.gear(id).get("artifact", ""))
	return art != "" and GameState.collected_artifacts.has(art)


static func owned_ids() -> Array:
	var out: Array = []
	for id in CombatData.gear_ids():
		if is_owned(String(id)):
			out.append(String(id))
	out.sort_custom(func(a, b):
		var ga := CombatData.gear(a)
		var gb := CombatData.gear(b)
		var ta := int(ga.get("tier", 0))
		var tb := int(gb.get("tier", 0))
		if ta != tb:
			return ta < tb
		return String(a) < String(b))
	return out


static func has_anything() -> bool:
	return not owned_ids().is_empty()


static func give(id: String) -> bool:
	if not CombatData.has_gear(id) or is_owned(id):
		return false
	state()["owned"][id] = 1
	_save()
	return true


static func equipped(slot_key: String) -> String:
	var id := String(state()["equipped"].get(slot_key, ""))
	if id != "" and not is_owned(id):
		return ""
	return id


static func equipped_ids() -> Array:
	var out: Array = []
	for k in CombatData.slots():
		var id := equipped(String(k))
		if id != "":
			out.append(id)
	return out


static func slot_of(id: String) -> String:
	for k in CombatData.slots():
		if equipped(String(k)) == id:
			return String(k)
	return ""


## Надеть. slot_key можно не указывать: аксессуар встаёт в свободную ячейку,
## а если обе заняты — вытесняет первую. Возвращает false, если нельзя.
static func equip(id: String, slot_key: String = "") -> bool:
	if not is_owned(id):
		return false
	var keys := CombatData.slot_keys_for(id)
	if keys.is_empty():
		return false
	if slot_of(id) != "" and (slot_key == "" or slot_of(id) == slot_key):
		return true
	var target := slot_key
	if target == "" or not keys.has(target):
		target = String(keys[0])
		for k in keys:
			if equipped(String(k)) == "":
				target = String(k)
				break
	var cur := slot_of(id)
	if cur != "":
		state()["equipped"][cur] = ""
	state()["equipped"][target] = id
	_save()
	return true


static func unequip(slot_key: String) -> bool:
	if equipped(slot_key) == "":
		return false
	state()["equipped"][slot_key] = ""
	_save()
	return true


# ---------------------------------------------------------------------------
# Характеристики
# ---------------------------------------------------------------------------

static func socket_defs() -> Array:
	return CombatData.v(CombatData.section("sockets").get("slots"), [])


static func socket_cost() -> int:
	return int(CombatData.v(CombatData.section("sockets").get("cost_each"), 3))


static func socket_filled(mat_id: String) -> bool:
	return bool(state()["sockets"].get(mat_id, false))


static func sockets_filled_count() -> int:
	var n := 0
	for s in socket_defs():
		if socket_filled(String(s["id"])):
			n += 1
	return n


static func set_pieces_worn() -> int:
	var n := 0
	var pieces: Array = CombatData.section("sets").get("ultimate", {}).get("pieces", [])
	for id in equipped_ids():
		if pieces.has(id):
			n += 1
	return n


static func set_bonus(count: int) -> Dictionary:
	var out := {"def": 0.0, "dmg_pct": 0.0, "spd_pct": 0.0, "res_pct": 0.0, "regen": 0.0}
	for b in CombatData.section("sets").get("ultimate", {}).get("bonuses", []):
		if count >= int(b.get("count", 99)):
			for k in out.keys():
				out[k] += float(b.get(k, 0.0))
	return out


## Итоговые характеристики героя от надетого.
## defense — сумма защиты; reduction — доля срезаемого урона; damage/cd/reach —
## оружие с процентами; dps — для сравнения в экране «Снаряжение».
static func stats() -> Dictionary:
	var base: Dictionary = CombatData.section("player").get("base_weapon", {})
	var weapon := {
		"dmg": float(base.get("dmg", 14)),
		"cd": float(base.get("cd", 0.7)),
		"reach": float(base.get("reach", 1.3)),
	}
	var defense := 0.0
	var dmg_pct := 0.0
	var spd_pct := 0.0
	var res_pct := 0.0
	var regen := 0.0
	var worn := equipped_ids()
	var weapon_id := equipped("weapon")
	if weapon_id != "":
		var ws: Dictionary = CombatData.gear(weapon_id).get("stats", {})
		weapon["dmg"] = float(ws.get("dmg", weapon["dmg"]))
		weapon["cd"] = float(ws.get("cd", weapon["cd"]))
		weapon["reach"] = float(ws.get("reach", weapon["reach"]))
	for id in worn:
		var s: Dictionary = CombatData.gear(id).get("stats", {})
		defense += float(s.get("def", 0))
		dmg_pct += float(s.get("dmg_pct", 0))
		spd_pct += float(s.get("spd_pct", 0))
		res_pct += float(s.get("res_pct", 0))
		regen += float(s.get("regen", 0))
	var sb := set_bonus(set_pieces_worn())
	defense += sb["def"]
	dmg_pct += sb["dmg_pct"]
	spd_pct += sb["spd_pct"]
	res_pct += sb["res_pct"]
	regen += sb["regen"]
	# Сокеты работают, только пока перчатка на герое.
	if worn.has(String(CombatData.section("sockets").get("gear", "ult_glove"))):
		for sdef in socket_defs():
			if socket_filled(String(sdef["id"])):
				defense += float(sdef.get("def", 0))
				dmg_pct += float(sdef.get("dmg_pct", 0))
				spd_pct += float(sdef.get("spd_pct", 0))
				res_pct += float(sdef.get("res_pct", 0))
				regen += float(sdef.get("regen", 0))
	var cap := float(CombatData.formula("res_cap_pct", 75))
	res_pct = minf(res_pct, cap)
	var damage: float = float(weapon["dmg"]) * (1.0 + dmg_pct / 100.0)
	var cd: float = maxf(0.2, float(weapon["cd"]) / (1.0 + spd_pct / 100.0))
	return {
		"defense": defense,
		"reduction": reduction_for(defense),
		"damage": damage,
		"cd": cd,
		"reach": float(weapon["reach"]),
		"dps": damage / cd,
		"res_pct": res_pct,
		"regen": regen,
		"dmg_pct": dmg_pct,
		"spd_pct": spd_pct,
		"set_pieces": set_pieces_worn(),
	}


static func reduction_for(defense: float) -> float:
	var k := float(CombatData.formula("armor_k", 100))
	return defense / (defense + k) if defense > 0.0 else 0.0


## Урон, дошедший до героя: броня режет всё, сопротивление — ещё и огненное
## и теневое (kind != "phys"). Не меньше min_damage, чтобы удар всегда был
## ударом.
static func mitigate(raw: float, kind: String = "phys", st: Dictionary = {}) -> float:
	var s: Dictionary = st if not st.is_empty() else stats()
	var out := raw * (1.0 - float(s["reduction"]))
	if kind != "phys":
		out *= 1.0 - float(s["res_pct"]) / 100.0
	return maxf(float(CombatData.formula("min_damage", 1.0)), out)


## Восстановление HP в бою (из снаряжения и базовое) — работает только в
## военной зоне, чтобы не менять баланс выше 4000.
static func regen_per_sec() -> float:
	return float(CombatData.player_cfg("regen_base_per_sec", 1.0)) + float(stats()["regen"])


# ---------------------------------------------------------------------------
# Верстак: крафт и сокеты. Материалы берутся со склада, потом из рюкзака —
# так же, как у техники (ShopService), чтобы верстак вёл себя одинаково.
# ---------------------------------------------------------------------------

static func held(id: String) -> int:
	return HouseStorage.count(id) + GameState.get_item_count(id)


static func _consume(id: String, amount: int) -> bool:
	var left := amount - HouseStorage.consume(id, amount)
	if left <= 0:
		return true
	return GameState.remove_item(id, left)


static func at_workbench() -> bool:
	return ShopService.is_at_workshop()


## {ok, reason, missing: {id: сколько ещё}, missing_coins}
static func check_craft(id: String) -> Dictionary:
	var r := CombatData.recipe(id)
	var res := {"ok": false, "reason": "", "missing": {}, "missing_coins": 0}
	if r.is_empty():
		res["reason"] = "Нет такого рецепта"
		return res
	if is_owned(id):
		res["reason"] = "Уже собрано"
		return res
	if not at_workbench():
		res["reason"] = "Верстак дома, в подвале"
		# недостающее всё равно считаем — экран покажет «есть/нужно»
	var inputs: Dictionary = r.get("inputs", {})
	for mat in inputs.keys():
		var need := int(inputs[mat])
		var have := held(String(mat))
		if have < need:
			res["missing"][String(mat)] = need - have
	var coins := int(r.get("coins", 0))
	if coins > 0 and not GameState.debug_free_shop and GameState.coins < coins:
		res["missing_coins"] = coins - GameState.coins
	if res["reason"] == "" and (not (res["missing"] as Dictionary).is_empty() or int(res["missing_coins"]) > 0):
		res["reason"] = "Не хватает материалов"
	res["ok"] = res["reason"] == ""
	return res


static func can_craft(id: String) -> bool:
	return bool(check_craft(id)["ok"])


static func craft(id: String) -> Dictionary:
	var chk := check_craft(id)
	if not bool(chk["ok"]):
		return {"ok": false, "message": String(chk["reason"])}
	var r := CombatData.recipe(id)
	var inputs: Dictionary = r.get("inputs", {})
	for mat in inputs.keys():
		if not _consume(String(mat), int(inputs[mat])):
			return {"ok": false, "message": "Материалы кончились"}
	var coins := int(r.get("coins", 0))
	if coins > 0 and not GameState.spend_coins(coins):
		return {"ok": false, "message": "Не хватает монет"}
	give(id)
	var worn := false
	var keys := CombatData.slot_keys_for(id)
	if not keys.is_empty() and equipped(String(keys[0])) == "":
		worn = equip(id)
	GameState.emit_event(&"gear_crafted", {"id": id})
	SaveSystem.save_game()
	return {"ok": true, "message": CombatData.item_name(id), "equipped": worn}


## Вставить материал в сокет Перчатки Мироздания. Нужна сама перчатка (то есть
## найденный артефакт «Перчатка Мироздания») и верстак.
static func check_socket(mat_id: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "have": held(mat_id), "need": socket_cost()}
	var known := false
	for s in socket_defs():
		if String(s["id"]) == mat_id:
			known = true
	if not known:
		res["reason"] = "Нет такого сокета"
	elif socket_filled(mat_id):
		res["reason"] = "Сокет уже заполнен"
	elif not is_owned(String(CombatData.section("sockets").get("gear", "ult_glove"))):
		res["reason"] = "Нужна Перчатка Мироздания"
	elif not at_workbench():
		res["reason"] = "Верстак дома, в подвале"
	elif int(res["have"]) < int(res["need"]):
		res["reason"] = "Не хватает материала"
	res["ok"] = res["reason"] == ""
	return res


static func fill_socket(mat_id: String) -> Dictionary:
	var chk := check_socket(mat_id)
	if not bool(chk["ok"]):
		return {"ok": false, "message": String(chk["reason"])}
	if not _consume(mat_id, socket_cost()):
		return {"ok": false, "message": "Материалы кончились"}
	state()["sockets"][mat_id] = true
	_save()
	SaveSystem.save_game()
	return {"ok": true, "message": CombatData.material_name(mat_id)}


# ---------------------------------------------------------------------------
# Босс и счётчики
# ---------------------------------------------------------------------------

static func boss_state() -> Dictionary:
	var b: Dictionary = state()["boss"]
	if not b.has("defeated"):
		b["defeated"] = false
	return b


static func boss_defeated() -> bool:
	return bool(boss_state().get("defeated", false))


static func boss_note_attempt() -> void:
	var b := boss_state()
	b["attempts"] = int(b.get("attempts", 0)) + 1
	_save()


static func boss_note_phase(phase: int) -> void:
	var b := boss_state()
	if phase > int(b.get("best_phase", 0)):
		b["best_phase"] = phase
		_save()


## Награда за босса: материалы кладутся прямо на склад (рюкзак при смерти
## теряется, а награда за рейд — нет) и трофейное снаряжение. Повторно не
## выдаётся.
static func boss_claim_rewards() -> Dictionary:
	var b := boss_state()
	if bool(b.get("defeated", false)):
		return {}
	b["defeated"] = true
	_save()
	var rw: Dictionary = CombatData.section("boss").get("rewards", {})
	var mats: Dictionary = rw.get("materials", {})
	for id in mats.keys():
		HouseStorage.store_directly(String(id), int(mats[id]))
	for gid in rw.get("gear", []):
		give(String(gid))
	var xp := int(rw.get("xp", 0))
	if xp > 0:
		GameState.add_xp(xp)
	return rw


static func note_kill(id: String) -> void:
	var k: Dictionary = state()["kills"]
	k[id] = int(k.get(id, 0)) + 1


static func kills_total() -> int:
	var n := 0
	for id in state()["kills"].keys():
		n += int(state()["kills"][id])
	return n


# ---------------------------------------------------------------------------
# Подключение к игре
# ---------------------------------------------------------------------------

## Одна строка в main.gd: CombatService.attach(self). Ставит директора боя
## (монстры, удар, босс), слой интерфейса и экран «Снаряжение», регистрирует
## пункт меню. Мир не меняется до 4000: монстров выше нет, арена лежит на дне.
static func attach(host: Node) -> Node:
	if director != null and is_instance_valid(director):
		return director
	var d: Node = load("res://scripts/combat/combat_director.gd").new()
	d.name = "CombatDirector"
	host.add_child(d)
	director = d
	return d
