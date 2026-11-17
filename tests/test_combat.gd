extends SceneTree
## Headless checks for the battle rules.
## Run: godot --headless --path . --script res://tests/test_combat.gd

const B := BuildingTypes.Type
const U := UnitTypes.Type
const ATT := Battle.ATTACKER
const DEF := Battle.DEFENDER

var failures := 0
var planet: Planet


func _init() -> void:
	planet = Planet.new()
	planet.build(20)
	TerrainGenerator.generate(planet, 1)

	_check_design_table()
	_check_slider_rule()
	_check_modifiers()
	_check_commit_and_retreat()
	_check_damage_assignment()
	_check_capture()
	_check_support()
	_check_full_battles()

	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)


func _near(value: float, target: float, tolerance: float) -> bool:
	return absf(value - target) <= tolerance


func _is_land(t: int) -> bool:
	return not Biomes.is_water(planet.biomes[t])


## A tile of `biome` whose neighbours are all land, with a neighbour of
## `neighbour_biome` (any land if -1). Returns [tile, neighbour].
func _pair(biome: int, neighbour_biome := -1, skip := 0) -> Array[int]:
	for t in planet.tile_count:
		if planet.biomes[t] != biome or not Array(planet.get_neighbors(t)).all(_is_land):
			continue
		for nb in planet.get_neighbors(t):
			if (neighbour_biome < 0 or planet.biomes[nb] == neighbour_biome) \
					and planet.biomes[nb] != Biomes.Type.MOUNTAINS \
					and Array(planet.get_neighbors(nb)).all(_is_land):
				if skip > 0:
					skip -= 1
					break
				return [t, nb]
	return [-1, -1]


func _new_game() -> GameState:
	var game := GameState.new(planet)
	game.sandbox = true
	return game


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Supply for both sides around a tile so supply does not skew a test.
func _supply(game: GameState, around: int) -> void:
	var placed := {}
	for t: int in planet.tiles_within(around, 3):
		if planet.tiles_within(around, 3)[t] == 3 and _is_land(t):
			for side in 2:
				if not placed.has(side) and game.build(B.SUPPLY_DEPOT, side, t) != null:
					placed[side] = true
					break
	assert(placed.size() == 2)


# The win rates and battle lengths quoted in the design.
func _check_design_table() -> void:
	var rng := _rng(12345)
	var rows := [
		# attacker, defender, [win % at 10%, 15%, 25% spread], rounds at 15%
		[60.0, 30.0, [100.0, 99.6, 95.0], 2.5],
		[50.0, 35.0, [98.0, 91.0, 80.0], 4.0],
		[50.0, 45.0, [72.0, 66.0, 60.0], 5.0],
		[50.0, 50.0, [50.0, 50.0, 50.0], 5.0],
	]
	var spreads := [0.10, 0.15, 0.25]
	for row in rows:
		var text: Array[String] = []
		for i in spreads.size():
			var wins := 0
			var rounds := 0
			var battles := 20000
			for b in battles:
				var result := Battle.simulate(row[0], row[1], spreads[i], rng)
				wins += int(result["attacker_won"])
				rounds += result["rounds"]
			var pct := 100.0 * wins / battles
			var avg := float(rounds) / battles
			text.append("%.1f%%" % pct)
			_expect(_near(pct, row[2][i], 2.5), "%d vs %d at %d%% spread: %.1f%% (design says %.1f%%)" % [
				row[0], row[1], spreads[i] * 100, pct, row[2][i]])
			if i == 1:
				text.append("(%.1f rounds)" % avg)
				_expect(_near(avg, row[3], 1.0), "%d vs %d lasts ~%.1f rounds (got %.1f)" % [row[0], row[1], row[3], avg])
		print("  %d vs %d: %s" % [row[0], row[1], " ".join(text)])
	# Scale-free: 500 vs 350 plays like 50 vs 35.
	var wins := 0
	for b in 20000:
		wins += int(Battle.simulate(500.0, 350.0, 0.15, rng)["attacker_won"])
	_expect(_near(100.0 * wins / 20000, 91.0, 2.5), "500 vs 350 plays like 50 vs 35 (%.1f%%)" % (100.0 * wins / 20000))


# Damage = distance from the roll to the dividing line, dealt by the zone's owner.
func _check_slider_rule() -> void:
	var tiles := _pair(Biomes.Type.SWAMP)
	var game := _new_game()
	_supply(game, tiles[0])
	for i in 5:
		game.train(U.INFANTRY, 0, tiles[1])   # attacker: 50
	for i in 3:
		game.train(U.INFANTRY, 1, tiles[0])   # defender: 30 x 1.2 = 36
	var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(4))
	battle.commit(battle.candidates(ATT), battle.candidates(DEF))
	_expect(battle.phase == Battle.Phase.ROLL, "battle is ready to roll after commit")
	_expect(_near(battle.side_power(ATT), 50.0, 0.001) and _near(battle.side_power(DEF), 36.0, 0.001),
		"powers: attacker 50, defender 30 x 1.2 = 36")
	for i in 40:
		if battle.phase != Battle.Phase.ROLL:
			break
		var attack := battle.side_power(ATT)
		var hp := [_hp(battle, ATT), _hp(battle, DEF)]
		battle.roll_round()
		var r := battle.last_roll
		_expect(_near(r["line"], attack, 0.001) and r["roll"] >= 0.0 and r["roll"] <= r["total"],
			"roll is on the slider and the line is at the attacker's power")
		_expect(r["hit_side"] == (DEF if r["roll"] < r["line"] else ATT), "the zone's owner deals the damage")
		_expect(r["damage"] == roundi(absf(r["line"] - r["roll"])), "damage is the distance to the line, rounded")
		battle.auto_assign()
		var lost: int = hp[r["hit_side"]] - _hp(battle, r["hit_side"])
		_expect(lost == mini(r["damage"], hp[r["hit_side"]]) and _hp(battle, 1 - r["hit_side"]) == hp[1 - r["hit_side"]],
			"only the hit side loses exactly that much")
		if battle.phase == Battle.Phase.RETREAT:
			battle.submit_retreat([], [])
	_expect(battle.phase == Battle.Phase.FINISHED, "battle runs to a finish")


func _hp(battle: Battle, side: int) -> int:
	var total := 0
	for unit: Unit in battle.committed[side]:
		total += unit.hit_points
	return total


func _check_modifiers() -> void:
	# Infantry x1.5 in forest; armor x1.5 on plains; artillery x0.5 defending.
	for case in [
		[Biomes.Type.FOREST, U.INFANTRY, 15.0], [Biomes.Type.PLAINS, U.INFANTRY, 10.0],
		[Biomes.Type.PLAINS, U.ARMOR, 30.0], [Biomes.Type.FOREST, U.ARMOR, 20.0],
		[Biomes.Type.DESERT, U.ARMOR, 30.0], [Biomes.Type.JUNGLE, U.INFANTRY, 15.0],
	]:
		var tiles := _pair(case[0])
		var game := _new_game()
		_supply(game, tiles[0])
		var attacker := game.train(case[1], 0, tiles[1])
		game.train(U.INFANTRY, 1, tiles[0])
		var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
		_expect(_near(battle.unit_power(attacker, ATT), case[2], 0.001), "%s attacking into %s has power %.1f" % [
			UnitTypes.display_name(case[1]), Biomes.display_name(case[0]), case[2]])

	var tiles := _pair(Biomes.Type.PLAINS, Biomes.Type.PLAINS)
	var game := _new_game()
	_supply(game, tiles[0])
	var gun_def := game.train(U.ARTILLERY, 1, tiles[0])
	var inf_def := game.train(U.INFANTRY, 1, tiles[0])
	var gun_att := game.train(U.ARTILLERY, 0, tiles[1])
	var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	_expect(_near(battle.unit_power(gun_def, DEF), 6.0, 0.001) and _near(battle.unit_power(gun_att, ATT), 12.0, 0.001),
		"artillery fights at half power when defending")
	_expect(_near(battle.defender_multiplier(), 1.2, 0.001), "defender multiplier is x1.2")
	_expect(_near(battle.side_power(DEF, [gun_def, inf_def]), (6.0 + 10.0) * 1.2, 0.001), "defender total uses the multiplier")

	# Fortifications and cities raise the defender multiplier; cities change unit modifiers.
	game.build(B.FORTIFICATION, 1, tiles[0])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	_expect(_near(battle.defender_multiplier(), 1.5, 0.001), "fortifications add 0.3")
	game.build(B.ADMIN_CENTER, 1, tiles[0])
	_expect(game.is_city(tiles[0]) and not game.is_city(tiles[1]), "an administrative center makes a city")
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	_expect(_near(battle.defender_multiplier(), 1.7, 0.001), "a city adds 0.2 more")
	var tank := game.train(U.ARMOR, 0, tiles[1])
	_expect(_near(battle.unit_power(tank, ATT), 15.0, 0.001), "armor x0.75 in a city, even on plains")
	_expect(_near(battle.unit_power(inf_def, DEF), 15.0, 0.001), "infantry x1.5 in a city")

	# Four ordinary buildings also make a city.
	var other := _pair(Biomes.Type.PLAINS, -1, 3)
	for type in [B.BARRACKS, B.FACTORY, B.BANK]:
		game.build(type, 0, other[0])
	_expect(not game.is_city(other[0]), "three buildings are not yet a city")
	game.build(B.FARM, 0, other[0])
	game.build(B.ROAD, 0, other[0])
	_expect(not game.is_city(other[0]), "farms and roads do not count")
	game.build(B.HOSPITAL, 0, other[0])
	_expect(game.is_city(other[0]), "four urban buildings make a city")

	# Supply: x0.5 without a supply source in reach.
	game = _new_game()
	var lonely := game.train(U.INFANTRY, 0, tiles[1])
	game.train(U.INFANTRY, 1, tiles[0])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	_expect(not battle.is_supplied(lonely) and _near(battle.unit_power(lonely, ATT), 5.0, 0.001), "out of supply: x0.5")
	game.build(B.SUPPLY_DEPOT, 0, tiles[1])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	_expect(battle.is_supplied(lonely) and _near(battle.unit_power(lonely, ATT), 10.0, 0.001), "a supply depot restores full power")

	# Damaged units fight at reduced power.
	lonely.hit_points = 4
	_expect(_near(battle.unit_power(lonely, ATT), 4.0, 0.001), "a damaged unit fights at its remaining hit points")


func _check_commit_and_retreat() -> void:
	var tiles := _pair(Biomes.Type.PLAINS, Biomes.Type.PLAINS)
	var game := _new_game()
	_supply(game, tiles[0])
	var a1 := game.train(U.INFANTRY, 0, tiles[1])
	var a2 := game.train(U.ARMOR, 0, tiles[1])
	var d1 := game.train(U.INFANTRY, 1, tiles[0])
	var d2 := game.train(U.INFANTRY, 1, tiles[0])
	var d3 := game.train(U.ARMOR, 1, tiles[0])

	_expect(Battle.start_block_reason(game, 0, tiles[1], tiles[0]) == "", "can attack an adjacent enemy tile")
	_expect(Battle.start_block_reason(game, 0, tiles[1], tiles[1]) != "", "cannot attack a non-adjacent tile")
	_expect(Battle.start_block_reason(game, 1, tiles[1], tiles[0]) != "", "cannot attack your own units")

	# The defender leaves a unit out: it retreats to a safe adjacent tile.
	var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(2))
	_expect(battle.sides == [0, 1], "sides are attacker 0, defender 1")
	battle.commit([a1, a2], [d1, d2])
	_expect(d3.tile != tiles[0] and d3.tile != tiles[1] and Array(planet.get_neighbors(tiles[0])).has(d3.tile),
		"an uncommitted defender retreats to an adjacent safe tile")
	_expect(battle.committed[DEF].size() == 2 and battle.committed[ATT].size() == 2, "committed units are in the fight")

	# Retreat: a defender pulls out, takes the pursuit hit, and leaves the tile.
	battle.roll_round()
	battle.auto_assign()
	if battle.phase == Battle.Phase.RETREAT and battle.committed[DEF].size() == 2:
		var runner: Unit = battle.committed[DEF][0]
		var hp_before := runner.hit_points
		var pursuit := roundi(Battle.PURSUIT_SHARE * battle.side_power(ATT))
		battle.submit_retreat([], [runner])
		_expect(battle.phase == Battle.Phase.ASSIGN and battle.current_damage()["amount"] == pursuit
			and battle.damage_pool() == [runner], "retreating unit takes 25% of the enemy's power as a pursuit hit")
		battle.auto_assign()
		if hp_before > pursuit:
			_expect(runner.hit_points == hp_before - pursuit and runner.tile != tiles[0], "the survivor leaves the tile")
		_expect(not battle.committed[DEF].has(runner), "a retreated unit is out of the battle")

	# The attacker pulls everything out: the defender holds.
	game = _new_game()
	_supply(game, tiles[0])
	a1 = game.train(U.INFANTRY, 0, tiles[1])
	d1 = game.train(U.INFANTRY, 1, tiles[0])
	for i in 4:
		game.train(U.INFANTRY, 1, tiles[0])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(3))
	battle.commit([a1], battle.candidates(DEF))
	for i in 20:
		if battle.phase != Battle.Phase.ROLL:
			break
		battle.roll_round()
		battle.auto_assign()
		if battle.phase == Battle.Phase.RETREAT:
			battle.submit_retreat(battle.committed[ATT].duplicate(), [])
			battle.auto_assign()
	_expect(battle.phase == Battle.Phase.FINISHED and battle.winner == DEF, "attacker retreats everything: defender holds")
	_expect(game.units.units_at(tiles[0]).all(func(u: Unit) -> bool: return u.owner == 1), "defenders still hold the tile")

	# The defender pulls everything out: the attacker takes the tile.
	game = _new_game()
	_supply(game, tiles[0])
	for i in 3:
		game.train(U.INFANTRY, 0, tiles[1])
	d1 = game.train(U.INFANTRY, 1, tiles[0])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(3))
	battle.commit(battle.candidates(ATT), [])
	_expect(battle.phase == Battle.Phase.FINISHED and battle.winner == ATT, "no defenders committed: attacker wins at once")
	_expect(d1.tile != tiles[0] and game.units.units.has(d1), "the defender fell back")
	_expect(game.units.units_at(tiles[0]).size() == 3 and game.units.units_at(tiles[1]).is_empty(), "attackers move onto the tile")

	# No safe tile: the left-out defender is lost.
	game = _new_game()
	game.train(U.INFANTRY, 0, tiles[1])
	d1 = game.train(U.INFANTRY, 1, tiles[0])
	for nb in planet.get_neighbors(tiles[0]):
		game.train(U.INFANTRY, 0, nb)
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(3))
	battle.commit(battle.candidates(ATT), [])
	_expect(not game.units.units.has(d1), "a surrounded defender with no safe tile is lost")


func _check_damage_assignment() -> void:
	var tiles := _pair(Biomes.Type.SWAMP)
	var game := _new_game()
	_supply(game, tiles[0])
	game.train(U.INFANTRY, 0, tiles[1])
	var inf := game.train(U.INFANTRY, 1, tiles[0])
	var inf2 := game.train(U.INFANTRY, 1, tiles[0])
	var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	battle.commit(battle.candidates(ATT), battle.candidates(DEF))
	# Hand the defender 14 damage and let it choose.
	battle.pending.append({"side": DEF, "amount": 14, "pool": battle.committed[DEF], "reason": "Test"})
	battle._resolve_pending(func() -> void: battle.phase = Battle.Phase.ROLL)
	_expect(battle.phase == Battle.Phase.ASSIGN and battle.current_damage()["side"] == DEF, "defender must assign damage")
	battle.assign(inf2)
	_expect(not game.units.units.has(inf2) and battle.current_damage()["amount"] == 4,
		"the chosen unit is finished off first; 4 damage is left over")
	_expect(battle.phase == Battle.Phase.ASSIGN, "still assigning")
	battle.assign(inf)
	_expect(inf.hit_points == 6 and battle.phase == Battle.Phase.ROLL, "the rest goes on the next unit")

	# Auto-assign sacrifices cheap units first.
	game = _new_game()
	_supply(game, tiles[0])
	game.train(U.INFANTRY, 0, tiles[1])
	var tank := game.train(U.ARTILLERY, 1, tiles[0])
	inf = game.train(U.INFANTRY, 1, tiles[0])
	battle = Battle.new(game, 0, tiles[1], tiles[0], null, _rng(1))
	battle.committed = [battle.candidates(ATT), battle.candidates(DEF)]
	battle.pending.append({"side": DEF, "amount": 5, "pool": battle.committed[DEF], "reason": "Test"})
	battle._resolve_pending(Callable())
	battle.auto_assign()
	_expect(inf.hit_points == 5 and tank.hit_points == 12, "auto-assign damages the cheapest unit first")


func _check_capture() -> void:
	var tiles := _pair(Biomes.Type.PLAINS, Biomes.Type.PLAINS)
	var game := _new_game()
	game.build(B.CAPITAL, 0, tiles[1])
	game.build(B.CAPITAL, 1, tiles[0])
	game.build(B.BARRACKS, 1, tiles[0])
	for i in 4:
		game.train(U.ARMOR, 0, tiles[1])
	var defender := game.train(U.INFANTRY, 1, tiles[0])
	var battle := Battle.new(game, 0, tiles[1], tiles[0], null, _rng(8))
	battle.commit(battle.candidates(ATT), [defender])
	for i in 40:
		if battle.phase != Battle.Phase.ROLL:
			break
		battle.roll_round()
		battle.auto_assign()
		if battle.phase == Battle.Phase.RETREAT:
			battle.submit_retreat([], [])
	_expect(battle.winner == ATT, "four tanks beat one infantry")
	_expect(game.buildings.has_type(tiles[0], B.BARRACKS, 0), "the barracks is captured")
	_expect(not game.buildings.has_type(tiles[0], B.CAPITAL), "a second capital is destroyed, not captured")
	_expect(game.buildings.count_of(B.CAPITAL, 1) == 0, "the loser has lost its capital")


func _check_support() -> void:
	# A coastal land tile with a land neighbour and a water tile within 2.
	var coast := -1
	var inland := -1
	var sea := -1
	for t in planet.tile_count:
		if not _is_land(t) or planet.biomes[t] == Biomes.Type.MOUNTAINS:
			continue
		var water := Array(planet.get_neighbors(t)).filter(func(nb: int) -> bool: return not _is_land(nb))
		var land := Array(planet.get_neighbors(t)).filter(func(nb: int) -> bool:
			return _is_land(nb) and planet.biomes[nb] != Biomes.Type.MOUNTAINS)
		if not water.is_empty() and not land.is_empty():
			coast = t; inland = land[0]; sea = water[0]
			break
	var game := _new_game()
	var infantry := game.train(U.INFANTRY, 0, inland)
	game.train(U.INFANTRY, 1, coast)

	# Naval bombardment of a coastal battle.
	var ship := game.train(U.NAVAL, 0, sea)
	var battle := Battle.new(game, 0, inland, coast, null, _rng(1))
	_expect(battle.candidates(ATT).has(ship) and battle.is_remote(ship), "a ship next to a coastal battle can bombard")
	var far_sea := -1
	for t: int in planet.tiles_within(coast, 6):
		if planet.tiles_within(coast, 6)[t] >= 4 and not _is_land(t):
			far_sea = t
	if far_sea >= 0:
		var far_ship := game.train(U.NAVAL, 0, far_sea)
		_expect(not battle.candidates(ATT).has(far_ship), "a distant ship cannot bombard")

	# Aircraft join from an airbase in range, not from open ground.
	var base := -1
	for t: int in planet.tiles_within(coast, 6):
		if planet.tiles_within(coast, 6)[t] == 5 and _is_land(t) and game.buildings.can_place(B.AIRBASE, 0, t):
			base = t
	var plane := game.train(U.AIRCRAFT, 0, base)
	battle = Battle.new(game, 0, inland, coast, null, _rng(1))
	_expect(not battle.candidates(ATT).has(plane), "aircraft without an airbase cannot join")
	game.build(B.AIRBASE, 0, base)
	battle = Battle.new(game, 0, inland, coast, null, _rng(1))
	_expect(battle.candidates(ATT).has(plane) and battle.is_remote(plane), "aircraft join from an airbase in range")
	_expect(_near(battle.unit_power(plane, ATT), 18.0, 0.001), "based aircraft are in supply at full power")

	# Bad weather grounds air support; a storm also stops bombardment.
	var weather := WeatherSystem.new()
	weather.setup(planet, 1)
	weather.current[coast] = Weather.Type.HEAVY_RAIN
	battle = Battle.new(game, 0, inland, coast, weather, _rng(1))
	_expect(not battle.candidates(ATT).has(plane) and battle.candidates(ATT).has(ship), "heavy rain grounds aircraft, not ships")
	weather.current[coast] = Weather.Type.STORM
	battle = Battle.new(game, 0, inland, coast, weather, _rng(1))
	_expect(not battle.candidates(ATT).has(plane) and not battle.candidates(ATT).has(ship), "a storm stops all support")

	# Air defense hits the aircraft first; supporters do not move in on a win.
	game.build(B.AIR_DEFENSE, 1, coast)
	battle = Battle.new(game, 0, inland, coast, null, _rng(5))
	battle.commit([infantry, plane, ship], battle.candidates(DEF))
	var first := battle.current_damage()
	_expect(battle.phase == Battle.Phase.ASSIGN and first["side"] == ATT and first["pool"] == [plane],
		"air defense fires on the aircraft before the battle")
	var plane_hp := plane.hit_points
	battle.auto_assign()
	_expect(plane.hit_points < plane_hp or not game.units.units.has(plane), "the aircraft takes the air defense damage")
	for i in 60:
		if battle.phase == Battle.Phase.ASSIGN:
			battle.auto_assign()
		elif battle.phase == Battle.Phase.ROLL:
			battle.roll_round()
		elif battle.phase == Battle.Phase.RETREAT:
			battle.submit_retreat([], [])
		else:
			break
	_expect(battle.phase == Battle.Phase.FINISHED, "supported battle finishes")
	_expect(ship.tile == sea or not game.units.units.has(ship), "the ship stays at sea")
	_expect(plane.tile == base or not game.units.units.has(plane), "the aircraft stays at its base")

	# Artillery fires a free round before the battle.
	game = _new_game()
	_supply(game, coast)
	var gun := game.train(U.ARTILLERY, 0, inland)
	game.train(U.INFANTRY, 0, inland)
	var target := game.train(U.INFANTRY, 1, coast)
	game.train(U.INFANTRY, 1, coast)
	battle = Battle.new(game, 0, inland, coast, null, _rng(5))
	battle.commit(battle.candidates(ATT), battle.candidates(DEF))
	first = battle.current_damage()
	_expect(battle.phase == Battle.Phase.ASSIGN and first["side"] == DEF and first["amount"] > 0
		and first["amount"] <= 12 and battle.round_number == 0, "artillery fires a free round before round 1")
	_expect(gun.hit_points == 12 and target.hit_points == 10, "nothing fires back at the artillery")


# Whole battles with units reproduce the expected odds.
func _check_full_battles() -> void:
	var tiles := _pair(Biomes.Type.SWAMP)
	var rng := _rng(77)
	var wins := 0
	var battles := 300
	for b in battles:
		var game := _new_game()
		_supply(game, tiles[0])
		for i in 6:
			game.train(U.INFANTRY, 0, tiles[1])   # 60
		for i in 3:
			game.train(U.INFANTRY, 1, tiles[0])   # 30 x 1.2 = 36
		var battle := Battle.new(game, 0, tiles[1], tiles[0], null, rng)
		battle.commit(battle.candidates(ATT), battle.candidates(DEF))
		for i in 60:
			if battle.phase == Battle.Phase.ASSIGN:
				battle.auto_assign()
			elif battle.phase == Battle.Phase.ROLL:
				battle.roll_round()
			elif battle.phase == Battle.Phase.RETREAT:
				battle.submit_retreat([], [])
			else:
				break
		wins += int(battle.winner == ATT)
		var survivors := game.units.units_at(tiles[0])
		if battle.winner == ATT:
			_expect(not survivors.is_empty() and survivors.all(func(u: Unit) -> bool: return u.owner == 0),
				"winner's units hold the tile")
	var pct := 100.0 * wins / battles
	print("  60 vs 36 (30 x1.2) with units: attacker wins %.1f%%" % pct)
	_expect(pct > 88.0 and pct < 100.0, "6 infantry usually beat 3 dug-in infantry (%.1f%%)" % pct)
