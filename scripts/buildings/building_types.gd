class_name BuildingTypes
extends RefCounted
## Building definitions.
##
## Each entry only lists what differs from DEFAULTS. All numbers are first-pass
## values. "effects" holds parameters for systems that do not exist yet
## (vision, combat, research, morale ...) so they are ready when those arrive.

enum Category { MILITARY, ECONOMY, DEFENSE, INFRASTRUCTURE, STRATEGIC, GOVERNMENT }

## Where a building may stand.
enum Placement {
	LAND,     ## any land tile
	COASTAL,  ## land tile next to water
	BRIDGE,   ## shallow water tile next to land
}

enum Type {
	# Military production
	BARRACKS, FACTORY, AIRBASE, SHIPYARD, MILITARY_ACADEMY,
	# Economy
	FARM, MINE, OIL_WELL, INDUSTRIAL_COMPLEX, POWER_PLANT, TRADE_PORT, BANK,
	# Defense
	FORTIFICATION, AIR_DEFENSE, COASTAL_BATTERY, RADAR_STATION, MISSILE_DEFENSE,
	# Infrastructure
	ROAD, SUPPLY_DEPOT, BRIDGE, AIRPORT,
	# Strategic / advanced
	RESEARCH_LAB, INTELLIGENCE_HQ, MISSILE_SILO, SPACE_CENTER, NUCLEAR_FACILITY,
	# Government
	CAPITAL, ADMIN_CENTER, HOSPITAL, MEDIA_CENTER,
}

const CATEGORY_NAMES := {
	Category.MILITARY: "Military production",
	Category.ECONOMY: "Economy",
	Category.DEFENSE: "Defense",
	Category.INFRASTRUCTURE: "Infrastructure",
	Category.STRATEGIC: "Strategic / advanced",
	Category.GOVERNMENT: "Government",
}

const CATEGORY_COLORS := {
	Category.MILITARY: Color("6b7a35"),
	Category.ECONOMY: Color("f1c232"),
	Category.DEFENSE: Color("808b8f"),
	Category.INFRASTRUCTURE: Color("a8673a"),
	Category.STRATEGIC: Color("a462d8"),
	Category.GOVERNMENT: Color("f2f2f2"),
}

const R := ResourceTypes.Type

const DEFAULTS := {
	"name": "",
	"category": Category.MILITARY,
	"description": "",
	"placement": Placement.LAND,
	"forbidden_biomes": [],
	"cost": {},          # paid once when built
	"upkeep": {},        # paid every turn
	"produces": {},      # gained every turn (scaled down if short of power)
	"power": 0,          # > 0 supplies power, < 0 draws it
	"trains": [],        # UnitTypes.Type that can be trained here
	"unique": false,     # only one per side
	"effects": {},
}

const DATA := {
	# --- Military production -------------------------------------------------
	Type.BARRACKS: {
		"name": "Barracks", "category": Category.MILITARY,
		"description": "Trains infantry.",
		"cost": {R.MONEY: 150, R.MATERIALS: 20, R.PRODUCTION: 20},
		"upkeep": {R.MONEY: 2}, "power": -1,
		"trains": [UnitTypes.Type.INFANTRY],
	},
	Type.FACTORY: {
		"name": "Factory / Tank Plant", "category": Category.MILITARY,
		"description": "Builds armor and artillery.",
		"cost": {R.MONEY: 400, R.MATERIALS: 80, R.PRODUCTION: 60},
		"upkeep": {R.MONEY: 5}, "power": -3,
		"trains": [UnitTypes.Type.ARMOR],
	},
	Type.AIRBASE: {
		"name": "Airbase", "category": Category.MILITARY,
		"description": "Builds, repairs, and launches aircraft, and sets their operating range.",
		"cost": {R.MONEY: 500, R.MATERIALS: 60, R.PRODUCTION: 60},
		"upkeep": {R.MONEY: 6}, "power": -2,
		"trains": [UnitTypes.Type.AIRCRAFT],
		"effects": {"aircraft_operating_range": 12, "repairs": [UnitTypes.Type.AIRCRAFT]},
	},
	Type.SHIPYARD: {
		"name": "Naval Shipyard / Port", "category": Category.MILITARY,
		"description": "Builds and repairs warships, and is the starting point for overseas transport.",
		"placement": Placement.COASTAL,
		"cost": {R.MONEY: 600, R.MATERIALS: 100, R.PRODUCTION: 80},
		"upkeep": {R.MONEY: 6}, "power": -3,
		"trains": [UnitTypes.Type.NAVAL],
		"effects": {"repairs": [UnitTypes.Type.NAVAL], "embarkation_point": true},
	},
	Type.MILITARY_ACADEMY: {
		"name": "Military Academy", "category": Category.MILITARY,
		"description": "Gives new units an experience or quality bonus.",
		"cost": {R.MONEY: 400, R.MATERIALS: 30, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 5}, "power": -1,
		"effects": {"new_unit_experience": 1},
	},

	# --- Economy -------------------------------------------------------------
	Type.FARM: {
		"name": "Farm", "category": Category.ECONOMY,
		"description": "Food and population growth.",
		"forbidden_biomes": [Biomes.Type.MOUNTAINS, Biomes.Type.DESERT, Biomes.Type.TUNDRA],
		"cost": {R.MONEY: 80, R.PRODUCTION: 10},
		"produces": {R.FOOD: 6},
		"effects": {"population_growth": 1},
	},
	Type.MINE: {
		"name": "Mine", "category": Category.ECONOMY,
		"description": "Raw materials such as iron, rare earths, and uranium.",
		"cost": {R.MONEY: 200, R.MATERIALS: 10, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 2}, "power": -1,
		"produces": {R.MATERIALS: 4, R.RARE_EARTHS: 1, R.URANIUM: 1},
	},
	Type.OIL_WELL: {
		"name": "Oil Well / Refinery", "category": Category.ECONOMY,
		"description": "Fuel for armor, aircraft, and ships. A classic strategic target.",
		"cost": {R.MONEY: 300, R.MATERIALS: 40, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 3}, "power": -1,
		"produces": {R.FUEL: 5},
	},
	Type.INDUSTRIAL_COMPLEX: {
		"name": "Industrial Complex", "category": Category.ECONOMY,
		"description": "General production points.",
		"cost": {R.MONEY: 500, R.MATERIALS: 80, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 5}, "power": -4,
		"produces": {R.PRODUCTION: 8},
	},
	Type.POWER_PLANT: {
		"name": "Power Plant", "category": Category.ECONOMY,
		"description": "Powers other buildings. Could come in coal, nuclear, or renewable versions with tradeoffs.",
		"cost": {R.MONEY: 400, R.MATERIALS: 60, R.PRODUCTION: 50},
		"upkeep": {R.MONEY: 4, R.FUEL: 1}, "power": 10,
	},
	Type.TRADE_PORT: {
		"name": "Commercial Port / Trade Hub", "category": Category.ECONOMY,
		"description": "Income from trade routes.",
		"placement": Placement.COASTAL,
		"cost": {R.MONEY: 400, R.MATERIALS: 50, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 2}, "power": -1,
		"produces": {R.MONEY: 25},
	},
	Type.BANK: {
		"name": "Bank / Financial Center", "category": Category.ECONOMY,
		"description": "Boosts money income.",
		"cost": {R.MONEY: 500, R.MATERIALS: 20, R.PRODUCTION: 30},
		"power": -1,
		## Each bank adds this share to money produced by buildings (see GameState).
		"effects": {"money_income_bonus": 0.1},
	},

	# --- Defense -------------------------------------------------------------
	Type.FORTIFICATION: {
		"name": "Fortifications / Bunkers", "category": Category.DEFENSE,
		"description": "Defense bonus for units on that tile.",
		"cost": {R.MONEY: 200, R.MATERIALS: 60, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 1},
		"effects": {"defense_bonus": 3},
	},
	Type.AIR_DEFENSE: {
		"name": "Air Defense Site", "category": Category.DEFENSE,
		"description": "Shoots at enemy aircraft in range.",
		"cost": {R.MONEY: 350, R.MATERIALS: 40, R.RARE_EARTHS: 5, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 4}, "power": -1,
		"effects": {"range": 3, "attack_vs_aircraft": 6},
	},
	Type.COASTAL_BATTERY: {
		"name": "Coastal Battery", "category": Category.DEFENSE,
		"description": "Protects shorelines from ships.",
		"placement": Placement.COASTAL,
		"cost": {R.MONEY: 350, R.MATERIALS: 60, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 3},
		"effects": {"range": 3, "attack_vs_naval": 6},
	},
	Type.RADAR_STATION: {
		"name": "Radar Station", "category": Category.DEFENSE,
		"description": "Reveals enemy units in a radius.",
		"cost": {R.MONEY: 300, R.MATERIALS: 20, R.RARE_EARTHS: 10, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 3}, "power": -2,
		"effects": {"reveal_radius": 6},
	},
	Type.MISSILE_DEFENSE: {
		"name": "Missile Defense Site", "category": Category.DEFENSE,
		"description": "Chance to intercept missiles.",
		"cost": {R.MONEY: 700, R.MATERIALS: 50, R.RARE_EARTHS: 20, R.PRODUCTION: 60},
		"upkeep": {R.MONEY: 6}, "power": -3,
		"effects": {"range": 4, "intercept_chance": 0.5},
	},

	# --- Infrastructure ------------------------------------------------------
	Type.ROAD: {
		"name": "Road / Railway", "category": Category.INFRASTRUCTURE,
		"description": "Faster movement and supply. Lets vehicles through mountains.",
		"cost": {R.MONEY: 30, R.MATERIALS: 5, R.PRODUCTION: 5},
		"effects": {"move_cost_multiplier": 0.5, "vehicles_pass_mountains": true},
	},
	Type.SUPPLY_DEPOT: {
		"name": "Supply Depot", "category": Category.INFRASTRUCTURE,
		"description": "Keeps nearby units supplied, and is a high-value target.",
		"cost": {R.MONEY: 200, R.MATERIALS: 30, R.PRODUCTION: 20},
		"upkeep": {R.MONEY: 2},
		"effects": {"supply_radius": 4},
	},
	Type.BRIDGE: {
		"name": "Bridge", "category": Category.INFRASTRUCTURE,
		"description": "Important crossings that can be destroyed. Lets land units cross a shallow water tile.",
		"placement": Placement.BRIDGE,
		"cost": {R.MONEY: 150, R.MATERIALS: 40, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 1},
		"effects": {"land_units_can_cross": true, "destructible": true},
	},
	Type.AIRPORT: {
		"name": "Airport (Civilian)", "category": Category.INFRASTRUCTURE,
		"description": "Could be turned into a makeshift airbase in wartime.",
		"cost": {R.MONEY: 350, R.MATERIALS: 40, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 2}, "power": -1,
		"produces": {R.MONEY: 8},
		"effects": {"converts_to": Type.AIRBASE},
	},

	# --- Strategic / advanced --------------------------------------------------
	Type.RESEARCH_LAB: {
		"name": "Research Lab", "category": Category.STRATEGIC,
		"description": "Unlocks new tech and upgrades.",
		"cost": {R.MONEY: 600, R.MATERIALS: 40, R.RARE_EARTHS: 10, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 8}, "power": -3,
		"effects": {"research_points": 5},
	},
	Type.INTELLIGENCE_HQ: {
		"name": "Intelligence Agency HQ", "category": Category.STRATEGIC,
		"description": "Trains spies, reveals enemy plans.",
		"cost": {R.MONEY: 700, R.MATERIALS: 30, R.RARE_EARTHS: 10, R.PRODUCTION: 40},
		"upkeep": {R.MONEY: 10}, "power": -2,
		"unique": true,
		"effects": {"trains_spies": true, "reveals_enemy_plans": true},
	},
	Type.MISSILE_SILO: {
		"name": "Missile Silo", "category": Category.STRATEGIC,
		"description": "Launches long-range or nuclear strikes.",
		"cost": {R.MONEY: 900, R.MATERIALS: 120, R.RARE_EARTHS: 20, R.PRODUCTION: 100},
		"upkeep": {R.MONEY: 8}, "power": -1,
		"effects": {"strike_range": 30, "nuclear_capable": true},
	},
	Type.SPACE_CENTER: {
		"name": "Space Center", "category": Category.STRATEGIC,
		"description": "Launches satellites for global vision.",
		"cost": {R.MONEY: 1500, R.MATERIALS: 150, R.RARE_EARTHS: 50, R.PRODUCTION: 150},
		"upkeep": {R.MONEY: 15}, "power": -6,
		"unique": true,
		"effects": {"global_vision": true},
	},
	Type.NUCLEAR_FACILITY: {
		"name": "Nuclear Reactor / Enrichment Facility", "category": Category.STRATEGIC,
		"description": "Needed for nuclear weapons, and could draw diplomatic penalties.",
		"cost": {R.MONEY: 1200, R.MATERIALS: 150, R.RARE_EARTHS: 30, R.URANIUM: 20, R.PRODUCTION: 120},
		"upkeep": {R.MONEY: 12, R.URANIUM: 1}, "power": 6,
		"effects": {"enables_nuclear_weapons": true, "diplomatic_penalty": 1},
	},

	# --- Government ------------------------------------------------------------
	Type.CAPITAL: {
		"name": "Capital", "category": Category.GOVERNMENT,
		"description": "Losing it hurts morale and production badly.",
		"unique": true,
		"produces": {R.MONEY: 20, R.FOOD: 5, R.PRODUCTION: 5},
		"power": 5,
		"effects": {"loss_morale_penalty": 3, "loss_production_penalty": 0.5},
	},
	Type.ADMIN_CENTER: {
		"name": "Administrative Center", "category": Category.GOVERNMENT,
		"description": "Lowers unrest and makes occupied land easier to govern.",
		"cost": {R.MONEY: 400, R.MATERIALS: 30, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 4}, "power": -1,
		"effects": {"unrest_reduction": 2, "radius": 5},
	},
	Type.HOSPITAL: {
		"name": "Hospital", "category": Category.GOVERNMENT,
		"description": "Wounded units heal faster.",
		"cost": {R.MONEY: 300, R.MATERIALS: 30, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 4}, "power": -1,
		"effects": {"heal_bonus": 2, "radius": 2},
	},
	Type.MEDIA_CENTER: {
		"name": "Propaganda / Media Center", "category": Category.GOVERNMENT,
		"description": "Boosts public support for the war.",
		"cost": {R.MONEY: 400, R.MATERIALS: 20, R.RARE_EARTHS: 5, R.PRODUCTION: 30},
		"upkeep": {R.MONEY: 5}, "power": -2,
		"effects": {"war_support": 1},
	},
}

static var _merged := {}


## Full definition of a building type (DEFAULTS filled in).
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


static func category_color(type: int) -> Color:
	return CATEGORY_COLORS[DATA[type]["category"]]


## Building types that can train a unit type.
static func producers_of(unit_type: int) -> Array[int]:
	var out: Array[int] = []
	for type in count():
		if info(type)["trains"].has(unit_type):
			out.append(type)
	return out


static func placement_text(type: int) -> String:
	match info(type)["placement"]:
		Placement.COASTAL:
			return "Land next to water"
		Placement.BRIDGE:
			return "Shallow water next to land"
	return "Land"


## Multi-line summary for tooltips.
static func summary(type: int) -> String:
	var d := info(type)
	var lines: Array[String] = [d["description"], ""]
	lines.append("Cost: " + ResourceTypes.format_amounts(d["cost"]))
	if not d["upkeep"].is_empty():
		lines.append("Upkeep per turn: " + ResourceTypes.format_amounts(d["upkeep"]))
	if not d["produces"].is_empty():
		lines.append("Produces per turn: " + ResourceTypes.format_amounts(d["produces"]))
	if d["power"] > 0:
		lines.append("Supplies %d power" % d["power"])
	elif d["power"] < 0:
		lines.append("Uses %d power" % -d["power"])
	if not d["trains"].is_empty():
		var names: Array[String] = []
		for unit_type: int in d["trains"]:
			names.append(UnitTypes.display_name(unit_type))
		lines.append("Trains: " + ", ".join(names))
	lines.append("Built on: " + placement_text(type))
	if d["unique"]:
		lines.append("Only one per side")
	return "\n".join(lines)
