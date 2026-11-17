class_name UnitTypes
extends RefCounted
## The basic unit types. Specialised variants will be derived from these.
##
## "power" is a unit's combat power and also its full hit points: a damaged
## unit fights at its remaining hit points (see Battle). The multipliers below
## scale that power in battle.
##
## "cost" is paid once when the unit is trained and "upkeep" every turn; both
## are {ResourceTypes.Type: amount}. Which building trains a unit is set on the
## building (BuildingTypes "trains"). All numbers are first-pass values.

enum Type { INFANTRY, ARMOR, AIRCRAFT, NAVAL, ARTILLERY }
enum Domain { LAND, AIR, SEA }

## How a unit can join a battle without being on the tile.
enum Support {
	NONE,
	AIRBASE,  ## from one of its side's airbases within that airbase's operating range
	BOMBARD,  ## from a water tile within "bombard_range" of a land battle
}

## Open ground: nowhere to hide, room to manoeuvre.
const OPEN_TERRAIN: Array[int] = [Biomes.Type.PLAINS, Biomes.Type.DESERT, Biomes.Type.TUNDRA]
## Forests, for unit modifiers.
const FOREST_TERRAIN: Array[int] = [Biomes.Type.FOREST, Biomes.Type.JUNGLE]

const DEFAULTS := {
	"name": "",
	"role": "",
	"domain": Domain.LAND,
	## Which Biomes move cost applies ("move_cost_infantry" / "move_cost_vehicle").
	"move_cost_key": "",
	"cost": {},
	"upkeep": {},
	"power": 10,
	"movement": 1,
	"vision": 2,
	## Power multipliers in battle. A city overrides the biome it stands on.
	"city_multiplier": 1.0,
	"biome_multipliers": {},
	"defending_multiplier": 1.0,
	## Fires a free round before the battle that cannot be answered.
	"pre_battle_fire": false,
	"support": Support.NONE,
	"bombard_range": 0,
	"can_hold_territory": true,
	"needs_airbase": false,
	"transport_capacity": 0,
}

const DATA := {
	Type.INFANTRY: {
		"name": "Infantry",
		"role": "Cheap and flexible. Good at holding cities, forests, and mountains, but slow and weak in open terrain against armor.",
		"move_cost_key": "move_cost_infantry",
		"cost": {ResourceTypes.Type.MONEY: 100, ResourceTypes.Type.FOOD: 20, ResourceTypes.Type.PRODUCTION: 10},
		"upkeep": {ResourceTypes.Type.MONEY: 1, ResourceTypes.Type.FOOD: 1},
		"power": 10,
		"movement": 2,
		"city_multiplier": 1.5,
		"biome_multipliers": {
			Biomes.Type.FOREST: 1.5, Biomes.Type.JUNGLE: 1.5, Biomes.Type.MOUNTAINS: 1.5},
	},
	Type.ARMOR: {
		"name": "Armor",
		"role": "The main attack unit. Strong and fast on open ground, expensive, and vulnerable to aircraft and to infantry in close terrain.",
		"move_cost_key": "move_cost_vehicle",
		"cost": {ResourceTypes.Type.MONEY: 300, ResourceTypes.Type.MATERIALS: 40, ResourceTypes.Type.FUEL: 10, ResourceTypes.Type.PRODUCTION: 40},
		"upkeep": {ResourceTypes.Type.MONEY: 2, ResourceTypes.Type.FUEL: 2},
		"power": 20,
		"movement": 5,
		"city_multiplier": 0.75,
		"biome_multipliers": {
			Biomes.Type.PLAINS: 1.5, Biomes.Type.DESERT: 1.5, Biomes.Type.TUNDRA: 1.5},
	},
	Type.AIRCRAFT: {
		"name": "Aircraft",
		"role": "Fast, can reach anywhere, and hits ground and naval units hard. Can't hold territory, and needs airbases.",
		"domain": Domain.AIR,
		"cost": {ResourceTypes.Type.MONEY: 400, ResourceTypes.Type.MATERIALS: 30, ResourceTypes.Type.RARE_EARTHS: 10, ResourceTypes.Type.FUEL: 20, ResourceTypes.Type.PRODUCTION: 50},
		"upkeep": {ResourceTypes.Type.MONEY: 3, ResourceTypes.Type.FUEL: 3},
		"power": 18,
		"movement": 12,
		"vision": 4,
		"support": Support.AIRBASE,
		"can_hold_territory": false,
		"needs_airbase": true,
	},
	Type.NAVAL: {
		"name": "Naval",
		"role": "Controls the seas, carries or escorts troops overseas, and can bombard coastlines. Useless inland.",
		"domain": Domain.SEA,
		"cost": {ResourceTypes.Type.MONEY: 500, ResourceTypes.Type.MATERIALS: 80, ResourceTypes.Type.FUEL: 20, ResourceTypes.Type.PRODUCTION: 80},
		"upkeep": {ResourceTypes.Type.MONEY: 3, ResourceTypes.Type.FUEL: 3},
		"power": 25,
		"movement": 6,
		"vision": 3,
		"support": Support.BOMBARD,
		"bombard_range": 2,
		"can_hold_territory": false,
		"transport_capacity": 4,
	},
	Type.ARTILLERY: {
		"name": "Artillery",
		"role": "Fires a free round before the battle that the enemy cannot answer. Fights at half power when defending.",
		"move_cost_key": "move_cost_vehicle",
		"cost": {ResourceTypes.Type.MONEY: 250, ResourceTypes.Type.MATERIALS: 40, ResourceTypes.Type.FUEL: 5, ResourceTypes.Type.PRODUCTION: 40},
		"upkeep": {ResourceTypes.Type.MONEY: 2, ResourceTypes.Type.FUEL: 1},
		"power": 12,
		"movement": 2,
		"defending_multiplier": 0.5,
		"pre_battle_fire": true,
	},
}

static var _merged := {}


## Full definition of a unit type (DEFAULTS filled in).
static func info(type: int) -> Dictionary:
	if not _merged.has(type):
		var merged := DEFAULTS.duplicate(true)
		merged.merge(DATA[type], true)
		_merged[type] = merged
	return _merged[type]


static func display_name(type: int) -> String:
	return DATA[type]["name"]


static func count() -> int:
	return Type.size()


## Whether a unit of this type may occupy a tile of this biome.
static func can_enter(type: int, biome: int) -> bool:
	return entry_block_reason(type, biome) == ""


## Empty if the unit may occupy the biome, otherwise why not.
static func entry_block_reason(type: int, biome: int) -> String:
	var data := info(type)
	match data["domain"]:
		Domain.AIR:
			return ""
		Domain.SEA:
			if Biomes.is_water(biome):
				return ""
			return "%s units cannot go on land" % data["name"]
		_:
			if Biomes.is_water(biome):
				return "%s cannot enter water" % data["name"]
			if Biomes.info(biome)[data["move_cost_key"]] < 0:
				return "%s is impassable to %s" % [Biomes.display_name(biome), data["name"]]
			return ""


## Power multiplier for fighting on a tile of this biome (or in a city).
static func terrain_multiplier(type: int, biome: int, in_city: bool) -> float:
	var data := info(type)
	if in_city:
		return data["city_multiplier"]
	return data["biome_multipliers"].get(biome, 1.0)


## Multi-line summary for tooltips.
static func summary(type: int) -> String:
	var d := info(type)
	var lines: Array[String] = [
		d["role"], "",
		"Cost: " + ResourceTypes.format_amounts(d["cost"]),
		"Upkeep per turn: " + ResourceTypes.format_amounts(d["upkeep"], "None"),
		"Power / HP %d  |  Movement %d  |  Vision %d" % [d["power"], d["movement"], d["vision"]],
	]
	var mods: Array[String] = []
	if d["city_multiplier"] != 1.0:
		mods.append("x%s in cities" % d["city_multiplier"])
	var by_value := {}
	for biome: int in d["biome_multipliers"]:
		var value: float = d["biome_multipliers"][biome]
		if not by_value.has(value):
			by_value[value] = []
		by_value[value].append(Biomes.display_name(biome).split(" ")[0])
	for value: float in by_value:
		mods.append("x%s in %s" % [value, ", ".join(by_value[value])])
	if d["defending_multiplier"] != 1.0:
		mods.append("x%s when defending" % d["defending_multiplier"])
	if not mods.is_empty():
		lines.append("Power: " + "; ".join(mods))
	if d["pre_battle_fire"]:
		lines.append("Fires a free round before battle")
	if d["support"] == Support.AIRBASE:
		lines.append("Joins battles from an airbase in range")
	if d["support"] == Support.BOMBARD:
		lines.append("Bombards land battles within %d hexes" % d["bombard_range"])
	if d["transport_capacity"] > 0:
		lines.append("Carries up to %d land units" % d["transport_capacity"])
	if not d["can_hold_territory"]:
		lines.append("Cannot hold territory")
	return "\n".join(lines)
