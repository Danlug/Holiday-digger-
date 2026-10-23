extends SceneTree
## Замер экономики породы на настоящем генераторе: доля клеток по рудам, вес и
## цена «на клетку», стоимость полного рюкзака. Ничего не пишет на диск.
##   godot --headless --path . --script res://tools/world_economy.gd

const BANDS := [30, 100, 160, 320, 500, 900, 1200, 1600, 2000, 2600, 3000, 3800, 4200, 5000, 6500, 8000, 9800]
const HALF := 25
const SEEDS := 12
const BACKPACK_KG := 60.0

var _price := {}
var _kg := {}


func _unwrap(v):
	if typeof(v) == TYPE_DICTIONARY and v.has("value"):
		return v["value"]
	return v


func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/minerals.json"))
	for m in data["minerals"]:
		var p = _unwrap(m.get("price_coins", 0))
		_price[m["id"]] = float(p) if p != null else 0.0
		_kg[m["id"]] = float(_unwrap(m.get("weight_kg", 0.0)))
	print("y;ore%;void%;stone%;kg/cell;coins/cell;coins/kg;cells_per_pack")
	for yc in BANDS:
		var counts := {}
		var total := 0
		var voids := 0
		var stones := 0
		for s in range(SEEDS):
			var w := WorldGen.new(s * 7919 + 17)
			for y in range(maxi(6, yc - HALF), yc + HALF + 1):
				for x in range(WorldGen.WIDTH):
					var t := w.get_tile(x, y)
					total += 1
					if t == TileTypes.Type.EMPTY:
						voids += 1
					elif t == TileTypes.Type.STONE:
						stones += 1
					elif TileTypes.is_ore(t):
						counts[t] = int(counts.get(t, 0)) + 1
		var ore := 0
		var kg := 0.0
		var coins := 0.0
		for t in counts.keys():
			var mid := MineralMap.mineral_id_for(t)
			ore += counts[t]
			kg += counts[t] * float(_kg.get(mid, 0.0))
			coins += counts[t] * float(_price.get(mid, 0.0))
		var n := float(total)
		print("%d;%.1f;%.1f;%.1f;%.3f;%.2f;%.1f;%.0f" % [yc, 100.0 * ore / n, 100.0 * voids / n,
				100.0 * stones / n, kg / n, coins / n, coins / maxf(kg, 0.001), BACKPACK_KG / maxf(kg / n, 0.0001)])
		var parts := []
		var keys := counts.keys()
		keys.sort_custom(func(a, b): return counts[a] > counts[b])
		for t in keys:
			var mid := MineralMap.mineral_id_for(t)
			parts.append("%s %.2f%%" % [mid, 100.0 * counts[t] / n])
		print("    ", ", ".join(parts))
	quit(0)
