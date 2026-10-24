extends Node
## Темп для ежедневных заданий: сколько клеток в минуту копает игрок каждой
## ступени (tier_by_max_depth из data/quests.json) и сколько монет приносит
## продажа выкопанного. По этим числам подобраны цели заданий дня (ГДД §17.2).
##
##   godot --headless --path . res://tools/sim_daily.tscn [-- --seeds=4 --activity=0.6]
##
## Считает на настоящем генераторе (WorldGen) и настоящих числах (Balance):
##  * пояс ступени — глубины [порог ступени, порог следующей); у последней — до 4000;
##  * игрок копает ряды пояса целиком (как «серпантин» в sim_economy.gd);
##  * время клетки — как в sim_economy: секунды минерала / (кирка × общий множитель) ×
##    0.96^«Скорость копки», плюс шаг 0.24 с; кирка и ступень навыка — типичные для пояса
##    по прогонам sim_economy (ржавая → железная → титановая → платиновая → алмазная → обсидиановая);
##  * activity — доля «чистой копки» в игровом времени живого игрока (подъёмы, продажа,
##    еда, меню, сюжет); 0.6 — ориентир, sim_economy считает 1.0 без меню и ошибок.

const STEP_S := 0.24
const TOOLS := ["rusty_pickaxe", "iron_pickaxe", "titanium_pickaxe", "platinum_pickaxe", "diamond_pickaxe", "obsidian_pickaxe"]
const SKILL := [0, 3, 6, 9, 12, 15]
const LAST_BAND_END := 4000
const ROWS_PER_BAND := 60

var _opt := {"seeds": 4, "activity": 0.6}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_opt[kv[0]] = kv[1]
	var th: Array = MetaData.quests().get("tier_by_max_depth", [0])
	var activity := float(_opt["activity"])
	print("=== sim_daily: сидов %d, activity %.2f ===" % [int(_opt["seeds"]), activity])
	print("%-4s %-11s %7s %7s %7s %7s %8s %8s %9s" % ["ст.", "пояс", "с/кл", "кл/мин", "руда%", "камень%", "мон/кл", "мон/мин", "мин/500кл"])
	for t in range(th.size()):
		var y0 := maxi(6, int(th[t]))
		var y1 := int(th[t + 1]) if t + 1 < th.size() else LAST_BAND_END
		var acc := {"cells": 0, "secs": 0.0, "loot": 0, "stone": 0, "coins": 0, "m": {}}
		for s in range(int(_opt["seeds"])):
			_band(WorldGen.new(1000 + s * 7919), y0, y1, t, acc)
		var n := maxi(1, int(acc["cells"]))
		var sec_cell: float = float(acc["secs"]) / n + STEP_S
		var cpm := 60.0 / sec_cell * activity
		var coins_cell := float(acc["coins"]) / n
		print("%-4d %-11s %7.2f %7.1f %7.1f %7.1f %8.2f %8.0f %9.0f" % [t, "%d-%d" % [y0, y1], sec_cell, cpm,
			100.0 * float(acc["loot"]) / n, 100.0 * float(acc["stone"]) / n, coins_cell, coins_cell * cpm, 500.0 / cpm])
		var dens: Array = []
		for id in acc["m"].keys():
			dens.append([float(acc["m"][id]) / n, id])
		dens.sort()
		dens.reverse()
		var parts: Array[String] = []
		for e in dens:
			if float(e[0]) >= 0.002:
				parts.append("%s %.1f%%" % [e[1], 100.0 * float(e[0])])
		print("     руды: ", ", ".join(parts))
	get_tree().quit(0)


func _band(world: WorldGen, y0: int, y1: int, tier: int, acc: Dictionary) -> void:
	var step := maxi(1, int(float(y1 - y0) / float(ROWS_PER_BAND)))
	for y in range(y0, y1, step):
		for x in range(WorldGen.WIDTH):
			var tile := world.get_tile(x, y)
			if tile == TileTypes.Type.EMPTY:
				continue
			acc["cells"] += 1
			acc["secs"] += _cell_seconds(tile, y, tier)
			if tile == TileTypes.Type.STONE:
				acc["stone"] += 1
			if MineralMap.is_loot(tile):
				acc["loot"] += 1
				var mid := MineralMap.mineral_id_for(tile)
				acc["coins"] += Balance.get_mineral_price(mid)
				acc["m"][mid] = int(acc["m"].get(mid, 0)) + 1


func _cell_seconds(tile: int, y: int, tier: int) -> float:
	var mid := MineralMap.mineral_id_for(tile)
	var base: float = Balance.get_mineral_drill_seconds(mid) if not mid.is_empty() \
		else float(Balance.unwrap(Balance.balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
	var tool: String = TOOLS[clampi(tier, 0, TOOLS.size() - 1)]
	var mult: float = Balance.get_tool_speed_multiplier(tool)
	if tool == "rusty_pickaxe" and y >= 80:
		mult *= float(Balance.unwrap(Balance.get_tool("rusty_pickaxe").get("broken_speed_multiplier", 0.75)))
	var stage: int = SKILL[clampi(tier, 0, SKILL.size() - 1)]
	return maxf(base * pow(0.96, float(stage)) / maxf(mult, 0.01) / Balance.get_global_dig_speed_multiplier(), 0.05)
