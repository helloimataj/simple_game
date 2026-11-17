extends SceneTree
## Headless checks for world generation.
## Run: godot --headless --path . --script res://tests/test_planet.gd

var failures := 0


func _init() -> void:
	for n in [20, 100]:
		_check_planet(n)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)


func _check_weather(planet: Planet) -> void:
	var t0 := Time.get_ticks_msec()
	var weather := WeatherSystem.new()
	weather.setup(planet, 3)
	var twin := WeatherSystem.new()
	twin.setup(planet, 3)
	var totals := PackedInt32Array()
	totals.resize(Weather.count())
	var changed := 0
	var mud_on_water := 0
	var turns := 12
	for turn in turns:
		var before := weather.current.duplicate()
		weather.advance()
		twin.advance()
		for t in planet.tile_count:
			var w := weather.current[t]
			totals[w] += 1
			if w != before[t]:
				changed += 1
			if w == Weather.Type.MUD and Biomes.is_water(planet.biomes[t]):
				mud_on_water += 1
	var parts: Array[String] = []
	for w in Weather.count():
		parts.append("%s %.0f%%" % [Weather.info(w)["name"].split(" ")[0],
			100.0 * totals[w] / (turns * planet.tile_count)])
		_expect(totals[w] > 0, "weather %s occurs" % Weather.info(w)["name"])
	print("  weather %d ms/turn | %s | %.0f%% of tiles change per turn" % [
		(Time.get_ticks_msec() - t0) / (turns + 2), ", ".join(parts),
		100.0 * changed / (turns * planet.tile_count)])
	_expect(weather.current == twin.current, "weather is deterministic for a seed")
	_expect(changed > 0, "weather changes between turns")
	_expect(mud_on_water == 0, "no mud on water")
	_expect(totals[Weather.Type.CLEAR] > totals[Weather.Type.STORM], "clear is more common than storms")


func _check_planet(n: int) -> void:
	var t0 := Time.get_ticks_msec()
	var planet := Planet.new()
	planet.build(n)
	var t1 := Time.get_ticks_msec()
	print("n=%d: %d tiles, geometry %d ms" % [n, planet.tile_count, t1 - t0])

	_expect(planet.tile_count == 10 * n * n + 2, "tile count for n=%d" % n)
	var pentagons := 0
	var bad_degree := 0
	var asymmetric := 0
	for t in planet.tile_count:
		var d := planet.degree(t)
		if d == 5:
			pentagons += 1
		elif d != 6:
			bad_degree += 1
		for nb in planet.get_neighbors(t):
			if not planet.get_neighbors(nb).has(t):
				asymmetric += 1
	_expect(pentagons == 12, "exactly 12 pentagons (got %d)" % pentagons)
	_expect(bad_degree == 0, "all other tiles are hexagons (bad: %d)" % bad_degree)
	_expect(asymmetric == 0, "neighbour lists are symmetric (bad: %d)" % asymmetric)

	# Neighbours must be ordered CCW around the outward normal.
	var misordered := 0
	for t in range(0, planet.tile_count, 37):
		var c := planet.centers[t]
		var nbs := planet.get_neighbors(t)
		for k in nbs.size():
			var a := planet.centers[nbs[k]] - c
			var b := planet.centers[nbs[(k + 1) % nbs.size()]] - c
			if a.cross(b).dot(c) <= 0.0:
				misordered += 1
	_expect(misordered == 0, "neighbours are CCW (bad: %d)" % misordered)

	# Nearest-tile lookup agrees with brute force.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	for i in 200:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var found := planet.find_tile(dir, rng.randi_range(0, planet.tile_count - 1))
		var best := 0
		var best_dot := -2.0
		for t in planet.tile_count:
			var d := planet.centers[t].dot(dir)
			if d > best_dot:
				best_dot = d
				best = t
		if found != best and absf(planet.centers[found].dot(dir) - best_dot) > 1e-6:
			wrong += 1
	_expect(wrong == 0, "find_tile matches brute force (wrong: %d)" % wrong)

	for world_seed in [1, 2, 3]:
		t0 = Time.get_ticks_msec()
		TerrainGenerator.generate(planet, world_seed)
		var counts := PackedInt32Array()
		counts.resize(Biomes.count())
		for t in planet.tile_count:
			counts[planet.biomes[t]] += 1
		var land := 0
		for b in Biomes.count():
			if not Biomes.is_water(b):
				land += counts[b]
		var land_pct := 100.0 * land / planet.tile_count
		var parts: Array[String] = []
		for b in Biomes.count():
			if not Biomes.is_water(b):
				parts.append("%s %.0f%%" % [Biomes.display_name(b).split(" ")[0], 100.0 * counts[b] / land])
		print("  seed %d terrain %d ms, land %.1f%% | %s" % [
			world_seed, Time.get_ticks_msec() - t0, land_pct, ", ".join(parts)])
		_expect(absf(land_pct - 29.0) < 2.0, "land fraction near 29%")
		for b in Biomes.count():
			_expect(counts[b] > 0, "biome %s present" % Biomes.display_name(b))

	_check_weather(planet)
