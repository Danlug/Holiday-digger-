class_name MineralMap
extends RefCounted
## Сопоставление TileTypes.Type <-> id минерала в data/minerals.json.
## Отдельный маленький модуль, потому что имена не всегда совпадают
## (например TileTypes.LEAD_ORE — минерал "lead", а не "lead_ore").

static var _tile_to_mineral: Dictionary = {
	TileTypes.Type.DIRT: "earth",
	TileTypes.Type.STONE: "stone",
	TileTypes.Type.SCRAP_METAL: "scrap",
	TileTypes.Type.IRON_ORE: "iron_ore",
	TileTypes.Type.LEAD_ORE: "lead",
	TileTypes.Type.SILVER_ORE: "silver",
	TileTypes.Type.COPPER_ORE: "copper",
	TileTypes.Type.ALUMINIUM_ORE: "aluminium",
	TileTypes.Type.GOLD_ORE: "gold",
	TileTypes.Type.DIAMOND: "diamond",
	TileTypes.Type.NICKEL_ORE: "nickel",
	TileTypes.Type.PEAT: "peat",
	TileTypes.Type.COAL: "coal",
	TileTypes.Type.PLATINUM_ORE: "platinum",
	TileTypes.Type.TITANIUM_ORE: "titanium",
	TileTypes.Type.LITHIUM_ORE: "lithium",
	TileTypes.Type.MERCURY_ORE: "mercury",
	TileTypes.Type.URANIUM_ORE: "uranium",
	TileTypes.Type.RUBY: "ruby",
	TileTypes.Type.EMERALD: "emerald",
	TileTypes.Type.GEOCRYSTAL: "geocrystal",
	TileTypes.Type.ANCIENT_METAL: "ancient_metal",
	TileTypes.Type.OBSIDIAN: "obsidian",
	TileTypes.Type.HELLSTONE: "hellstone",
	TileTypes.Type.DARK_MATTER: "dark_matter",
	TileTypes.Type.UNIVERSALIUM: "universum",
	TileTypes.Type.ANGEL_STONE: "angelstone",
	TileTypes.Type.DIVINE_HEART: "divine_heart",
	# FOUNDATION и STAIRCASE сознательно не отражены — фундамент не лут
	# (капает 0 монет, у него нет статьи в minerals.json), лестница вообще
	# не копается.
}

## Типы, которые не являются добычей (раздел 4 ГДД): капают монеты,
## но не ложатся в рюкзак и не занимают вес.
static var NOT_LOOT: Array = [
	TileTypes.Type.DIRT,
	TileTypes.Type.STONE,
	TileTypes.Type.FOUNDATION,
	TileTypes.Type.STAIRCASE,
	TileTypes.Type.EMPTY,
]

static func mineral_id_for(type: int) -> String:
	return String(_tile_to_mineral.get(type, ""))


## Обратный поиск: id минерала -> тип клетки (для иконки в инвентаре —
## та же текстура, что и у тайла в мире, см. TileArt.texture_for).
static func tile_type_for(id: String) -> int:
	for t in _tile_to_mineral.keys():
		if _tile_to_mineral[t] == id:
			return t
	return -1

static func is_loot(type: int) -> bool:
	return not NOT_LOOT.has(type)
