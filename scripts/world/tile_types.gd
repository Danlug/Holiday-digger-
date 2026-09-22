class_name TileTypes
extends RefCounted
## Реестр всех типов клеток мира и их свойств (инструмент, фиксация).
## Не автозагрузка — используется как глобальный класс через class_name,
## чтобы не занимать слот в project.godot (им управляет оркестратор).

enum Type {
	EMPTY = 0,          # пустота (воздух), проходима, копать нечего
	DIRT,                # земля
	STONE,               # камень — помеха, не ресурс
	FOUNDATION,          # фундамент на уровне 5, сплошной, зафиксирован пока цел
	STAIRCASE,           # нерушимая лестница у дома, не копается вообще
	REINFORCED,          # железобетон: стены тоннеля Роберта, не копается вообще

	# --- руды и полезные ископаемые (раздел 4 ГДД) ---
	IRON_ORE,            # железо
	LEAD_ORE,            # свинец
	SILVER_ORE,          # серебро
	COPPER_ORE,          # медь
	ALUMINIUM_ORE,       # алюминий
	GOLD_ORE,            # золото
	DIAMOND,             # алмаз
	NICKEL_ORE,          # никель
	PEAT,                # торф
	COAL,                # каменный уголь
	PLATINUM_ORE,        # платина
	TITANIUM_ORE,        # титан
	LITHIUM_ORE,         # литий
	MERCURY_ORE,         # ртуть
	URANIUM_ORE,         # уран
	RUBY,                # рубин
	EMERALD,             # изумруд
	GEOCRYSTAL,          # геотермальный кристалл
	ANCIENT_METAL,       # древний металл
	OBSIDIAN,            # обсидиан
	HELLSTONE,           # адский камень
	DARK_MATTER,         # чёрная материя
	UNIVERSALIUM,        # вселениум
	ANGEL_STONE,         # ангельский камень
	DIVINE_HEART,        # божественное сердце
	SCRAP_METAL,         # металлолом
}

## Свойства клетки: можно ли копать лопатой/киркой и фиксирована ли она
## (фиксированные клетки не участвуют в событиях сброса, см. collapse.gd).
class Props:
	var shovel: bool
	var pickaxe: bool
	var fixed: bool
	func _init(p_shovel: bool, p_pickaxe: bool, p_fixed: bool) -> void:
		shovel = p_shovel
		pickaxe = p_pickaxe
		fixed = p_fixed

static var _props: Dictionary = _build_props()

static func _build_props() -> Dictionary:
	var d := {}
	d[Type.EMPTY] = Props.new(false, false, false)
	d[Type.DIRT] = Props.new(true, true, false)
	d[Type.STONE] = Props.new(false, true, false)
	# фундамент: пока цел — только кирка, фиксирован; после пролома
	# теряет флаг "fixed" на уровне мира (см. world_gen._is_permanent_feature)
	d[Type.FOUNDATION] = Props.new(false, true, true)
	# лестница вообще не копается никаким инструментом
	d[Type.STAIRCASE] = Props.new(false, false, true)
	# железобетон стен тоннеля Роберта: не копается ничем и никогда — в
	# отличие от фундамента, который кирка всё-таки пробивает. Потому и
	# отдельный тип, а не FOUNDATION: тоннель обязан остаться колодцем
	# шириной ровно в одну клетку, иначе огород вскрывается сбоку.
	d[Type.REINFORCED] = Props.new(false, false, true)

	# золото и камень лопата не берёт (раздел 5 ГДД) — то же относится
	# ко всем рудам: они вморожены в породу, нужна кирка
	d[Type.IRON_ORE] = Props.new(false, true, false)
	d[Type.LEAD_ORE] = Props.new(false, true, false)
	d[Type.SILVER_ORE] = Props.new(false, true, false)
	d[Type.COPPER_ORE] = Props.new(false, true, false)
	d[Type.ALUMINIUM_ORE] = Props.new(false, true, false)
	d[Type.GOLD_ORE] = Props.new(false, true, false)
	d[Type.DIAMOND] = Props.new(false, true, false)
	d[Type.NICKEL_ORE] = Props.new(false, true, false)
	# торф мягкий, органический — берётся и лопатой (предположение,
	# в ГДД инструмент для торфа не указан явно)
	d[Type.PEAT] = Props.new(true, true, false)
	d[Type.COAL] = Props.new(false, true, false)
	d[Type.PLATINUM_ORE] = Props.new(false, true, false)
	d[Type.TITANIUM_ORE] = Props.new(false, true, false)
	d[Type.LITHIUM_ORE] = Props.new(false, true, false)
	d[Type.MERCURY_ORE] = Props.new(false, true, false)
	d[Type.URANIUM_ORE] = Props.new(false, true, false)
	d[Type.RUBY] = Props.new(false, true, false)
	d[Type.EMERALD] = Props.new(false, true, false)
	d[Type.GEOCRYSTAL] = Props.new(false, true, false)
	d[Type.ANCIENT_METAL] = Props.new(false, true, false)
	d[Type.OBSIDIAN] = Props.new(false, true, false)
	d[Type.HELLSTONE] = Props.new(false, true, false)
	d[Type.DARK_MATTER] = Props.new(false, true, false)
	d[Type.UNIVERSALIUM] = Props.new(false, true, false)
	d[Type.ANGEL_STONE] = Props.new(false, true, false)
	d[Type.DIVINE_HEART] = Props.new(false, true, false)
	# металлолом — поверхностный мусор, предположительно берётся лопатой
	# (в ГДД явно не указано, см. финальный отчёт)
	d[Type.SCRAP_METAL] = Props.new(true, true, false)
	return d

static func can_dig_with_shovel(type: Type) -> bool:
	return _props[type].shovel

static func can_dig_with_pickaxe(type: Type) -> bool:
	return _props[type].pickaxe

static func is_diggable(type: Type) -> bool:
	return _props[type].shovel or _props[type].pickaxe

## Фиксация по умолчанию для типа клетки (см. также world_gen._is_permanent_feature,
## которая учитывает ещё и геометрию — торфяной пласт 450-455 и т.п.)
static func is_fixed_by_type(type: Type) -> bool:
	return _props[type].fixed

## Имя типа для отладки/логов теста.
static func type_name(type: Type) -> String:
	return Type.keys()[type]

## Является ли клетка рудой/ценным ресурсом (не земля, не камень, не пустота,
## не служебные типы). Опирается на порядок enum: все руды объявлены одним
## блоком после служебных типов (EMPTY..REINFORCED).
static func is_ore(type: Type) -> bool:
	return type >= Type.IRON_ORE

## Тип по имени ключа enum (используется world_gen.gd при чтении world_layers.json,
## где типы заданы строками). Enum в GDScript ведёт себя как Dictionary,
## поэтому .get() с запасным значением работает и защищает от опечатки в JSON.
static func from_name(name: String, fallback: Type = Type.STONE) -> Type:
	return Type.get(name, fallback)
