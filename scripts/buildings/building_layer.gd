class_name BuildingLayer
extends Node3D
## Draws buildings on the globe.
##
## A tile with buildings gets a hexagonal plate in its owner's colour, with one
## small block per building around the rim, coloured by building category.

var planet: Planet
var buildings: BuildingManager
var radius := 10.0

var _plates := MultiMesh.new()
var _blocks := MultiMesh.new()
var _rebuild_queued := false


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8

	var plate := CylinderMesh.new()
	plate.top_radius = 0.5
	plate.bottom_radius = 0.5
	plate.height = 0.06
	plate.radial_segments = 6
	plate.rings = 1
	var block := BoxMesh.new()
	block.size = Vector3(1.0, 1.0, 1.0)

	for pair in [[_plates, plate], [_blocks, block]]:
		var mm: MultiMesh = pair[0]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pair[1]
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


func setup(for_planet: Planet, building_manager: BuildingManager, globe_radius: float) -> void:
	if buildings != null and buildings.changed.is_connected(queue_rebuild):
		buildings.changed.disconnect(queue_rebuild)
	planet = for_planet
	buildings = building_manager
	radius = globe_radius
	buildings.changed.connect(queue_rebuild)
	rebuild()


## Rebuilds once at the end of the frame, however many buildings changed.
func queue_rebuild() -> void:
	if not _rebuild_queued:
		_rebuild_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	var tiles := buildings.occupied_tiles()
	var spacing := planet.tile_angle() * radius
	var block_size := spacing * 0.1

	var block_count := 0
	for tile: int in tiles:
		block_count += buildings.buildings_at(tile).size()
	_plates.instance_count = tiles.size()
	_blocks.instance_count = block_count

	var b := 0
	for i in tiles.size():
		var tile: int = tiles[i]
		var here := buildings.buildings_at(tile)
		var up := planet.centers[tile]
		var east := Vector3.UP.cross(up)
		east = east.normalized() if east.length_squared() > 1e-6 else Vector3.RIGHT
		var north := up.cross(east)
		var frame := Basis(east, up, -north)

		var plate_scale := Vector3(spacing * 0.7, spacing, spacing * 0.7)
		_plates.set_instance_transform(i, Transform3D(frame * Basis.from_scale(plate_scale), up * radius))
		var owner_color: Color = UnitManager.PLAYERS[here[0].owner]["color"]
		_plates.set_instance_color(i, owner_color.darkened(0.25))

		var slots := maxi(here.size(), 8)
		var ring := spacing * 0.3
		for k in here.size():
			var angle := TAU * k / slots + PI / 2.0
			var offset := (east * cos(angle) + north * sin(angle)) * ring
			var origin := up * (radius + block_size * 0.5 + spacing * 0.03) + offset
			_blocks.set_instance_transform(b, Transform3D(frame.scaled(Vector3.ONE * block_size), origin))
			_blocks.set_instance_color(b, BuildingTypes.category_color(here[k].type))
			b += 1
