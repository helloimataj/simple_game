class_name ResourceTypes
extends RefCounted
## Stockpiled resources. Costs, upkeep and income are dictionaries {Type: amount}.
##
## Power is not listed here: it is not stockpiled. Power plants supply it and
## other buildings draw it every turn (see GameState.power_for).

enum Type { MONEY, FOOD, MATERIALS, RARE_EARTHS, URANIUM, FUEL, PRODUCTION }

const DATA := {
	Type.MONEY: {"name": "Money", "color": Color("f2d16b"),
		"description": "Pays for everything and for upkeep."},
	Type.FOOD: {"name": "Food", "color": Color("9ad17a"),
		"description": "Feeds infantry. From farms."},
	Type.MATERIALS: {"name": "Materials", "color": Color("b9a79a"),
		"description": "Iron and other raw materials. From mines."},
	Type.RARE_EARTHS: {"name": "Rare Earths", "color": Color("c79bf2"),
		"description": "Electronics for aircraft and advanced sites. From mines."},
	Type.URANIUM: {"name": "Uranium", "color": Color("a4f27a"),
		"description": "Nuclear programmes. From mines."},
	Type.FUEL: {"name": "Fuel", "color": Color("f29b5c"),
		"description": "Runs armor, aircraft and ships. From oil wells."},
	Type.PRODUCTION: {"name": "Production", "color": Color("8fc7f2"),
		"description": "General production points. From industrial complexes."},
}


static func display_name(type: int) -> String:
	return DATA[type]["name"]


static func color(type: int) -> Color:
	return DATA[type]["color"]


static func count() -> int:
	return Type.size()


## "Money 100, Food 20" (or "Free").
static func format_amounts(amounts: Dictionary, empty_text := "Free") -> String:
	var parts: Array[String] = []
	for type in count():
		if amounts.get(type, 0) != 0:
			parts.append("%s %d" % [display_name(type), amounts[type]])
	return ", ".join(parts) if not parts.is_empty() else empty_text
