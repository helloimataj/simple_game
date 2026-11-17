extends SceneTree
## Headless checks for buildings, resources, costs and the per-turn economy.
## Run: godot --headless --path . --script res://tests/test_buildings.gd

const B := BuildingTypes.Type
const R := ResourceTypes.Type
const U := UnitTypes.Type

var failures := 0
var planet: Planet


func _init() -> void:
	planet = Planet.new()
	planet.build(20)
	TerrainGenerator.generate(planet, 1)

	_check_data()
	_check_placement()
	_check_costs_and_training()
	_check_economy()
	_check_roads_and_bridges()

	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)


## First tile matching a test, or -1.
func _find(test: Callable) -> int:
	for t in planet.tile_count:
		if test.call(t):
			return t
	return -1


func _is_land(t: int) -> bool:
	return not Biomes.is_water(planet.biomes[t])


func _touches_water(t: int) -> bool:
	for nb in planet.get_neighbors(t):
		if not _is_land(nb):
			return true
	return false


func _inland_plains(t: int) -> bool:
	return planet.biomes[t] == Biomes.Type.PLAINS and not _touches_water(t)


func _check_data() -> void:
	_expect(BuildingTypes.count() == 30, "30 building types (got %d)" % BuildingTypes.count())
	var per_category := {}
	for type in BuildingTypes.count():
		var d := BuildingTypes.info(type)
		per_category[d["category"]] = per_category.get(d["category"], 0) + 1
		_expect(d["name"] != "" and d["description"] != "", "building %d has a name and description" % type)
		_expect(type == B.CAPITAL or not d["cost"].is_empty(), "%s has a cost" % d["name"])
		for amounts: Dictionary in [d["cost"], d["upkeep"], d["produces"]]:
			for key: int in amounts:
				_expect(key >= 0 and key < ResourceTypes.count() and amounts[key] > 0,
					"%s uses valid resource amounts" % d["name"])
	_expect(per_category == {
		BuildingTypes.Category.MILITARY: 5, BuildingTypes.Category.ECONOMY: 7,
		BuildingTypes.Category.DEFENSE: 5, BuildingTypes.Category.INFRASTRUCTURE: 4,
		BuildingTypes.Category.STRATEGIC: 5, BuildingTypes.Category.GOVERNMENT: 4,
	}, "buildings per category match the design list")
	for unit_type in UnitTypes.count():
		var d := UnitTypes.info(unit_type)
		_expect(not d["cost"].is_empty() and not d["upkeep"].is_empty(),
			"%s has a cost and upkeep" % d["name"])
		_expect(BuildingTypes.producers_of(unit_type).size() == 1,
			"%s is trained by exactly one building type" % d["name"])
	_expect(BuildingTypes.producers_of(U.INFANTRY) == [B.BARRACKS] and BuildingTypes.producers_of(U.ARMOR) == [B.FACTORY]
		and BuildingTypes.producers_of(U.AIRCRAFT) == [B.AIRBASE] and BuildingTypes.producers_of(U.NAVAL) == [B.SHIPYARD],
		"each unit type is trained at the right building")


func _check_placement() -> void:
	var m := BuildingManager.new(planet)
	var inland := _find(_inland_plains)
	var coast := _find(func(t: int) -> bool: return _is_land(t) and _touches_water(t))
	var deep := _find(func(t: int) -> bool: return planet.biomes[t] == Biomes.Type.DEEP_OCEAN)
	var strait := _find(func(t: int) -> bool:
		return planet.biomes[t] == Biomes.Type.SHALLOW_WATER and Array(planet.get_neighbors(t)).any(_is_land))
	var desert := _find(func(t: int) -> bool: return planet.biomes[t] == Biomes.Type.DESERT)

	_expect(m.can_place(B.BARRACKS, 0, inland), "barracks on land")
	_expect(not m.can_place(B.BARRACKS, 0, deep), "no barracks at sea")
	_expect(m.can_place(B.SHIPYARD, 0, coast) and not m.can_place(B.SHIPYARD, 0, inland),
		"shipyard only on the coast")
	_expect(m.can_place(B.TRADE_PORT, 0, coast) and not m.can_place(B.COASTAL_BATTERY, 0, inland),
		"ports and coastal batteries need a coast")
	_expect(m.can_place(B.BRIDGE, 0, strait) and not m.can_place(B.BRIDGE, 0, inland)
		and not m.can_place(B.BRIDGE, 0, deep), "bridge only on shallow water next to land")
	_expect(not m.can_place(B.FARM, 0, desert) and m.can_place(B.MINE, 0, desert),
		"no farms in the desert, mines are fine")

	# Many buildings on one tile, one of each type, one owner.
	for type in [B.BARRACKS, B.FACTORY, B.FARM, B.MINE, B.BANK, B.FORTIFICATION, B.ROAD, B.HOSPITAL]:
		_expect(m.add_building(type, 0, inland) != null, "can stack %s" % BuildingTypes.display_name(type))
	_expect(m.buildings_at(inland).size() == 8, "eight buildings share a tile")
	_expect(m.add_building(B.FARM, 0, inland) == null, "only one of each type per tile")
	_expect(m.add_building(B.AIRBASE, 1, inland) == null, "another side cannot build on an owned tile")
	_expect(m.owner_of(inland) == 0 and m.owner_of(coast) == -1, "tile ownership follows buildings")

	# Unique buildings.
	_expect(m.add_building(B.CAPITAL, 0, inland) != null, "first capital")
	_expect(m.add_building(B.CAPITAL, 0, coast) == null, "only one capital per side")
	_expect(m.add_building(B.CAPITAL, 1, coast) != null, "the other side gets its own capital")

	var farm: Building = m.buildings_at(inland)[2]
	m.remove_building(farm)
	_expect(not m.has_type(inland, B.FARM) and m.can_place(B.FARM, 0, inland), "removed building frees its slot")


func _check_costs_and_training() -> void:
	var game := GameState.new(planet)
	var home := _find(func(t: int) -> bool: return _inland_plains(t) and Array(planet.get_neighbors(t)).all(_inland_plains))
	var far := _find(func(t: int) -> bool: return _inland_plains(t) and planet.centers[t].dot(planet.centers[home]) < 0.9)
	_expect(home >= 0 and far >= 0, "test tiles found")

	_expect(game.stock[0] == GameState.STARTING_STOCK and game.stock[1] == GameState.STARTING_STOCK,
		"both sides start with the starting stockpile")

	# No barracks: cannot train.
	_expect(game.train(U.INFANTRY, 0, home) == null, "infantry needs a barracks")
	_expect(game.train_block_reason(U.INFANTRY, 0, home).contains("Barracks"), "the reason names the barracks")

	# Building pays its cost.
	var before: Dictionary = game.stock[0].duplicate()
	_expect(game.build(B.BARRACKS, 0, home) != null, "barracks built")
	var cost: Dictionary = BuildingTypes.info(B.BARRACKS)["cost"]
	for type: int in cost:
		_expect(game.stock[0][type] == before[type] - cost[type], "barracks cost paid in %s" % ResourceTypes.display_name(type))
	_expect(game.stock[1] == GameState.STARTING_STOCK, "the other side pays nothing")

	# Training on and next to the barracks, paying the unit cost.
	before = game.stock[0].duplicate()
	_expect(game.train(U.INFANTRY, 0, home) != null, "infantry trained at the barracks")
	_expect(game.train(U.INFANTRY, 0, planet.get_neighbors(home)[0]) != null, "infantry trained next to the barracks")
	var unit_cost: Dictionary = UnitTypes.info(U.INFANTRY)["cost"]
	for type: int in unit_cost:
		_expect(game.stock[0][type] == before[type] - 2 * unit_cost[type], "infantry cost paid in %s" % ResourceTypes.display_name(type))
	_expect(game.train(U.INFANTRY, 0, far) == null, "cannot train far from the barracks")
	_expect(game.train(U.INFANTRY, 1, home) == null, "the other side cannot use this barracks")
	_expect(game.train(U.ARMOR, 0, home) == null, "a barracks does not build armor")

	# Running out of money.
	game.stock[0][R.MONEY] = 50
	_expect(game.build(B.FACTORY, 0, home) == null, "cannot build without the money")
	_expect(game.build_block_reason(B.FACTORY, 0, home).contains("Money"), "the reason names what is short")
	_expect(game.stock[0][R.MONEY] == 50, "a failed build costs nothing")

	# Sandbox ignores costs and requirements but not terrain.
	game.sandbox = true
	_expect(game.build(B.FACTORY, 0, home) != null and game.stock[0][R.MONEY] == 50, "sandbox builds for free")
	_expect(game.train(U.ARMOR, 1, far) != null, "sandbox trains anywhere valid")
	var sea := _find(func(t: int) -> bool: return not _is_land(t))
	_expect(game.train(U.ARMOR, 0, sea) == null and game.build(B.FARM, 0, sea) == null, "sandbox still obeys terrain")


func _check_economy() -> void:
	var game := GameState.new(planet)
	game.sandbox = true
	var tiles: Array[int] = []
	for t in planet.tile_count:
		if _inland_plains(t):
			tiles.append(t)
		if tiles.size() >= 6:
			break

	_expect(game.income_for(0)[R.MONEY] == 0 and game.power_for(0) == Vector2i.ZERO, "no buildings, no income")

	game.build(B.CAPITAL, 0, tiles[0])
	var income := game.income_for(0)
	_expect(income[R.MONEY] == 20 and income[R.FOOD] == 5 and income[R.PRODUCTION] == 5, "capital income")
	_expect(game.power_for(0) == Vector2i(5, 0), "capital supplies 5 power")

	game.build(B.FARM, 0, tiles[0])
	_expect(game.income_for(0)[R.FOOD] == 11, "farm adds 6 food")

	# Industrial complex draws 4 of the capital's 5 power: full output.
	game.build(B.INDUSTRIAL_COMPLEX, 0, tiles[1])
	_expect(game.power_for(0) == Vector2i(5, 4) and is_equal_approx(game.power_efficiency(0), 1.0), "powered")
	_expect(game.income_for(0)[R.PRODUCTION] == 13 and game.income_for(0)[R.MONEY] == 15,
		"industrial complex: +8 production, -5 money upkeep")

	# A second one overloads the grid: 5 supply for 8 demand.
	game.build(B.INDUSTRIAL_COMPLEX, 0, tiles[2])
	_expect(is_equal_approx(game.power_efficiency(0), 5.0 / 8.0), "short of power")
	_expect(game.income_for(0)[R.PRODUCTION] == 5 + 10, "underpowered complexes produce 16 x 5/8 = 10")

	# A power plant fixes it, for money and fuel upkeep.
	game.build(B.POWER_PLANT, 0, tiles[3])
	_expect(game.power_for(0) == Vector2i(15, 8) and game.income_for(0)[R.PRODUCTION] == 21, "power plant restores output")
	_expect(game.income_for(0)[R.FUEL] == -1, "power plant burns fuel")

	# Banks boost money made by buildings (capital 20 -> 22), not upkeep.
	var money_before: int = game.income_for(0)[R.MONEY]
	game.build(B.BANK, 0, tiles[4])
	_expect(game.income_for(0)[R.MONEY] == money_before + 2, "bank adds 10% to building money income")

	# Unit upkeep.
	var fuel_before: int = game.income_for(0)[R.FUEL]
	game.train(U.ARMOR, 0, tiles[5])
	_expect(game.income_for(0)[R.FUEL] == fuel_before - 2 and game.income_for(0)[R.MONEY] == money_before + 2 - 2,
		"armor upkeep: 2 fuel and 2 money per turn")

	# End of turn applies income; stockpiles stop at zero; sides are separate.
	var stock_before: Dictionary = game.stock[0].duplicate()
	var net := game.income_for(0)
	game.stock[0][R.FUEL] = 1
	game.end_turn()
	_expect(game.stock[0][R.MONEY] == stock_before[R.MONEY] + net[R.MONEY]
		and game.stock[0][R.PRODUCTION] == stock_before[R.PRODUCTION] + net[R.PRODUCTION], "end of turn applies income")
	_expect(game.stock[0][R.FUEL] == 0, "stockpile does not go below zero")
	_expect(game.stock[1] == GameState.STARTING_STOCK, "the idle side is unchanged")


func _check_roads_and_bridges() -> void:
	var game := GameState.new(planet)
	game.sandbox = true
	var mountain := _find(func(t: int) -> bool: return planet.biomes[t] == Biomes.Type.MOUNTAINS)
	var strait := _find(func(t: int) -> bool:
		return planet.biomes[t] == Biomes.Type.SHALLOW_WATER and Array(planet.get_neighbors(t)).any(_is_land))

	_expect(not game.units.can_place(U.ARMOR, mountain), "armor cannot enter bare mountains")
	game.build(B.ROAD, 0, mountain)
	_expect(game.units.can_place(U.ARMOR, mountain), "a road lets armor into mountains")
	_expect(not game.units.can_place(U.NAVAL, mountain), "a road does not help ships")

	_expect(not game.units.can_place(U.INFANTRY, strait), "infantry cannot enter water")
	game.build(B.BRIDGE, 0, strait)
	_expect(game.units.can_place(U.INFANTRY, strait) and game.units.can_place(U.ARMOR, strait),
		"a bridge lets land units cross")
	_expect(game.units.can_place(U.NAVAL, strait), "ships can still use a bridged tile")
