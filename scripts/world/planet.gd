class_name Planet
extends RefCounted
## Hex-tiled sphere (a Goldberg polyhedron) built from a subdivided icosahedron.
##
## Every vertex of the subdivided icosahedron becomes the centre of a tile. The
## 12 original icosahedron corners have 5 neighbours (pentagons); every other
## tile has 6 (hexagons). With an edge length of `frequency` tiles the planet
## has 10 * frequency^2 + 2 tiles.
##
## Tile data is stored in flat packed arrays indexed by tile id so the planet
## stays fast to build and cheap to hold in memory at 100k tiles.

const MIN_FREQUENCY := 20
const MAX_FREQUENCY := 100

var frequency := 0
var tile_count := 0

## Unit vector from the planet centre to each tile centre.
var centers := PackedVector3Array()

## Neighbours of tile `t` are neighbors[neighbor_offsets[t] .. neighbor_offsets[t + 1]],
## in counter-clockwise order seen from outside the planet.
var neighbor_offsets := PackedInt32Array()
var neighbors := PackedInt32Array()

## Parallel to `neighbors`: corner k of a tile is the centre of triangle
## corner_tris[offset + k], and lies between neighbour k and neighbour k + 1.
var corner_tris := PackedInt32Array()
## Unit-sphere centre of every triangle of the subdivided icosahedron.
var tri_centers := PackedVector3Array()

# Filled in by TerrainGenerator.
var elevation := PackedFloat32Array()   # roughly -1..1, 0 = sea level
var temperature := PackedFloat32Array() # 0 (polar) .. 1 (equatorial)
var moisture := PackedFloat32Array()    # 0 (arid) .. 1 (wet)
var biomes := PackedByteArray()         # Biomes.Type


static func tile_count_for(edge_length: int) -> int:
	return 10 * edge_length * edge_length + 2


func degree(tile: int) -> int:
	return neighbor_offsets[tile + 1] - neighbor_offsets[tile]


func get_neighbors(tile: int) -> PackedInt32Array:
	return neighbors.slice(neighbor_offsets[tile], neighbor_offsets[tile + 1])


## Approximate angular distance (radians) between neighbouring tile centres.
func tile_angle() -> float:
	return sqrt(4.0 * PI / tile_count)


## Latitude in radians (+ north) of a direction.
static func latitude_of(dir: Vector3) -> float:
	return asin(clampf(dir.y, -1.0, 1.0))


## Longitude in radians (+ east) of a direction.
static func longitude_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


## Returns the tile whose centre is closest to `dir` (need not be normalised).
## Walks greedily across the tile graph from `start`, which is very fast when
## `start` is near the answer (e.g. the previously hovered tile).
func find_tile(dir: Vector3, start := 0) -> int:
	if tile_count == 0:
		return -1
	var target := dir.normalized()
	var current := clampi(start, 0, tile_count - 1)
	var best := centers[current].dot(target)
	while true:
		var next := -1
		for k in range(neighbor_offsets[current], neighbor_offsets[current + 1]):
			var nb := neighbors[k]
			var d := centers[nb].dot(target)
			if d > best:
				best = d
				next = nb
		if next < 0:
			return current
		current = next
	return current


## Builds the tile geometry. `progress` is called with values 0..1.
func build(edge_length: int, progress := Callable()) -> void:
	frequency = clampi(edge_length, 1, 1000)
	var n := frequency
	tile_count = tile_count_for(n)

	var ico := _icosahedron()
	var ico_verts: PackedVector3Array = ico[0]
	var ico_faces: PackedInt32Array = ico[1]

	centers.resize(tile_count)
	for i in 12:
		centers[i] = ico_verts[i]
	var next_vertex := 12

	# Points on the 30 icosahedron edges, shared by the two faces that meet there.
	# Key: lower corner * 12 + higher corner -> index of the first interior point.
	var edge_base := {}

	var tri_count := 20 * n * n
	var tris := PackedInt32Array()
	tris.resize(tri_count * 3)
	var tri_write := 0

	var row_len := (n + 1) * (n + 2) / 2
	var local := PackedInt32Array()
	local.resize(row_len)

	for f in 20:
		var ia := ico_faces[f * 3]
		var ib := ico_faces[f * 3 + 1]
		var ic := ico_faces[f * 3 + 2]
		var a := ico_verts[ia]
		var ab := (ico_verts[ib] - a) / n
		var ac := (ico_verts[ic] - a) / n

		# Make sure the shared edge points exist.
		for pair in [[ia, ib], [ia, ic], [ib, ic]]:
			var lo: int = mini(pair[0], pair[1])
			var hi: int = maxi(pair[0], pair[1])
			var key := lo * 12 + hi
			if not edge_base.has(key):
				edge_base[key] = next_vertex
				var plo := ico_verts[lo]
				var step := (ico_verts[hi] - plo) / n
				for k in range(1, n):
					centers[next_vertex] = (plo + step * k).normalized()
					next_vertex += 1

		# Map every grid point (i along A->B, j along A->C) of this face to a vertex.
		var li := 0
		for i in n + 1:
			for j in n + 1 - i:
				var v: int
				if i == 0 and j == 0:
					v = ia
				elif i == n:
					v = ib
				elif j == n:
					v = ic
				elif j == 0:
					v = _edge_vertex(edge_base, ia, ib, i, n)
				elif i == 0:
					v = _edge_vertex(edge_base, ia, ic, j, n)
				elif i + j == n:
					v = _edge_vertex(edge_base, ib, ic, j, n)
				else:
					v = next_vertex
					centers[v] = (a + ab * i + ac * j).normalized()
					next_vertex += 1
				local[li] = v
				li += 1

		# Emit the n^2 small triangles of this face.
		for i in n:
			var row := i * (n + 1) - (i * (i - 1)) / 2
			var next_row := row + (n + 1 - i)
			for j in n - i:
				tris[tri_write] = local[row + j]
				tris[tri_write + 1] = local[next_row + j]
				tris[tri_write + 2] = local[row + j + 1]
				tri_write += 3
				if j < n - i - 1:
					tris[tri_write] = local[next_row + j]
					tris[tri_write + 1] = local[next_row + j + 1]
					tris[tri_write + 2] = local[row + j + 1]
					tri_write += 3
		if progress.is_valid():
			progress.call(0.3 * (f + 1) / 20.0)

	assert(next_vertex == tile_count)
	assert(tri_write == tri_count * 3)

	# Triangle centres become tile corners.
	tri_centers.resize(tri_count)
	for t in tri_count:
		tri_centers[t] = (centers[tris[t * 3]] + centers[tris[t * 3 + 1]] + centers[tris[t * 3 + 2]]).normalized()
	if progress.is_valid():
		progress.call(0.45)

	# Count triangles around each vertex, then bucket them.
	neighbor_offsets.resize(tile_count + 1)
	neighbor_offsets.fill(0)
	for k in tri_count * 3:
		neighbor_offsets[tris[k] + 1] += 1
	for v in tile_count:
		neighbor_offsets[v + 1] += neighbor_offsets[v]

	var slots := tri_count * 3
	var inc_next := PackedInt32Array() # vertex after v in the triangle (CCW)
	var inc_prev := PackedInt32Array() # vertex before v
	var inc_tri := PackedInt32Array()
	inc_next.resize(slots)
	inc_prev.resize(slots)
	inc_tri.resize(slots)
	var fill := neighbor_offsets.slice(0, tile_count)
	for t in tri_count:
		var v0 := tris[t * 3]
		var v1 := tris[t * 3 + 1]
		var v2 := tris[t * 3 + 2]
		var s := fill[v0]
		inc_next[s] = v1; inc_prev[s] = v2; inc_tri[s] = t
		fill[v0] = s + 1
		s = fill[v1]
		inc_next[s] = v2; inc_prev[s] = v0; inc_tri[s] = t
		fill[v1] = s + 1
		s = fill[v2]
		inc_next[s] = v0; inc_prev[s] = v1; inc_tri[s] = t
		fill[v2] = s + 1
	if progress.is_valid():
		progress.call(0.7)

	# Walk around each vertex to order its neighbours and corners CCW.
	neighbors.resize(slots)
	corner_tris.resize(slots)
	for v in tile_count:
		var start := neighbor_offsets[v]
		var end := neighbor_offsets[v + 1]
		var cur := start
		for out in range(start, end):
			neighbors[out] = inc_next[cur]
			corner_tris[out] = inc_tri[cur]
			var want := inc_prev[cur]
			for s in range(start, end):
				if inc_next[s] == want:
					cur = s
					break
		if progress.is_valid() and v % 20000 == 0:
			progress.call(0.7 + 0.3 * v / tile_count)
	if progress.is_valid():
		progress.call(1.0)


static func _edge_vertex(edge_base: Dictionary, from: int, to: int, k: int, n: int) -> int:
	if from < to:
		return edge_base[from * 12 + to] + k - 1
	return edge_base[to * 12 + from] + (n - k) - 1


## Regular icosahedron: [unit vertices, faces wound counter-clockwise from outside].
static func _icosahedron() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var raw := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var verts := PackedVector3Array()
	for v in raw:
		verts.append((v as Vector3).normalized())
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	# Force counter-clockwise winding when viewed from outside.
	for f in 20:
		var a := verts[faces[f * 3]]
		var b := verts[faces[f * 3 + 1]]
		var c := verts[faces[f * 3 + 2]]
		if (b - a).cross(c - a).dot(a + b + c) < 0.0:
			var tmp := faces[f * 3 + 1]
			faces[f * 3 + 1] = faces[f * 3 + 2]
			faces[f * 3 + 2] = tmp
	return [verts, faces]
