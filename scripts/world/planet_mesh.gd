class_name PlanetMesh
extends RefCounted
## Builds render data for a Planet.
##
## Each tile is a triangle fan (centre + its 5 or 6 corners). Tile colours are
## not baked into vertices; each vertex carries its tile's cell in a colour
## lookup texture (UV2), so recolouring tiles later (selection, fog of war,
## ownership) only means updating the texture.
##
## UV.x is 0 at a tile centre and 1 on its outline, used by the shader to draw
## tile borders.

const TEXTURE_WIDTH := 1024


## Returns the arrays for ArrayMesh.add_surface_from_arrays (thread-safe).
static func build_arrays(planet: Planet, radius: float) -> Array:
	var vertex_count := planet.tile_count + planet.neighbors.size()
	var index_count := planet.neighbors.size() * 3

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	positions.resize(vertex_count)
	normals.resize(vertex_count)
	uv.resize(vertex_count)
	uv2.resize(vertex_count)
	indices.resize(index_count)

	var center_uv := Vector2(0.0, 0.0)
	var corner_uv := Vector2(1.0, 0.0)
	var v := 0
	var w := 0
	for t in planet.tile_count:
		var cell := Vector2(t % TEXTURE_WIDTH, t / TEXTURE_WIDTH)
		var start := planet.neighbor_offsets[t]
		var count := planet.neighbor_offsets[t + 1] - start
		var c := planet.centers[t]
		var center_index := v
		positions[v] = c * radius
		normals[v] = c
		uv[v] = center_uv
		uv2[v] = cell
		v += 1
		for k in count:
			var corner := planet.tri_centers[planet.corner_tris[start + k]]
			positions[v] = corner * radius
			normals[v] = corner
			uv[v] = corner_uv
			uv2[v] = cell
			v += 1
		# Godot treats clockwise triangles as front-facing.
		for k in count:
			indices[w] = center_index
			indices[w + 1] = center_index + 1 + (k + 1) % count
			indices[w + 2] = center_index + 1 + k
			w += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## RGBA8 pixel data for the tile colour lookup texture (thread-safe).
## RGB is the biome colour; A holds the biome id.
static func build_color_data(planet: Planet) -> PackedByteArray:
	var height := texture_height(planet)
	var data := PackedByteArray()
	data.resize(TEXTURE_WIDTH * height * 4)
	var palette: Array[Color] = []
	for b in Biomes.count():
		palette.append(Biomes.color(b))
	for t in planet.tile_count:
		var col := palette[planet.biomes[t]]
		var o := t * 4
		data[o] = col.r8
		data[o + 1] = col.g8
		data[o + 2] = col.b8
		data[o + 3] = planet.biomes[t]
	return data


static func texture_height(planet: Planet) -> int:
	return int(ceil(float(planet.tile_count) / TEXTURE_WIDTH))


static func create_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_color_texture(planet: Planet, data: PackedByteArray) -> ImageTexture:
	var image := Image.create_from_data(TEXTURE_WIDTH, texture_height(planet), false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(image)
