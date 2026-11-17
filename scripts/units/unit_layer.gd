class_name UnitLayer
extends Node3D
## Draws unit tokens on the globe.
##
## Each tile shows one token per (side, unit type) on it, coloured by side,
## with a number when there is more than one such unit. Shapes seen from above:
## infantry = disc, armor = square, artillery = diamond, aircraft = raised
## triangle, naval = long hull.

var planet: Planet
var units: UnitManager
var radius := 10.0

var _multimeshes: Array[MultiMesh] = []
var _labels: Node3D
var _rebuild_queued := false


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	for type in UnitTypes.count():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _token_mesh(type)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_multimeshes.append(mm)
	_labels = Node3D.new()
	add_child(_labels)


func setup(for_planet: Planet, unit_manager: UnitManager, globe_radius: float) -> void:
	if units != null and units.changed.is_connected(queue_rebuild):
		units.changed.disconnect(queue_rebuild)
	planet = for_planet
	units = unit_manager
	radius = globe_radius
	units.changed.connect(queue_rebuild)
	rebuild()


## Rebuilds once at the end of the frame, however many units changed.
func queue_rebuild() -> void:
	if not _rebuild_queued:
		_rebuild_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	for child in _labels.get_children():
		child.queue_free()
	var transforms: Array[Array] = []
	var colors: Array[Array] = []
	for type in UnitTypes.count():
		transforms.append([])
		colors.append([])

	var spacing := planet.tile_angle() * radius
	var token_size := spacing * 0.3
	for tile: int in units.occupied_tiles():
		var groups := units.stack_summary(tile)
		var keys := groups.keys()
		keys.sort()
		var up := planet.centers[tile]
		var east := Vector3.UP.cross(up)
		east = east.normalized() if east.length_squared() > 1e-6 else Vector3.RIGHT
		var north := up.cross(east)
		for i in keys.size():
			var owner: int = keys[i][0]
			var type: int = keys[i][1]
			var offset := Vector3.ZERO
			if keys.size() > 1:
				var angle := TAU * i / keys.size() + PI / 4.0
				offset = (east * cos(angle) + north * sin(angle)) * spacing * 0.3
			var origin := up * radius + offset
			var basis := Basis(east, up, -north).scaled(Vector3.ONE * token_size)
			transforms[type].append(Transform3D(basis, origin))
			colors[type].append(Players.list[owner]["color"])
			var count: int = groups[keys[i]]
			if count > 1:
				_labels.add_child(_count_label(count, origin + up * token_size * 2.2, token_size))

	for type in UnitTypes.count():
		var mm := _multimeshes[type]
		mm.instance_count = transforms[type].size()
		for i in transforms[type].size():
			mm.set_instance_transform(i, transforms[type][i])
			mm.set_instance_color(i, colors[type][i])


func _count_label(count: int, at: Vector3, token_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = str(count)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 16
	label.pixel_size = token_size / 70.0
	label.position = at
	return label


## Unit-sized meshes (about 1 wide, sitting on y = 0).
static func _token_mesh(type: int) -> Mesh:
	match type:
		UnitTypes.Type.INFANTRY:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 0.8
			mesh.radial_segments = 20
			return _raised(mesh, 0.4)
		UnitTypes.Type.ARMOR:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.0, 0.6, 1.0)
			return _raised(mesh, 0.3)
		UnitTypes.Type.AIRCRAFT:
			var mesh := PrismMesh.new()
			mesh.size = Vector3(1.2, 1.2, 0.25)
			# Lay the triangle flat, pointing north, hovering above the ground.
			return _raised(mesh, 1.4, Basis(Vector3.RIGHT, -PI / 2.0))
		UnitTypes.Type.ARTILLERY:
			# A diamond from above.
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.8, 0.5, 0.8)
			return _raised(mesh, 0.25, Basis(Vector3.UP, PI / 4.0))
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.55, 0.5, 1.5)
			return _raised(mesh, 0.25)


static func _raised(mesh: PrimitiveMesh, height: float, rotation := Basis.IDENTITY) -> ArrayMesh:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = rotation * verts[i] + Vector3(0.0, height, 0.0)
		normals[i] = rotation * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
