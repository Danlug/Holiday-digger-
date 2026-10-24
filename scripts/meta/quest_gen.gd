class_name QuestGen
extends RefCounted
## Генератор заданий. Чистые функции: один и тот же набор (период, сид мира,
## ступень игрока, виденные события) всегда даёт один и тот же список заданий —
## перезапуск игры или переустановка не «перебрасывает» задания дня.
##
## Задание — словарь (кладётся в сейв как есть):
##   id, tpl (шаблон), kind (daily|weekly), slot, event, filter, sum, mode,
##   target, progress, base (рекорд глубины для mode:delta), tier, glyph,
##   reward{coins,dollars,xp}, points, claimed

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


## Шаблон годится игроку этой ступени: вид задания, диапазон ступеней и
## «событие уже было на шине» (requires_seen).
static func _eligible(t: Dictionary, kind: String, tier: int, seen: Dictionary) -> bool:
	if not (t.get("kinds", []) as Array).has(kind):
		return false
	if tier < int(t.get("min_tier", 0)) or tier > int(t.get("max_tier", 99)):
		return false
	var need := String(t.get("requires_seen", ""))
	return need == "" or bool(seen.get(need, false))


## kind: "daily"|"weekly"; period — номер суток или недели; seen — {event: true}.
static func generate(kind: String, period: int, world_seed: int, max_depth: int, seen: Dictionary) -> Array:
	var q: Dictionary = MetaData.quests()
	var cfg: Dictionary = q[kind]
	var tier := tier_for(max_depth)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_seed("%s|%d|%d" % [kind, period, world_seed])
	if _has_pools(cfg):
		return _generate_slots(kind, period, cfg, tier, max_depth, seen, rng)

	var pool: Array = []
	for t in q["templates"]:
		if _eligible(t, kind, tier, seen):
			pool.append(t)

	var out: Array = []
	var used_groups := {}
	var used_ids := {}
	var slots: Array = cfg["slots"]
	for i in range(int(cfg["count"])):
		var cands: Array = []
		for t in pool:
			if not used_groups.has(t["group"]) and not used_ids.has(t["id"]):
				cands.append(t)
		if cands.is_empty():
			for t in pool:
				if not used_ids.has(t["id"]):
					cands.append(t)
		if cands.is_empty():
			break
		var pick: Dictionary = _weighted(cands, rng)
		used_groups[pick["group"]] = true
		used_ids[pick["id"]] = true
		out.append(_make(kind, period, i, pick, slots[mini(i, slots.size() - 1)], cfg, tier, max_depth))
	return out


static func _has_pools(cfg: Dictionary) -> bool:
	for sl in cfg.get("slots", []):
		if (sl as Dictionary).has("pool"):
			return true
	return false


## Ежедневные — по слотам (копка, продажа, трата, забота, «охота»): у каждого
## слота свой пул шаблонов с весами, так в наборе дня всегда есть копка и нет
## двух заданий об одном.
static func _generate_slots(kind: String, period: int, cfg: Dictionary, tier: int, max_depth: int,
		seen: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var used := {}
	var slots: Array = cfg["slots"]
	for i in range(mini(int(cfg.get("count", slots.size())), slots.size())):
		var slot: Dictionary = slots[i]
		var pick := _pick_from_pool(slot, kind, tier, seen, used, rng)
		if pick.is_empty():
			continue
		used[pick["id"]] = true
		out.append(_make(kind, period, i, pick, slot, cfg, tier, max_depth))
	return out


static func _pool_candidates(slot: Dictionary, kind: String, tier: int, seen: Dictionary, exclude: Dictionary) -> Array:
	var cands: Array = []
	var pool: Dictionary = slot.get("pool", {})
	for tid in pool.keys():
		if exclude.has(tid):
			continue
		var t := MetaData.template(String(tid))
		if t.is_empty() or not _eligible(t, kind, tier, seen):
			continue
		var w := float(pool[tid])
		if w > 0.0:
			var c := t.duplicate()
			c["weight"] = w
			cands.append(c)
	return cands


static func _pick_from_pool(slot: Dictionary, kind: String, tier: int, seen: Dictionary,
		exclude: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cands := _pool_candidates(slot, kind, tier, seen, exclude)
	if cands.is_empty():
		return {}
	return _weighted(cands, rng)


## Есть ли чем заменить задание слота (другой шаблон пула, которого нет в наборе дня).
static func can_reroll(q: Dictionary, day_set: Array, seen: Dictionary) -> bool:
	return not _pool_candidates(_slot_cfg(q), String(q["kind"]), int(q["tier"]), seen, _tpls_of(day_set)).is_empty()


## Замена задания: другой шаблон того же слота, детерминированно от (сутки, сид,
## слот, номер замены) — переустановка не даёт «перебросить» ещё раз.
static func reroll(q: Dictionary, day_set: Array, world_seed: int, max_depth: int, seen: Dictionary, n: int) -> Dictionary:
	var kind := String(q["kind"])
	var day := int(String(q["id"]).split(":")[1])
	var slot_idx := int(q["slot"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_seed("%s|%d|%d|reroll|%d|%d" % [kind, day, world_seed, slot_idx, n])
	var tier := int(q["tier"])
	var pick := _pick_from_pool(_slot_cfg(q), kind, tier, seen, _tpls_of(day_set), rng)
	if pick.is_empty():
		return {}
	var cfg: Dictionary = MetaData.quests()[kind]
	var nq := _make(kind, day, slot_idx, pick, _slot_cfg(q), cfg, tier, max_depth)
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
	var targets: Array = t["targets"]
	var base_target := float(targets[clampi(tier, 0, targets.size() - 1)])
	var scale := float(slot["scale"])
	if kind == "weekly":
		scale *= float(t.get("weekly_scale", cfg.get("default_scale", 6)))
	# Крошечные цели (1–3) не масштабируем дробью: «0.6 алмаза» не бывает.
	var target := int(round(base_target * scale)) if base_target > 3.0 or scale > 1.0 else int(base_target)
	target = maxi(1, target)

	var filter: Dictionary = (t.get("filter", {}) as Dictionary).duplicate(true)
	var by_tier: Dictionary = t.get("filter_by_tier", {})
	for k in by_tier.keys():
		var arr: Array = by_tier[k]
		filter[k] = int(arr[clampi(tier, 0, arr.size() - 1)])

	var rw: Dictionary = cfg["reward"]
	var coins_t: Array = rw["coins"]
	var xp_t: Array = rw["xp"]
	var rmult := float(slot["reward"])
	var reward := {
		"coins": _round5(float(coins_t[clampi(tier, 0, coins_t.size() - 1)]) * rmult),
		"xp": _round5(float(xp_t[clampi(tier, 0, xp_t.size() - 1)]) * rmult),
	}
	if int(slot.get("dollars", 0)) > 0:
		reward["dollars"] = int(slot["dollars"])

	return {
		"id": "%s:%d:%d" % [kind, period, slot_idx], "tpl": t["id"], "kind": kind, "slot": slot_idx,
		"event": t["event"], "filter": filter, "sum": t.get("sum", ""), "mode": t.get("mode", ""),
		"target": target, "progress": 0, "base": max_depth, "tier": tier, "glyph": t.get("glyph", "dig"),
		"reward": reward, "points": int(cfg.get("points", 1)), "claimed": false,
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
