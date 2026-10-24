extends SceneTree
## Выгружает вывод настоящего генератора в JSON для веб-превью.
## Веб-демка не повторяет алгоритм, а рисует то, что сгенерировал Godot —
## иначе появилась бы вторая реализация, расходящаяся с игрой.

const DEPTH := 400
const OUT := "res://web/world_dump.json"

func _init() -> void:
	var w := WorldGen.new(20260915)
	var names := TileTypes.Type.keys()
	var grid := PackedInt32Array()
	grid.resize(DEPTH * WorldGen.WIDTH)
	var i := 0
	for y in range(1, DEPTH + 1):
		for x in range(WorldGen.WIDTH):
			grid[i] = w.get_tile(x, y)
			i += 1
	var props := {}
	for t in range(names.size()):
		props[str(t)] = {
			"name": names[t],
			"shovel": TileTypes.can_dig_with_shovel(t),
			"pickaxe": TileTypes.can_dig_with_pickaxe(t),
		}
	var out := {
		"width": WorldGen.WIDTH,
		"depth": DEPTH,
		"seed": w.world_seed,
		"house_x_max": WorldGen.HOUSE_X_MAX,
		"garden_x_min": WorldGen.GARDEN_X_MIN,
		"tile_names": names,
		"tile_props": props,
		"grid": grid,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("записано клеток: ", grid.size())
	quit()
