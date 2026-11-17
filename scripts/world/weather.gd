class_name Weather
extends RefCounted
## Weather definitions: rules text, numeric modifiers and overlay colour.
##
## Distances are in hexes. A max_visibility of -1 means unlimited.

enum Type {
	CLEAR,
	OVERCAST,
	HEAVY_RAIN,
	MUD,
	STORM,
}

const DATA := {
	Type.CLEAR: {
		"name": "Clear",
		"overlay": Color(1, 1, 1, 0.0),
		"movement": "Normal",
		"visibility": "Unlimited",
		"combat": "No modifiers",
		"air": "Full availability",
		"max_visibility": -1,
		"vehicle_mp_penalty": 0, "speed_multiplier": 1.0, "march_allowed": true,
		"ranged_modifier": 0, "long_range_modifier": 0, "melee_modifier": 0,
		"spotter_modifier": 0, "vehicles_bog_on_1": false,
		"air_support": true, "offboard_support": true,
	},
	Type.OVERCAST: {
		"name": "Overcast / Mist",
		"overlay": Color(0.78, 0.8, 0.82, 0.45),
		"movement": "Normal",
		"visibility": "Max 6 hexes",
		"combat": "-1 to long-range attacks",
		"air": "-1 to air/artillery spotters",
		"max_visibility": 6,
		"vehicle_mp_penalty": 0, "speed_multiplier": 1.0, "march_allowed": true,
		"ranged_modifier": 0, "long_range_modifier": -1, "melee_modifier": 0,
		"spotter_modifier": -1, "vehicles_bog_on_1": false,
		"air_support": true, "offboard_support": true,
	},
	Type.HEAVY_RAIN: {
		"name": "Heavy Rain",
		"overlay": Color(0.25, 0.4, 0.75, 0.6),
		"movement": "-1 MP (wheeled/vehicles)",
		"visibility": "Max 4 hexes",
		"combat": "-1 to all ranged attacks",
		"air": "Air support grounded",
		"max_visibility": 4,
		"vehicle_mp_penalty": 1, "speed_multiplier": 1.0, "march_allowed": true,
		"ranged_modifier": -1, "long_range_modifier": 0, "melee_modifier": 0,
		"spotter_modifier": 0, "vehicles_bog_on_1": false,
		"air_support": false, "offboard_support": true,
	},
	Type.MUD: {
		"name": "Mud / Deep Snow",
		"overlay": Color(0.45, 0.3, 0.15, 0.6),
		"movement": "Half speed (infantry & vehicles)",
		"visibility": "Max 4 hexes",
		"combat": "-1 to ranged; vehicles risk bogging on a 1",
		"air": "Air support grounded",
		"max_visibility": 4,
		"vehicle_mp_penalty": 0, "speed_multiplier": 0.5, "march_allowed": true,
		"ranged_modifier": -1, "long_range_modifier": 0, "melee_modifier": 0,
		"spotter_modifier": 0, "vehicles_bog_on_1": true,
		"air_support": false, "offboard_support": true,
	},
	Type.STORM: {
		"name": "Storm / Blizzard",
		"overlay": Color(0.55, 0.15, 0.65, 0.7),
		"movement": "Half speed; no march/dash moves",
		"visibility": "Max 2 hexes",
		"combat": "-2 to ranged; -1 to melee",
		"air": "All air & off-board support disabled",
		"max_visibility": 2,
		"vehicle_mp_penalty": 0, "speed_multiplier": 0.5, "march_allowed": false,
		"ranged_modifier": -2, "long_range_modifier": 0, "melee_modifier": -1,
		"spotter_modifier": 0, "vehicles_bog_on_1": false,
		"air_support": false, "offboard_support": false,
	},
}

## Below this Planet.temperature, rain falls as snow and mud is deep snow.
const FREEZING := 0.3


static func info(type: int) -> Dictionary:
	return DATA[type]


static func overlay_color(type: int) -> Color:
	return DATA[type]["overlay"]


static func count() -> int:
	return Type.size()


## Name of the condition as it appears on a particular tile, e.g. a storm is a
## blizzard where it is freezing and a sandstorm in the desert. Rules are the same.
static func local_name(type: int, biome: int, temperature: float) -> String:
	var freezing := temperature < FREEZING
	var water := Biomes.is_water(biome)
	match type:
		Type.OVERCAST:
			return "Mist" if biome in [Biomes.Type.SWAMP, Biomes.Type.JUNGLE] else "Overcast"
		Type.HEAVY_RAIN:
			return "Heavy Snow" if freezing else "Heavy Rain"
		Type.MUD:
			return "Deep Snow" if freezing else "Mud"
		Type.STORM:
			if freezing:
				return "Blizzard"
			if biome == Biomes.Type.DESERT:
				return "Sandstorm"
			return "Storm"
	return DATA[type]["name"]
