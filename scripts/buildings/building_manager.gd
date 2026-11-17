class_name BuildingManager
extends RefCounted
## All buildings on a planet and which tile each one is on.
##
## A tile can hold any number of buildings, but only one of each type, and all
## of them must belong to the same side.

signal changed

var planet: Planet
var buildings: Array[Building] = []

var _by_tile := {}  # tile id -> Array[Building]
var _next_id := 1


func _init(for_planet: Planet) -> void:
	planet = for_planet


func can_place(type: int, owner: int, tile: int) -> bool:
	return placement_block_reason(type, owner, tile) == ""


## Empty if the side may build this type on the tile, otherwise why not.
func placement_block_reason(type: int, owner: int, tile: int) -> String:
	if tile < 0 or tile >= planet.tile_count:
		return "No tile there"
	var data := BuildingTypes.info(type)
	var name: String = data["name"]
	var biome := planet.biomes[tile]
	var water := Biomes.is_water(biome)
	match data["placement"]:
		BuildingTypes.Placement.BRIDGE:
			if biome != Biomes.Type.SHALLOW_WATER or not _touches(tile, false):
				return "%s must be on shallow water next to land" % name
		BuildingTypes.Placement.COASTAL:
			if water or not _touches(tile, true):
				return "%s must be on land next to water" % name
		_:
			if water:
				return "%s must be on land" % name
	if data["forbidden_biomes"].has(biome):
		return "%s cannot be built on %s" % [name, Biomes.display_name(biome)]
	var tile_owner := owner_of(tile)
	if tile_owner >= 0 and tile_owner != owner:
		return "%s already has buildings here" % UnitManager.PLAYERS[tile_owner]["name"]
	if has_type(tile, type):
		return "There is already a %s here" % name
	if data["unique"] and count_of(type, owner) > 0:
		return "Only one %s per side" % name
	return ""


## Creates a building. Returns null if it cannot stand there.
func add_building(type: int, owner: int, tile: int) -> Building:
	if not can_place(type, owner, tile):
		return null
	var building := Building.new()
	building.id = _next_id
	_next_id += 1
	building.type = type
	building.owner = owner
	building.tile = tile
	buildings.append(building)
	if not _by_tile.has(tile):
		_by_tile[tile] = [] as Array[Building]
	_by_tile[tile].append(building)
	changed.emit()
	return building


func remove_building(building: Building) -> void:
	if building == null or not buildings.has(building):
		return
	buildings.erase(building)
	var here: Array[Building] = _by_tile[building.tile]
	here.erase(building)
	if here.is_empty():
		_by_tile.erase(building.tile)
	building.tile = -1
	changed.emit()


## Buildings on a tile, oldest first. Do not modify the returned array.
func buildings_at(tile: int) -> Array[Building]:
	if _by_tile.has(tile):
		return _by_tile[tile]
	return [] as Array[Building]


func occupied_tiles() -> Array:
	return _by_tile.keys()


## Whether the tile has a building of this type (owned by `owner`, if given).
func has_type(tile: int, type: int, owner := -1) -> bool:
	for building in buildings_at(tile):
		if building.type == type and (owner < 0 or building.owner == owner):
			return true
	return false


## Side that owns the buildings on a tile, or -1 if there are none.
func owner_of(tile: int) -> int:
	var here := buildings_at(tile)
	return here[0].owner if not here.is_empty() else -1


func count_of(type: int, owner: int) -> int:
	var total := 0
	for building in buildings:
		if building.type == type and building.owner == owner:
			total += 1
	return total


func owned_by(owner: int) -> Array[Building]:
	var out: Array[Building] = []
	for building in buildings:
		if building.owner == owner:
			out.append(building)
	return out


## Whether any neighbour of the tile is water (want_water) or land.
func _touches(tile: int, want_water: bool) -> bool:
	for k in range(planet.neighbor_offsets[tile], planet.neighbor_offsets[tile + 1]):
		if Biomes.is_water(planet.biomes[planet.neighbors[k]]) == want_water:
			return true
	return false
