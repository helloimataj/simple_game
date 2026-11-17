class_name Unit
extends RefCounted
## One unit on the map.

var id := 0
var type := UnitTypes.Type.INFANTRY
## Index into Players.list.
var owner := 0
var tile := -1
## Remaining hit points. Also the unit's base power in battle.
var hit_points := 0
var moves_left := 0


func data() -> Dictionary:
	return UnitTypes.info(type)


func display_name() -> String:
	return UnitTypes.display_name(type)
