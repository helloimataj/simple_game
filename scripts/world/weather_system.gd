class_name WeatherSystem
extends RefCounted
## Per-tile weather that changes every turn.
##
## Weather fronts are noise fields that drift around the planet's axis and
## slowly change shape. Wet climates see more of them than deserts. Each turn
## a fixed share of the planet is overcast, raining or storming, so the mix
## stays steady while the fronts move.
##
## Mud / Deep Snow is a ground condition: land that has been rained or snowed
## on stays soaked for a turn or so after the front has passed. It lingers
## where it is cold and dries quickly in deserts.
##
## Deterministic for a given planet and seed.

## Share of tiles with at least this much weather each turn.
const OVERCAST_SHARE := 0.48
const RAIN_SHARE := 0.2
const STORM_SHARE := 0.06

## Degrees the fronts drift around the axis per turn.
const DRIFT_DEGREES_PER_TURN := 4.0
## How quickly fronts change shape (noise-space units per turn).
const EVOLUTION_PER_TURN := 0.05

const SOAK_FROM_RAIN := 0.5
const SOAK_FROM_STORM := 0.8
const MUD_THRESHOLD := 0.4

var planet: Planet
var turn := 0
## Weather.Type per tile for the current turn.
var current := PackedByteArray()

var _ground := PackedFloat32Array() # how soaked / snowed-in each tile is
var _fronts: FastNoiseLite
var _cells: FastNoiseLite
var _evolution_dir := Vector3.ZERO


func setup(for_planet: Planet, world_seed: int) -> void:
	planet = for_planet
	turn = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "weather"])
	_fronts = _noise(rng.randi(), 1.6, 4)
	_cells = _noise(rng.randi(), 5.0, 3)
	_evolution_dir = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	current.resize(planet.tile_count)
	current.fill(Weather.Type.CLEAR)
	_ground.resize(planet.tile_count)
	_ground.fill(0.0)
	advance()


func weather_at(tile: int) -> int:
	return current[tile]


## Moves the weather on by one turn.
func advance() -> void:
	turn += 1
	var n := planet.tile_count
	var drift := Basis(Vector3.UP, deg_to_rad(DRIFT_DEGREES_PER_TURN) * turn)
	var evolution := _evolution_dir * (EVOLUTION_PER_TURN * turn)

	var intensity := PackedFloat32Array()
	intensity.resize(n)
	for t in n:
		var q := drift * planet.centers[t] + evolution
		intensity[t] = _fronts.get_noise_3dv(q) + 0.35 * _cells.get_noise_3dv(q) \
			+ 0.45 * (planet.moisture[t] - 0.5)

	var sorted := intensity.duplicate()
	sorted.sort()
	var overcast_line := sorted[int((1.0 - OVERCAST_SHARE) * (n - 1))]
	var rain_line := sorted[int((1.0 - RAIN_SHARE) * (n - 1))]
	var storm_line := sorted[int((1.0 - STORM_SHARE) * (n - 1))]

	for t in n:
		var value := intensity[t]
		var biome := planet.biomes[t]
		var land := not Biomes.is_water(biome)
		var weather := Weather.Type.CLEAR
		if value >= storm_line:
			weather = Weather.Type.STORM
			_ground[t] = minf(_ground[t] + SOAK_FROM_STORM, 1.5)
		elif value >= rain_line:
			weather = Weather.Type.HEAVY_RAIN
			_ground[t] = minf(_ground[t] + SOAK_FROM_RAIN, 1.5)
		else:
			# The ground dries out (or the snow melts) once the front has passed.
			var keep := 0.6
			if biome == Biomes.Type.DESERT:
				keep = 0.3
			elif planet.temperature[t] < Weather.FREEZING or biome == Biomes.Type.SWAMP:
				keep = 0.8
			_ground[t] *= keep
			if land and _ground[t] >= MUD_THRESHOLD:
				weather = Weather.Type.MUD
			elif value >= overcast_line:
				weather = Weather.Type.OVERCAST
		current[t] = weather


## RGBA8 pixel data for the weather overlay texture, laid out like the tile
## colour texture (see PlanetMesh). RGB = overlay colour, A = overlay strength.
func build_overlay_data() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(PlanetMesh.TEXTURE_WIDTH * PlanetMesh.texture_height(planet) * 4)
	var palette: Array[Color] = []
	for w in Weather.count():
		palette.append(Weather.overlay_color(w))
	for t in planet.tile_count:
		var col := palette[current[t]]
		var o := t * 4
		data[o] = col.r8
		data[o + 1] = col.g8
		data[o + 2] = col.b8
		data[o + 3] = col.a8
	return data


static func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise
