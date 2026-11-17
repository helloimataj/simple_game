extends SceneTree
## Headless checks for unit types, placement rules and stacking.
## Run: godot --headless --path . --script res://tests/test_units.gd

var failures := 0


func _init() -> void:
	var planet := Planet.new()
	planet.build(20)
	TerrainGenerator.generate(planet, 1)
	var units := UnitManager.new(planet)

	var tile_of := {}  # biome -> a tile of that biome
	for t in planet.tile_count:
		if not tile_of.has(planet.biomes[t]):
			tile_of[planet.biomes[t]] = t
	_expect(tile_of.size() == Biomes.count(), "test world has every biome")

	var I := UnitTypes.Type.INFANTRY
	var A := UnitTypes.Type.ARMOR
	var P := UnitTypes.Type.AIRCRAFT
	var N := UnitTypes.Type.NAVAL

	# Which unit types may occupy which biomes.
	for biome in Biomes.count():
		var tile: int = tile_of[biome]
		var water := Biomes.is_water(biome)
		var label := Biomes.display_name(biome)
		_expect(units.can_place(I, tile) == (not water), "infantry on %s: %s" % [label, not water])
		_expect(units.can_place(A, tile) == (not water and biome != Biomes.Type.MOUNTAINS),
			"armor on %s" % label)
		_expect(units.can_place(P, tile), "aircraft over %s" % label)
		_expect(units.can_place(N, tile) == water, "naval on %s: %s" % [label, water])

	# Invalid placement creates nothing and explains why.
	var land: int = tile_of[Biomes.Type.PLAINS]
	var sea: int = tile_of[Biomes.Type.DEEP_OCEAN]
	_expect(units.add_unit(N, 0, land) == null, "no ships on land")
	_expect(units.add_unit(I, 0, sea) == null, "no infantry at sea")
	_expect(units.add_unit(A, 0, tile_of[Biomes.Type.MOUNTAINS]) == null, "no armor in mountains")
	_expect(units.placement_block_reason(N, land) != "", "blocked placement has a reason")
	_expect(units.units.is_empty(), "failed placements add no units")

	# Any number of units can share a tile.
	for i in 25:
		units.add_unit(I if i % 2 == 0 else A, i % 2, land)
	units.add_unit(P, 0, land)
	_expect(units.units_at(land).size() == 26, "26 units stacked on one tile")
	var summary := units.stack_summary(land)
	_expect(summary[[0, I]] == 13 and summary[[1, A]] == 12 and summary[[0, P]] == 1,
		"stack summary groups by side and type")

	# New units start at full strength.
	var ship := units.add_unit(N, 1, sea)
	_expect(ship != null and ship.hit_points == UnitTypes.info(N)["hit_points"]
		and ship.moves_left == UnitTypes.info(N)["movement"], "new unit has full HP and movement")

	# Relocating respects the same rules.
	_expect(not units.relocate(ship, land), "ship cannot relocate onto land")
	_expect(ship.tile == sea, "failed relocation leaves the unit in place")
	var shallow: int = tile_of[Biomes.Type.SHALLOW_WATER]
	_expect(units.relocate(ship, shallow) and units.units_at(shallow) == [ship]
		and units.units_at(sea).is_empty(), "ship relocates between water tiles")

	# Removal.
	units.remove_unit(ship)
	_expect(units.units_at(shallow).is_empty() and not units.units.has(ship), "removed unit is gone")
	_expect(not units.occupied_tiles().has(shallow), "emptied tile is no longer occupied")

	# Type data is complete and matches the design brief.
	for type in UnitTypes.count():
		var d := UnitTypes.info(type)
		for target in UnitTypes.count():
			_expect(d["attack"].has(target), "%s has attack vs %s" % [d["name"], UnitTypes.display_name(target)])
	_expect(UnitTypes.info(I)["cost"] < UnitTypes.info(A)["cost"], "infantry is cheaper than armor")
	_expect(UnitTypes.info(I)["movement"] < UnitTypes.info(A)["movement"], "infantry is slower than armor")
	_expect(UnitTypes.info(P)["movement"] > UnitTypes.info(A)["movement"], "aircraft are fastest")
	_expect(not UnitTypes.info(P)["can_hold_territory"] and UnitTypes.info(P)["needs_airbase"],
		"aircraft cannot hold territory and need airbases")
	_expect(UnitTypes.info(N)["bombard_range"] > 0 and UnitTypes.info(N)["transport_capacity"] > 0,
		"naval units bombard and carry troops")

	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
