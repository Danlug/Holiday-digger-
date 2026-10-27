class_name QuestGen
extends RefCounted
## Генератор заданий. Чистые функции: один и тот же набор (период, сид мира,
## ступень игрока, виденные события) всегда даёт один и тот же список заданий —
## перезапуск игры или переустановка не «перебрасывает» задания дня.
##
## Задание — словарь (кладётся в сейв как есть):
##   id, tpl (шаблон), kind (daily|weekly), slot, event (id шины или список
##   id), filter, sum, mode, target, progress, base (рекорд глубины для
##   mode:delta), tier, glyph, reward{coins,dollars,xp}, points, claimed

const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619


## FNV-1a по байтам строки: String.hash() движка стабильность между
## платформами не обещает, а сид обязан совпадать везде.
static func hash_seed(text: String) -> int:
	var h := FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * FNV_PRIME) & 0xFFFFFFFF
	return h


static func tier_for(max_depth: int) -> int:
	var th: Array = MetaData.quests().get("tier_by_max_depth", [0])
	var t := 0
	for i in range(th.size()):
		if max_depth >= int(th[i]):
			t = i
	return t


## Число или обёртка {value, proposed, note} из data-файлов (числа владельца
## внутри файла с общим proposed лежат обёрнутыми).
static func num(node, default = 0):
	if node is Dictionary:
		return (node as Dictionary).get("value", default)
	return default if node == null else node


## Сколько заданий в наборе: count конфигурации (по умолчанию — число слотов).
static func count_of(cfg: Dictionary) -> int:
	return int(num(cfg.get("count"), (cfg.get("slots", []) as Array).size()))


## Шаблон годится игроку этой ступени: вид задания, диапазон ступеней, рекорд
## глубины (record_min/record_max: монстры живут с 1500, «рекорд +N» у дна мира
## невыполним) и «событие уже было на шине» (requires_seen). max_depth < 0 —
## рекорд не проверять.
static func _eligible(t: Dictionary, kind: String, tier: int, seen: Dictionary, max_depth: int = -1) -> bool:
	if not (t.get("kinds", []) as Array).has(kind):
		return false
	if tier < int(t.get("min_tier", 0)) or tier > int(t.get("max_tier", 99)):
		return false
	if max_depth >= 0 and (max_depth < int(t.get("record_min", 0)) or max_depth > int(t.get("record_max", 1 << 30))):
		return false
	var need := String(t.get("requires_seen", ""))
	return need == "" or bool(seen.get(need, false))


## kind: "daily"|"weekly"; period — номер суток или недели; seen — {event: true}.
## cfg — свой набор слотов вместо quests.json → kind (так соседняя подсистема —
## стрик новичка — строит задания тем же генератором и шаблонами; поле
## template_kind говорит, шаблоны какого вида ей годятся).
##
## Слот с пулом берёт шаблон из пула; пул пуст на этой ступени (или всё уже
## занято) — запасной путь: любой подходящий шаблон вида, сначала из ещё не
## занятой группы. Так набор всегда полный, если шаблонов хватает.
static func generate(kind: String, period: int, world_seed: int, max_depth: int, seen: Dictionary,
		cfg: Dictionary = {}) -> Array:
	if cfg.is_empty():
		cfg = MetaData.quests().get(kind, {})
	var tkind := String(cfg.get("template_kind", kind))
	var tier := tier_for(max_depth)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_seed("%s|%d|%d" % [kind, period, world_seed])
	var out: Array = []
	var used := {}
	var used_groups := {}
	var slots: Array = cfg.get("slots", [])
	if slots.is_empty():
		slots = [{}]
	for i in range(count_of(cfg)):
		var slot: Dictionary = slots[mini(i, slots.size() - 1)]
		var pick := _pick_for_slot(slot, tkind, tier, max_depth, seen, used, used_groups, rng)
		if pick.is_empty():
			continue
		used[pick["id"]] = true
		used_groups[pick["group"]] = true
		out.append(_make(kind, period, i, pick, slot, cfg, tier, max_depth))
	return out


static func _pick_for_slot(slot: Dictionary, tkind: String, tier: int, max_depth: int, seen: Dictionary,
		used: Dictionary, used_groups: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pick := {}
	if slot.has("pool"):
		pick = _pick_from_pool(slot, tkind, tier, max_depth, seen, used, rng)
	if pick.is_empty() and bool(slot.get("fallback", true)):
		pick = _pick_any(tkind, tier, max_depth, seen, used, used_groups, rng)
	return pick


## Запасной путь и слоты без пула: любой подходящий шаблон вида, кроме
## «только из пула» (pool_only: их место — свой слот), сначала из новой группы.
static func _pick_any(tkind: String, tier: int, max_depth: int, seen: Dictionary, used: Dictionary,
		used_groups: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var fresh: Array = []
	var any: Array = []
	for t in MetaData.quests().get("templates", []):
		if used.has(t["id"]) or bool(t.get("pool_only", false)) or not _eligible(t, tkind, tier, seen, max_depth):
			continue
		any.append(t)
		if not used_groups.has(t["group"]):
			fresh.append(t)
	var cands := fresh if not fresh.is_empty() else any
	return {} if cands.is_empty() else _weighted(cands, rng)


static func _pool_candidates(slot: Dictionary, kind: String, tier: int, max_depth: int, seen: Dictionary,
		exclude: Dictionary) -> Array:
	var cands: Array = []
	var pool: Dictionary = slot.get("pool", {})
	for tid in pool.keys():
		if exclude.has(tid):
			continue
		var t := MetaData.template(String(tid))
		if t.is_empty() or not _eligible(t, kind, tier, seen, max_depth):
			continue
		var w := float(pool[tid])
		if w > 0.0:
			var c := t.duplicate()
			c["weight"] = w
			cands.append(c)
	return cands


static func _pick_from_pool(slot: Dictionary, kind: String, tier: int, max_depth: int, seen: Dictionary,
		exclude: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cands := _pool_candidates(slot, kind, tier, max_depth, seen, exclude)
	if cands.is_empty():
		return {}
	return _weighted(cands, rng)


## Есть ли чем заменить задание слота: другой шаблон пула (или запасного пути),
## которого нет в наборе дня. Слот с reroll: false (миссия владельца «посмотри
## рекламу») не заменяется.
static func can_reroll(q: Dictionary, day_set: Array, seen: Dictionary, max_depth: int = -1) -> bool:
	var slot := _slot_cfg(q)
	if not bool(slot.get("reroll", true)):
		return false
	var kind := String(q["kind"])
	var tier := int(q["tier"])
	var used := _tpls_of(day_set)
	if not _pool_candidates(slot, kind, tier, max_depth, seen, used).is_empty():
		return true
	if not bool(slot.get("fallback", true)):
		return false
	for t in MetaData.quests().get("templates", []):
		if not used.has(t["id"]) and not bool(t.get("pool_only", false)) and _eligible(t, kind, tier, seen, max_depth):
			return true
	return false


## Замена задания: другой шаблон того же слота, детерминированно от (сутки, сид,
## слот, номер замены) — переустановка не даёт «перебросить» ещё раз.
static func reroll(q: Dictionary, day_set: Array, world_seed: int, max_depth: int, seen: Dictionary, n: int) -> Dictionary:
	var kind := String(q["kind"])
	var day := int(String(q["id"]).split(":")[1])
	var slot_idx := int(q["slot"])
	var slot := _slot_cfg(q)
	if not bool(slot.get("reroll", true)):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_seed("%s|%d|%d|reroll|%d|%d" % [kind, day, world_seed, slot_idx, n])
	var tier := int(q["tier"])
	var used := _tpls_of(day_set)
	var pick := _pick_for_slot(slot, kind, tier, max_depth, seen, used, _groups_of(day_set), rng)
	if pick.is_empty():
		return {}
	var cfg: Dictionary = MetaData.quests()[kind]
	var nq := _make(kind, day, slot_idx, pick, slot, cfg, tier, max_depth)
	nq["id"] = "%s:%d:%d:r%d" % [kind, day, slot_idx, n]
	return nq


static func _slot_cfg(q: Dictionary) -> Dictionary:
	var slots: Array = MetaData.quests().get(String(q["kind"]), {}).get("slots", [])
	var i := int(q.get("slot", 0))
	return slots[i] if i >= 0 and i < slots.size() else {}


static func _tpls_of(day_set: Array) -> Dictionary:
	var out := {}
	for q in day_set:
		out[String(q["tpl"])] = true
	return out


static func _groups_of(day_set: Array) -> Dictionary:
	var out := {}
	for q in day_set:
		out[String(MetaData.template(String(q["tpl"])).get("group", ""))] = true
	return out


static func _weighted(cands: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for t in cands:
		total += float(t.get("weight", 1.0))
	var r := rng.randf() * total
	for t in cands:
		r -= float(t.get("weight", 1.0))
		if r <= 0.0:
			return t
	return cands[cands.size() - 1]


static func _make(kind: String, period: int, slot_idx: int, t: Dictionary, slot: Dictionary,
		cfg: Dictionary, tier: int, max_depth: int) -> Dictionary:
	var tkind := String(cfg.get("template_kind", kind))
	var fixed: Dictionary = t.get("fixed_target", {})
	var target := 1
	if fixed.has(tkind):
		# Цель задана словами (владелец: «посмотри рекламу 5 раз», «25 раз»): ни
		# ступень, ни масштаб слота её не трогают.
		target = maxi(1, int(num(fixed[tkind], 1)))
	else:
		var targets: Array = t["targets"]
		var base_target := float(targets[clampi(tier, 0, targets.size() - 1)])
		var scale := float(slot.get("scale", 1.0))
		if tkind == "weekly":
			scale *= float(t.get("weekly_scale", cfg.get("default_scale", 6)))
		# Крошечные цели (1–3) не масштабируем дробью: «0.6 алмаза» не бывает.
		target = int(round(base_target * scale)) if base_target > 3.0 or scale > 1.0 else int(base_target)
		target = maxi(1, target)

	var filter: Dictionary = (t.get("filter", {}) as Dictionary).duplicate(true)
	var by_tier: Dictionary = t.get("filter_by_tier", {})
	for k in by_tier.keys():
		var arr: Array = by_tier[k]
		filter[k] = int(arr[clampi(tier, 0, arr.size() - 1)])

	var rw: Dictionary = cfg["reward"]
	var coins_t: Array = rw["coins"]
	var xp_t: Array = rw["xp"]
	var rmult := float(slot.get("reward", 1.0))
	var reward := {
		"coins": _round5(float(coins_t[clampi(tier, 0, coins_t.size() - 1)]) * rmult),
		"xp": _round5(float(xp_t[clampi(tier, 0, xp_t.size() - 1)]) * rmult),
	}
	if int(slot.get("dollars", 0)) > 0:
		reward["dollars"] = int(slot["dollars"])

	return {
		"id": "%s:%d:%d" % [kind, period, slot_idx], "tpl": t["id"], "kind": kind, "slot": slot_idx,
		"event": (t["event"] as Array).duplicate() if t["event"] is Array else t["event"], "filter": filter, "sum": t.get("sum", ""), "mode": t.get("mode", ""),
		"target": target, "progress": 0, "base": max_depth, "tier": tier, "glyph": t.get("glyph", "dig"),
		"reward": reward, "points": int(num(cfg.get("points"), 1)), "claimed": false,
	}


static func _round5(v: float) -> int:
	return maxi(5, int(round(v / 5.0)) * 5)


## Заголовок задания для подсказки (из шаблона и параметров задания).
static func title(q: Dictionary) -> String:
	var t := MetaData.template(String(q["tpl"]))
	var s := String(t.get("name_ru", q["tpl"]))
	s = s.replace("{n}", str(int(q["target"])))
	var f: Dictionary = q.get("filter", {})
	for k in f.keys():
		s = s.replace("{%s}" % k, str(f[k]))
	if s.contains("{item}"):
		var it = f.get("item", "")
		s = s.replace("{item}", String(Balance.get_mineral(String(it)).get("name_ru", it)))
	return s


static func description(q: Dictionary) -> String:
	return String(MetaData.template(String(q["tpl"])).get("desc_ru", ""))
