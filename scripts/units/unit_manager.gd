class_name UnitManager
extends RefCounted
## All units on a planet and which tile each one is on.
##
## Any number of units may share a tile. A unit may only be on a tile whose
## biome its type can enter (see UnitTypes.can_enter): land units on passable
## land, naval units on water, aircraft anywhere. Roads let vehicles into
## mountains and bridges let land units onto a shallow water tile.

signal changed

var planet: Planet
var units: Array[Unit] = []
## Optional: lets roads and bridges open up tiles (see placement_block_reason).
var buildings: BuildingManager

var _by_tile := {}  # tile id -> Array[Unit]
var _next_id := 1


func _init(for_planet: Planet) -> void:
	planet = for_planet


func can_place(type: int, tile: int) -> bool:
	return placement_block_reason(type, tile) == ""


## Empty if a unit of this type may be on the tile, otherwise why not.
func placement_block_reason(type: int, tile: int) -> String:
	if tile < 0 or tile >= planet.tile_count:
		return "No tile there"
	var biome := planet.biomes[tile]
	var reason := UnitTypes.entry_block_reason(type, biome)
	if reason == "" or buildings == null:
		return reason
	if UnitTypes.info(type)["domain"] == UnitTypes.Domain.LAND:
		# A bridge carries land units over water; a road takes vehicles
		# through otherwise impassable land such as mountains.
		if Biomes.is_water(biome):
			if buildings.has_type(tile, BuildingTypes.Type.BRIDGE):
				return ""
		elif buildings.has_type(tile, BuildingTypes.Type.ROAD):
			return ""
	return reason


## Creates a unit on a tile. Returns null if the tile is not valid for it.
func add_unit(type: int, owner: int, tile: int) -> Unit:
	if not can_place(type, tile):
		return null
	var unit := Unit.new()
	unit.id = _next_id
	_next_id += 1
	unit.type = type
	unit.owner = owner
	unit.tile = tile
	unit.hit_points = unit.data()["power"]
	unit.moves_left = unit.data()["movement"]
	units.append(unit)
	if not _by_tile.has(tile):
		_by_tile[tile] = [] as Array[Unit]
	_by_tile[tile].append(unit)
	changed.emit()
	return unit


func remove_unit(unit: Unit) -> void:
	if unit == null or not units.has(unit):
		return
	units.erase(unit)
	var stack: Array[Unit] = _by_tile[unit.tile]
	stack.erase(unit)
	if stack.is_empty():
		_by_tile.erase(unit.tile)
	unit.tile = -1
	changed.emit()


## Moves a unit to another tile. Returns false if the tile is not valid for it.
## (No movement-point or path rules yet.)
func relocate(unit: Unit, tile: int) -> bool:
	if not units.has(unit) or not can_place(unit.type, tile):
		return false
	var stack: Array[Unit] = _by_tile[unit.tile]
	stack.erase(unit)
	if stack.is_empty():
		_by_tile.erase(unit.tile)
	unit.tile = tile
	if not _by_tile.has(tile):
		_by_tile[tile] = [] as Array[Unit]
	_by_tile[tile].append(unit)
	changed.emit()
	return true


## Units on a tile, oldest first. Do not modify the returned array.
func units_at(tile: int) -> Array[Unit]:
	if _by_tile.has(tile):
		return _by_tile[tile]
	return [] as Array[Unit]


func occupied_tiles() -> Array:
	return _by_tile.keys()


## Counts of units on a tile grouped by owner and type: {[owner, type]: count}.
func stack_summary(tile: int) -> Dictionary:
	var out := {}
	for unit in units_at(tile):
		var key := [unit.owner, unit.type]
		out[key] = out.get(key, 0) + 1
	return out
