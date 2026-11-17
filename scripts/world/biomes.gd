class_name Biomes
extends RefCounted
## Biome definitions: display colour, rules text and numeric gameplay stats.
##
## The numeric stats are first-pass values for when units are added; tune them
## freely. A move cost of -1 means impassable.

enum Type {
	DEEP_OCEAN,
	SHALLOW_WATER,
	PLAINS,
	FOREST,
	JUNGLE,
	DESERT,
	MOUNTAINS,
	SWAMP,
	TUNDRA,
}

const DATA := {
	Type.DEEP_OCEAN: {
		"name": "Deep Ocean",
		"color": Color("1c3d6e"),
		"movement": "Impassable to land units.",
		"combat": "Open water. No cover.",
		"strategic": "Separates continents.",
		"move_cost_infantry": -1, "move_cost_vehicle": -1,
		"defense": 0, "vision": 0, "blocks_sight": false, "attrition": 0,
	},
	Type.SHALLOW_WATER: {
		"name": "Shallow Water",
		"color": Color("3a74b0"),
		"movement": "Impassable to land units.",
		"combat": "Open water. No cover.",
		"strategic": "Coastal shelf around landmasses.",
		"move_cost_infantry": -1, "move_cost_vehicle": -1,
		"defense": 0, "vision": 0, "blocks_sight": false, "attrition": 0,
	},
	Type.PLAINS: {
		"name": "Plains & Grasslands",
		"color": Color("9cc463"),
		"movement": "Fast movement for all units. Ideal for heavy vehicles and cavalry.",
		"combat": "Clear line-of-sight. Minimal cover for infantry.",
		"strategic": "High-speed maneuver warfare and decisive open-field battles.",
		"move_cost_infantry": 1, "move_cost_vehicle": 1,
		"defense": 0, "vision": 1, "blocks_sight": false, "attrition": 0,
	},
	Type.FOREST: {
		"name": "Temperate & Boreal Forest",
		"color": Color("3b7a3a"),
		"movement": "Slows heavy vehicles and artillery. Passable for light infantry.",
		"combat": "Blocks line-of-sight. Grants high defensive cover and ambush bonuses.",
		"strategic": "Defensive strongholds, guerrilla tactics, and infantry-dominated zones.",
		"move_cost_infantry": 1, "move_cost_vehicle": 2,
		"defense": 2, "vision": -1, "blocks_sight": true, "attrition": 0,
	},
	Type.JUNGLE: {
		"name": "Jungle & Rainforest",
		"color": Color("1a5c3a"),
		"movement": "Severely restricts heavy armor and supply lines. High attrition risk.",
		"combat": "Extremely short sightlines. Heavy concealment and close-quarters combat.",
		"strategic": "Chokepoints that neutralize technological or armored superiority.",
		"move_cost_infantry": 2, "move_cost_vehicle": 4,
		"defense": 2, "vision": -2, "blocks_sight": true, "attrition": 2,
	},
	Type.DESERT: {
		"name": "Desert & Arid Scrub",
		"color": Color("e2c98b"),
		"movement": "Fast over hardpan, slow in deep dunes. High supply and water drain.",
		"combat": "Long sightlines, occasionally broken by sandstorms or heat haze.",
		"strategic": "Flanking maneuvers and fierce battles over scarce water or oasis nodes.",
		"move_cost_infantry": 1, "move_cost_vehicle": 1,
		"defense": 0, "vision": 2, "blocks_sight": false, "attrition": 1,
	},
	Type.MOUNTAINS: {
		"name": "Mountains & Highlands",
		"color": Color("8b8178"),
		"movement": "Impassable to vehicles outside of narrow roads and passes.",
		"combat": "High ground grants range and accuracy bonuses. Massive defense boost.",
		"strategic": "Natural borders, artillery nests, and critical strategic chokepoints.",
		"move_cost_infantry": 3, "move_cost_vehicle": -1,
		"defense": 3, "vision": 2, "blocks_sight": true, "attrition": 1,
	},
	Type.SWAMP: {
		"name": "Swamp & Marshland",
		"color": Color("5e6e3c"),
		"movement": "Boggy ground traps vehicles. Infantry move slowly.",
		"combat": "Moderate cover from reeds and trees, but poor footing reduces evasion.",
		"strategic": "Natural barriers that funnel enemy forces into predictable kill zones.",
		"move_cost_infantry": 2, "move_cost_vehicle": 4,
		"defense": 1, "vision": 0, "blocks_sight": false, "attrition": 1,
	},
	Type.TUNDRA: {
		"name": "Tundra & Arctic",
		"color": Color("e6edf1"),
		"movement": "Frozen ground supports heavy weight, but deep snow halts advances.",
		"combat": "Blizzards reduce visibility and weapon range. Severe cold attrition.",
		"strategic": "Endurance battles where winterized gear and heated supply hubs win wars.",
		"move_cost_infantry": 2, "move_cost_vehicle": 2,
		"defense": 0, "vision": -1, "blocks_sight": false, "attrition": 2,
	},
}


static func info(type: int) -> Dictionary:
	return DATA[type]


static func color(type: int) -> Color:
	return DATA[type]["color"]


static func display_name(type: int) -> String:
	return DATA[type]["name"]


static func is_water(type: int) -> bool:
	return type == Type.DEEP_OCEAN or type == Type.SHALLOW_WATER


static func count() -> int:
	return Type.size()
