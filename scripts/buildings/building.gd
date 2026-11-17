class_name Building
extends RefCounted
## One building on the map.

var id := 0
var type := BuildingTypes.Type.BARRACKS
## Index into Players.list.
var owner := 0
var tile := -1


func data() -> Dictionary:
	return BuildingTypes.info(type)


func display_name() -> String:
	return BuildingTypes.display_name(type)
