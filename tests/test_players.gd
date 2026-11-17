extends SceneTree
## Headless checks for player setup and starting locations.
## Run: godot --headless --path . --script res://tests/test_players.gd

var failures := 0


func _init() -> void:
	_expect(Players.MAX_PLAYERS == 20 and Players.PALETTE.size() == 20, "up to 20 players, each with a colour")
	var names := {}
	var colors := {}
	for entry in Players.PALETTE:
		names[entry[0]] = true
		colors[entry[1]] = true
	_expect(names.size() == 20 and colors.size() == 20, "player names and colours are all different")
	Players.setup(50)
	_expect(Players.count() == 20, "player count is capped at 20")
	Players.setup(0)
	_expect(Players.count() == 2, "at least 2 players")

	for edge in [20, 100]:
		var planet := Planet.new()
		planet.build(edge)
		TerrainGenerator.generate(planet, 1)
		for count in [2, 4, 8, 20]:
			Players.setup(count)
			var t0 := Time.get_ticks_msec()
			var game := GameState.new(planet)
			var starts := game.place_starting_capitals(1)
			var ms := Time.get_ticks_msec() - t0
			_expect(starts.size() == count and game.stock.size() == count, "%d players all get a start (edge %d)" % [count, edge])
			var closest := INF
			var good := 0
			for i in starts.size():
				_expect(game.capital_of(i) == starts[i], "player %d's capital is on its start" % i)
				_expect(not Biomes.is_water(planet.biomes[starts[i]]), "start %d is on land" % i)
				if StartLocations.GOOD_BIOMES.has(planet.biomes[starts[i]]):
					good += 1
				for j in range(i + 1, starts.size()):
					closest = minf(closest, planet.centers[starts[i]].angle_to(planet.centers[starts[j]]))
			var tiles_apart := closest / planet.tile_angle()
			print("  edge %d, %2d players: closest pair %.2f rad (%.0f tiles), %d ms" % [edge, count, closest, tiles_apart, ms])
			_expect(closest >= game.start_spacing - 1e-4, "no two starts are closer than the spacing")
			_expect(tiles_apart >= StartLocations.MIN_TILES_APART, "starts are at least %d tiles apart" % StartLocations.MIN_TILES_APART)
			_expect(closest >= 0.9 * sqrt(4.0 * PI * 0.29 / count) * 0.5, "starts are well spread for %d players" % count)
			_expect(good == count, "starts are on plains or forest")
			var again := GameState.new(planet).place_starting_capitals(1)
			_expect(again == starts, "same seed gives the same starts")
			var other := GameState.new(planet).place_starting_capitals(2)
			_expect(other != starts, "a different seed gives different starts")

	Players.setup(2)
	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
