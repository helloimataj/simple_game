class_name GameState
extends RefCounted
## The rules that tie units, buildings and resources together.
##
## - Each side has a stockpile of resources (ResourceTypes).
## - Buildings and units cost resources to create and upkeep every turn.
## - Units are trained on, or next to, a building of their side that trains them.
## - Economy buildings pay out every turn. Buildings that draw power produce
##   less if their side's power plants cannot cover the demand.
##
## With `sandbox` on, costs and training requirements are ignored (terrain
## rules still apply), which is handy for setting up test situations.

signal changed

const R := ResourceTypes.Type

const STARTING_STOCK := {
	R.MONEY: 2000, R.FOOD: 200, R.MATERIALS: 400, R.RARE_EARTHS: 20,
	R.URANIUM: 0, R.FUEL: 100, R.PRODUCTION: 300,
}
## Most money a side's banks can add to building income (as a share).
const MAX_BANK_BONUS := 0.5

var planet: Planet
var units: UnitManager
var buildings: BuildingManager
var sandbox := false:
	set(value):
		sandbox = value
		changed.emit()

## Stockpile per side: [{ResourceTypes.Type: amount}].
var stock: Array[Dictionary] = []


func _init(for_planet: Planet) -> void:
	planet = for_planet
	buildings = BuildingManager.new(planet)
	units = UnitManager.new(planet)
	units.buildings = buildings
	for i in UnitManager.PLAYERS.size():
		stock.append(STARTING_STOCK.duplicate())
	units.changed.connect(func() -> void: changed.emit())
	buildings.changed.connect(func() -> void: changed.emit())


# --- Paying ------------------------------------------------------------------

func can_afford(player: int, cost: Dictionary) -> bool:
	return missing_resources(player, cost).is_empty()


## What the side is short of for a cost: {type: shortfall}.
func missing_resources(player: int, cost: Dictionary) -> Dictionary:
	var missing := {}
	for type: int in cost:
		var short: int = cost[type] - stock[player].get(type, 0)
		if short > 0:
			missing[type] = short
	return missing


func _pay(player: int, cost: Dictionary) -> void:
	for type: int in cost:
		stock[player][type] = stock[player].get(type, 0) - cost[type]


func _afford_block_reason(player: int, cost: Dictionary) -> String:
	var missing := missing_resources(player, cost)
	if missing.is_empty():
		return ""
	return "Not enough resources (short of %s)" % ResourceTypes.format_amounts(missing)


# --- Buildings -----------------------------------------------------------------

## Empty if the side can build this here right now, otherwise why not.
func build_block_reason(type: int, player: int, tile: int) -> String:
	var reason := buildings.placement_block_reason(type, player, tile)
	if reason != "" or sandbox:
		return reason
	return _afford_block_reason(player, BuildingTypes.info(type)["cost"])


func build(type: int, player: int, tile: int) -> Building:
	if build_block_reason(type, player, tile) != "":
		return null
	if not sandbox:
		_pay(player, BuildingTypes.info(type)["cost"])
	return buildings.add_building(type, player, tile)


# --- Units -------------------------------------------------------------------

## Empty if the side can train this unit here right now, otherwise why not.
func train_block_reason(unit_type: int, player: int, tile: int) -> String:
	var reason := units.placement_block_reason(unit_type, tile)
	if reason != "" or sandbox:
		return reason
	if not _has_producer_near(unit_type, player, tile):
		var names: Array[String] = []
		for producer in BuildingTypes.producers_of(unit_type):
			names.append(BuildingTypes.display_name(producer))
		return "%s must be trained on or next to your %s" % [
			UnitTypes.display_name(unit_type), " or ".join(names)]
	return _afford_block_reason(player, UnitTypes.info(unit_type)["cost"])


func train(unit_type: int, player: int, tile: int) -> Unit:
	if train_block_reason(unit_type, player, tile) != "":
		return null
	if not sandbox:
		_pay(player, UnitTypes.info(unit_type)["cost"])
	return units.add_unit(unit_type, player, tile)


func _has_producer_near(unit_type: int, player: int, tile: int) -> bool:
	var producers := BuildingTypes.producers_of(unit_type)
	var nearby := [tile]
	nearby.append_array(planet.get_neighbors(tile))
	for t: int in nearby:
		for producer in producers:
			if buildings.has_type(t, producer, player):
				return true
	return false


# --- Economy -------------------------------------------------------------------

## Power a side generates and the power its buildings want: Vector2i(supply, demand).
func power_for(player: int) -> Vector2i:
	var supply := 0
	var demand := 0
	for building in buildings.owned_by(player):
		var power: int = building.data()["power"]
		if power > 0:
			supply += power
		else:
			demand -= power
	return Vector2i(supply, demand)


## Share of full output that powered buildings manage (1.0 = fully powered).
func power_efficiency(player: int) -> float:
	var power := power_for(player)
	if power.y <= 0:
		return 1.0
	return clampf(float(power.x) / power.y, 0.0, 1.0)


## Net change to a side's stockpile next turn: {type: amount}, every type present.
func income_for(player: int) -> Dictionary:
	var efficiency := power_efficiency(player)
	var produced := {}
	var spent := {}
	var banks := 0
	for building in buildings.owned_by(player):
		var data := building.data()
		var scale := efficiency if data["power"] < 0 else 1.0
		for type: int in data["produces"]:
			produced[type] = produced.get(type, 0.0) + data["produces"][type] * scale
		for type: int in data["upkeep"]:
			spent[type] = spent.get(type, 0) + data["upkeep"][type]
		if data["effects"].has("money_income_bonus"):
			banks += 1
	if banks > 0 and produced.has(R.MONEY):
		var bonus := minf(banks * BuildingTypes.info(BuildingTypes.Type.BANK)["effects"]["money_income_bonus"]
			* efficiency, MAX_BANK_BONUS)
		produced[R.MONEY] *= 1.0 + bonus
	for unit in units.units:
		if unit.owner != player:
			continue
		var upkeep: Dictionary = unit.data()["upkeep"]
		for type: int in upkeep:
			spent[type] = spent.get(type, 0) + upkeep[type]
	var net := {}
	for type in ResourceTypes.count():
		net[type] = int(floor(produced.get(type, 0.0))) - spent.get(type, 0)
	return net


## Applies one turn of income and upkeep to every side. Stockpiles stop at zero
## (running out has no further penalty yet).
func end_turn() -> void:
	for player in stock.size():
		var net := income_for(player)
		for type: int in net:
			stock[player][type] = maxi(stock[player].get(type, 0) + net[type], 0)
	changed.emit()
