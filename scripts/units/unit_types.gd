class_name UnitTypes
extends RefCounted
## The four basic unit types. Specialised variants will be derived from these.
##
## All numbers are first-pass values to tune once movement and combat exist.
## Attack values are keyed by the target's unit type.

enum Type { INFANTRY, ARMOR, AIRCRAFT, NAVAL }
enum Domain { LAND, AIR, SEA }

## Open ground: nowhere to hide, room to manoeuvre.
const OPEN_TERRAIN: Array[int] = [Biomes.Type.PLAINS, Biomes.Type.DESERT, Biomes.Type.TUNDRA]
## Close terrain: cover and short sightlines.
const CLOSE_TERRAIN: Array[int] = [
	Biomes.Type.FOREST, Biomes.Type.JUNGLE, Biomes.Type.MOUNTAINS, Biomes.Type.SWAMP]

const DATA := {
	Type.INFANTRY: {
		"name": "Infantry",
		"role": "Cheap and flexible. Good at holding cities, forests, and mountains, but slow and weak in open terrain against armor.",
		"domain": Domain.LAND,
		## Which Biomes move cost applies ("move_cost_infantry" / "move_cost_vehicle").
		"move_cost_key": "move_cost_infantry",
		"cost": 100,
		"movement": 2,
		"hit_points": 10,
		"vision": 2,
		"attack": {Type.INFANTRY: 4, Type.ARMOR: 2, Type.AIRCRAFT: 1, Type.NAVAL: 0},
		"defense": 4,
		## Infantry dig in: they get the biome's defense bonus, and more in close terrain.
		"uses_cover": true,
		"close_terrain_attack": 2, "close_terrain_defense": 2,
		"open_terrain_attack": 0, "open_terrain_defense": -1,
		"can_hold_territory": true,
		"needs_airbase": false,
		"bombard_range": 0,
		"transport_capacity": 0,
	},
	Type.ARMOR: {
		"name": "Armor",
		"role": "The main attack unit. Strong and fast on open ground, expensive, and vulnerable to aircraft and to infantry in close terrain.",
		"domain": Domain.LAND,
		"move_cost_key": "move_cost_vehicle",
		"cost": 300,
		"movement": 5,
		"hit_points": 12,
		"vision": 2,
		"attack": {Type.INFANTRY: 6, Type.ARMOR: 6, Type.AIRCRAFT: 0, Type.NAVAL: 1},
		"defense": 5,
		"uses_cover": false,
		"close_terrain_attack": -2, "close_terrain_defense": -2,
		"open_terrain_attack": 2, "open_terrain_defense": 1,
		"can_hold_territory": true,
		"needs_airbase": false,
		"bombard_range": 0,
		"transport_capacity": 0,
	},
	Type.AIRCRAFT: {
		"name": "Aircraft",
		"role": "Fast, can reach anywhere, and hits ground and naval units hard. Can't hold territory, and needs airbases.",
		"domain": Domain.AIR,
		"move_cost_key": "",
		"cost": 400,
		"movement": 12,
		"hit_points": 6,
		"vision": 4,
		"attack": {Type.INFANTRY: 5, Type.ARMOR: 7, Type.AIRCRAFT: 5, Type.NAVAL: 6},
		"defense": 2,
		"uses_cover": false,
		"close_terrain_attack": 0, "close_terrain_defense": 0,
		"open_terrain_attack": 0, "open_terrain_defense": 0,
		"can_hold_territory": false,
		"needs_airbase": true,
		"bombard_range": 0,
		"transport_capacity": 0,
	},
	Type.NAVAL: {
		"name": "Naval",
		"role": "Controls the seas, carries or escorts troops overseas, and can bombard coastlines. Useless inland.",
		"domain": Domain.SEA,
		"move_cost_key": "",
		"cost": 500,
		"movement": 6,
		"hit_points": 16,
		"vision": 3,
		"attack": {Type.INFANTRY: 3, Type.ARMOR: 3, Type.AIRCRAFT: 2, Type.NAVAL: 6},
		"defense": 6,
		"uses_cover": false,
		"close_terrain_attack": 0, "close_terrain_defense": 0,
		"open_terrain_attack": 0, "open_terrain_defense": 0,
		"can_hold_territory": false,
		"needs_airbase": false,
		"bombard_range": 2,
		"transport_capacity": 4,
	},
}


static func info(type: int) -> Dictionary:
	return DATA[type]


static func display_name(type: int) -> String:
	return DATA[type]["name"]


static func count() -> int:
	return Type.size()


## Whether a unit of this type may occupy a tile of this biome.
static func can_enter(type: int, biome: int) -> bool:
	return entry_block_reason(type, biome) == ""


## Empty if the unit may occupy the biome, otherwise why not.
static func entry_block_reason(type: int, biome: int) -> String:
	var data: Dictionary = DATA[type]
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


## One-line stat summary for tooltips.
static func summary(type: int) -> String:
	var d: Dictionary = DATA[type]
	var attack: Dictionary = d["attack"]
	var vs: Array[String] = []
	for target in count():
		vs.append("%s %d" % [display_name(target), attack[target]])
	var lines: Array[String] = [
		d["role"], "",
		"Cost %d  |  Movement %d  |  HP %d  |  Defense %d  |  Vision %d" % [
			d["cost"], d["movement"], d["hit_points"], d["defense"], d["vision"]],
		"Attack vs: " + ", ".join(vs),
	]
	if d["bombard_range"] > 0:
		lines.append("Bombards up to %d hexes" % d["bombard_range"])
	if d["transport_capacity"] > 0:
		lines.append("Carries up to %d land units" % d["transport_capacity"])
	if d["needs_airbase"]:
		lines.append("Needs an airbase")
	if not d["can_hold_territory"]:
		lines.append("Cannot hold territory")
	return "\n".join(lines)
