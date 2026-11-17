class_name TerrainGenerator
extends RefCounted
## Earth-like terrain for a Planet.
##
## 1. Tectonic plates: warped Voronoi regions on the sphere, each continental or
##    oceanic and drifting around its own axis. Colliding plates raise mountain
##    ranges, island arcs and trenches; separating plates make rifts.
## 2. Sea level is set so ~29% of the surface is land, as on Earth.
## 3. Climate: temperature from latitude and altitude, moisture from global
##    circulation bands (wet tropics, dry ~30°, wet ~55°) and distance from sea.
## 4. Biomes from altitude, temperature and moisture.
##
## Everything works in sphere coordinates rather than tile steps, so a given seed
## gives the same world at every map size, just at a different resolution.

const LAND_FRACTION := 0.29
const PLATE_COUNT := 16
const CONTINENTAL_PLATE_FRACTION := 0.4
## Angular width (radians) over which plate collisions shape the terrain.
const BOUNDARY_WIDTH := 0.07
## Share of land that is mountains & highlands.
const MOUNTAIN_FRACTION := 0.13
## Share of ocean that is shallow continental shelf.
const SHALLOW_FRACTION := 0.12

# Moisture by absolute latitude in degrees: Hadley/Ferrel/polar cells.
const MOISTURE_BY_LATITUDE := [
	[0.0, 1.0], [10.0, 0.9], [18.0, 0.5], [26.0, 0.12], [34.0, 0.25],
	[45.0, 0.62], [58.0, 0.72], [72.0, 0.4], [90.0, 0.2],
]


static func generate(planet: Planet, world_seed: int, progress := Callable()) -> void:
	var n := planet.tile_count
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	planet.elevation.resize(n)
	planet.temperature.resize(n)
	planet.moisture.resize(n)
	planet.biomes.resize(n)

	# --- Noise ------------------------------------------------------------
	var warp_x := _noise(rng.randi(), 1.3, 3)
	var warp_y := _noise(rng.randi(), 1.3, 3)
	var warp_z := _noise(rng.randi(), 1.3, 3)
	var continent := _noise(rng.randi(), 1.1, 5)
	var detail := _noise(rng.randi(), 4.0, 4)
	var ridges := _noise(rng.randi(), 2.5, 4)
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var climate := _noise(rng.randi(), 2.0, 3)
	var wetness := _noise(rng.randi(), 1.8, 4)

	# --- Plates -----------------------------------------------------------
	var plate_seed := PackedVector3Array()
	var plate_axis := PackedVector3Array()
	var plate_height := PackedFloat32Array()
	var plate_continental: Array[bool] = []
	var continental_count := roundi(PLATE_COUNT * CONTINENTAL_PLATE_FRACTION)
	for p in PLATE_COUNT:
		plate_seed.append(_random_dir(rng))
		plate_axis.append(_random_dir(rng) * rng.randf_range(0.4, 1.0))
		var is_continental := p < continental_count
		plate_continental.append(is_continental)
		plate_height.append(rng.randf_range(0.25, 0.45) if is_continental else rng.randf_range(-0.6, -0.4))

	# --- Elevation --------------------------------------------------------
	# How strongly plate collisions (plus ridged noise) push each tile up; used
	# to place mountains as ranges along plate boundaries rather than blobs.
	var uplift := PackedFloat32Array()
	uplift.resize(n)
	for t in n:
		var p := planet.centers[t]
		var q := (p + Vector3(
			warp_x.get_noise_3dv(p), warp_y.get_noise_3dv(p), warp_z.get_noise_3dv(p)) * 0.45).normalized()

		var i1 := 0
		var i2 := 0
		var d1 := -2.0
		var d2 := -2.0
		for i in PLATE_COUNT:
			var d := q.dot(plate_seed[i])
			if d > d1:
				d2 = d1; i2 = i1
				d1 = d; i1 = i
			elif d > d2:
				d2 = d; i2 = i
		var gap := acos(clampf(d2, -1.0, 1.0)) - acos(clampf(d1, -1.0, 1.0))
		var influence := exp(-gap / BOUNDARY_WIDTH)

		# Relative motion of the two plates across their shared boundary.
		var to_other := plate_seed[i2] - plate_seed[i1]
		to_other = (to_other - p * to_other.dot(p)).normalized()
		var v1 := plate_axis[i1].cross(p)
		var v2 := plate_axis[i2].cross(p)
		var convergence := clampf((v1 - v2).dot(to_other) / 1.2, -1.0, 1.0) * influence

		var base := lerpf(plate_height[i1], (plate_height[i1] + plate_height[i2]) * 0.5, influence * 0.5)
		var e := base + 0.45 * continent.get_noise_3dv(p) + 0.12 * detail.get_noise_3dv(p)

		var c1 := plate_continental[i1]
		var c2 := plate_continental[i2]
		var ridge := ridges.get_noise_3dv(p) * 0.5 + 0.5
		uplift[t] = maxf(convergence, 0.0) * (1.0 if c1 else 0.5) + 0.35 * ridge * ridge
		if convergence > 0.0:
			if c1 and c2:
				e += convergence * 0.9        # continental collision: great ranges
			elif c1:
				e += convergence * 0.7        # coastal ranges over a subducting plate
			elif c2:
				e -= convergence * 0.35       # ocean trench
			else:
				e += convergence * 0.4        # volcanic island arcs
		else:
			if c1 and c2:
				e += convergence * 0.3        # rift valleys
			else:
				e -= convergence * 0.12       # mid-ocean ridges
		e += 0.18 * ridge * influence
		planet.elevation[t] = e
		if progress.is_valid() and t % 10000 == 0:
			progress.call(0.6 * t / n)

	# Sea level so that LAND_FRACTION of tiles are land; rescale to -1..1.
	var sea := _percentile(planet.elevation, 1.0 - LAND_FRACTION)
	var lowest := _min(planet.elevation)
	var highest := _max(planet.elevation)
	for t in n:
		var e := planet.elevation[t]
		if e >= sea:
			planet.elevation[t] = (e - sea) / maxf(highest - sea, 1e-6)
		else:
			planet.elevation[t] = -(sea - e) / maxf(sea - lowest, 1e-6)
	if progress.is_valid():
		progress.call(0.65)

	# --- Distance from the sea (radians) ----------------------------------
	var coast_distance := _distance_from_water(planet)
	if progress.is_valid():
		progress.call(0.75)

	# --- Climate ----------------------------------------------------------
	for t in n:
		var p := planet.centers[t]
		var lat := absf(rad_to_deg(Planet.latitude_of(p)))
		var h := maxf(planet.elevation[t], 0.0)
		var temp := 1.0 - lat / 90.0
		temp -= h * 0.45
		temp += climate.get_noise_3dv(p) * 0.06
		planet.temperature[t] = clampf(temp, 0.0, 1.0)

		var continentality := clampf(coast_distance[t] / 0.45, 0.0, 1.0)
		var moist := _sample_curve(MOISTURE_BY_LATITUDE, lat)
		moist *= 1.0 - 0.5 * continentality
		moist += wetness.get_noise_3dv(p) * 0.3
		planet.moisture[t] = clampf(moist, 0.0, 1.0)
	if progress.is_valid():
		progress.call(0.85)

	# --- Biomes -----------------------------------------------------------
	var land_uplift := PackedFloat32Array()
	var ocean_elevations := PackedFloat32Array()
	for t in n:
		if planet.elevation[t] >= 0.0:
			uplift[t] += planet.elevation[t] * 0.4
			land_uplift.append(uplift[t])
		else:
			ocean_elevations.append(planet.elevation[t])
	var mountain_line := _percentile(land_uplift, 1.0 - MOUNTAIN_FRACTION)
	var shelf_line := _percentile(ocean_elevations, 1.0 - SHALLOW_FRACTION)

	for t in n:
		planet.biomes[t] = _classify(
			planet.elevation[t], uplift[t] >= mountain_line, planet.temperature[t],
			planet.moisture[t], coast_distance[t], shelf_line)
	if progress.is_valid():
		progress.call(1.0)


static func _classify(e: float, mountainous: bool, temp: float, moist: float,
		coast: float, shelf_line: float) -> int:
	if e < 0.0:
		return Biomes.Type.SHALLOW_WATER if e >= shelf_line else Biomes.Type.DEEP_OCEAN
	if mountainous:
		return Biomes.Type.MOUNTAINS
	if temp < 0.24:
		return Biomes.Type.TUNDRA
	if moist > 0.78 and e < 0.12 and temp > 0.3 and coast < 0.15:
		return Biomes.Type.SWAMP
	if temp > 0.7:
		if moist > 0.62:
			return Biomes.Type.JUNGLE
		if moist < 0.34:
			return Biomes.Type.DESERT
		return Biomes.Type.PLAINS
	if temp > 0.36:
		if moist < 0.22:
			return Biomes.Type.DESERT
		if moist < 0.48:
			return Biomes.Type.PLAINS
		return Biomes.Type.FOREST
	# Cold: steppe or boreal forest.
	if moist < 0.35:
		return Biomes.Type.PLAINS
	return Biomes.Type.FOREST


## Breadth-first distance from the nearest water tile, in radians.
static func _distance_from_water(planet: Planet) -> PackedFloat32Array:
	var n := planet.tile_count
	var steps := PackedInt32Array()
	steps.resize(n)
	steps.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n)
	var tail := 0
	for t in n:
		if planet.elevation[t] < 0.0:
			steps[t] = 0
			queue[tail] = t
			tail += 1
	var head := 0
	while head < tail:
		var t := queue[head]
		head += 1
		var next_step := steps[t] + 1
		for k in range(planet.neighbor_offsets[t], planet.neighbor_offsets[t + 1]):
			var nb := planet.neighbors[k]
			if steps[nb] < 0:
				steps[nb] = next_step
				queue[tail] = nb
				tail += 1
	var out := PackedFloat32Array()
	out.resize(n)
	var step_angle := planet.tile_angle()
	for t in n:
		out[t] = maxi(steps[t], 0) * step_angle
	return out


static func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


static func _random_dir(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	return v.normalized() if v.length_squared() > 1e-9 else Vector3.UP


static func _percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(fraction * sorted.size()), 0, sorted.size() - 1)]


static func _min(values: PackedFloat32Array) -> float:
	var m := INF
	for v in values:
		m = minf(m, v)
	return m


static func _max(values: PackedFloat32Array) -> float:
	var m := -INF
	for v in values:
		m = maxf(m, v)
	return m


static func _sample_curve(points: Array, x: float) -> float:
	for i in range(1, points.size()):
		if x <= points[i][0]:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	return points[-1][1]
