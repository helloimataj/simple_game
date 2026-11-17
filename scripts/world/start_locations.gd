class_name StartLocations
extends RefCounted
## Picks random starting tiles for players, spread out across the planet.
##
## Starts are drawn at random from good land (plains or forest with mostly land
## around it) and must be at least a minimum distance from every other start.
## The minimum begins at what an even spread over the land would allow and is
## relaxed step by step until everyone fits, so players are as far apart as the
## map and the player count permit. Deterministic for a seed.

## Starts are never closer than this many tiles, however crowded the map.
const MIN_TILES_APART := 4
## Share of tiles within 2 steps that must be land.
const MIN_LAND_AROUND := 0.6

const GOOD_BIOMES: Array[int] = [Biomes.Type.PLAINS, Biomes.Type.FOREST]
const POOR_BIOMES: Array[int] = [
	Biomes.Type.JUNGLE, Biomes.Type.SWAMP, Biomes.Type.DESERT, Biomes.Type.TUNDRA]


## Returns {tiles: Array[int], min_distance: float}. `min_distance` is the
## spacing (radians on the sphere) the starts were held to. `tiles` is shorter
## than `count` only if the planet has too little land.
static func pick(planet: Planet, count: int, world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "starts"])

	var candidates := _candidates(planet, GOOD_BIOMES)
	if candidates.size() < count * 4:
		candidates.append_array(_candidates(planet, POOR_BIOMES))
	_shuffle(candidates, rng)

	# An even spread over the land gives each player a cap of this angular size.
	var land_share := 0.29
	var spacing := 1.5 * sqrt(4.0 * PI * land_share / maxi(count, 1))
	var floor_spacing := MIN_TILES_APART * planet.tile_angle()
	var chosen: Array[int] = []
	while true:
		chosen = _place(planet, candidates, count, spacing)
		if chosen.size() >= count or spacing <= floor_spacing:
			break
		spacing = maxf(spacing * 0.9, floor_spacing)
	return {"tiles": chosen, "min_distance": spacing}


## Greedy pass: take candidates in order, skipping any too close to a start.
static func _place(planet: Planet, candidates: Array[int], count: int, spacing: float) -> Array[int]:
	var chosen: Array[int] = []
	var limit := cos(spacing)
	for tile in candidates:
		var dir := planet.centers[tile]
		var ok := true
		for other in chosen:
			if dir.dot(planet.centers[other]) > limit:
				ok = false
				break
		if ok:
			chosen.append(tile)
			if chosen.size() >= count:
				break
	return chosen


static func _candidates(planet: Planet, biomes: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for tile in planet.tile_count:
		if not biomes.has(planet.biomes[tile]):
			continue
		var near := planet.tiles_within(tile, 2)
		var land := 0
		for t: int in near:
			if not Biomes.is_water(planet.biomes[t]):
				land += 1
		if float(land) / near.size() >= MIN_LAND_AROUND:
			out.append(tile)
	return out


static func _shuffle(items: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp
