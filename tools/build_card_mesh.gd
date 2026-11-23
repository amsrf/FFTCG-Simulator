extends Node
## Rebuilds assets/models/card.tres, the printed card mesh, so its outline is EXACTLY the side wall's
## (scripts/cards/card_edge.gd: CARD_EDGE_RADIUS, CARD_EDGE_CORNER_STEPS), with nothing poking out past it.
##
##   godot --headless res://tools/build_card_mesh.tscn --quit-after 60
##
## Same three surfaces, same order (the code addresses them by index): Front (0, +Y at y 0), Border (1, the side ring
## down to -THICKNESS) and Back (2, -Y at -THICKNESS). The Front's UV mapping is FITTED from the existing mesh, so the
## card art lands exactly where it did. The Back uses the edge prism's bottom-cap mapping (card_edge.gd), so the
## printed back reads upright and unmirrored from below.

const CARD_EDGE := preload("res://scripts/cards/card_edge.gd")
const PATH := "res://assets/models/card.tres"
const FACE := Vector2(0.429, 0.6)
const THICKNESS := 0.003


func _ready() -> void:
	var old := load(PATH) as ArrayMesh
	var uid: int = ResourceLoader.get_resource_uid(PATH)
	var front_uv: Array = _fit_uv(old.surface_get_arrays(0))
	var front_up: bool = _faces_up(old.surface_get_arrays(0))
	print("[CardMesh] fitted front UV: u = %.4f x + %.4f z + %.4f, v = %.4f x + %.4f z + %.4f; front tri winds %s" % [
		front_uv[0].x, front_uv[0].y, front_uv[0].z, front_uv[1].x, front_uv[1].y, front_uv[1].z,
		"up" if front_up else "down"])

	var outline: Array[Vector2] = _outline()
	var mesh := ArrayMesh.new()

	# FRONT: a fan from the centre at y 0, normal +Y, wound like the old one.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = outline.size()
	var keep_order: bool = _new_front_up() == front_up
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var tri: Array = [Vector2.ZERO, a, b] if keep_order else [Vector2.ZERO, b, a]
		for p in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(_apply(front_uv, p))
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	st.index()
	st.commit(mesh)
	mesh.surface_set_name(0, "Front")

	# BORDER: the side ring, outward normals (its material is the wall's, which draws both sides).
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var side: Vector2 = (b - a).normalized()
		var normal := Vector3(side.y, 0.0, -side.x)
		for v in [Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3(b.x, -THICKNESS, b.y),
				Vector3(a.x, 0.0, a.y), Vector3(b.x, -THICKNESS, b.y), Vector3(a.x, -THICKNESS, a.y)]:
			st.set_normal(normal)
			st.set_uv(Vector2(float(i) / n, -v.y / THICKNESS))
			st.add_vertex(v)
	st.index()
	st.commit(mesh)
	mesh.surface_set_name(1, "Border")

	# BACK: normal -Y at -THICKNESS, wound and mapped like card_edge.gd's bottom cap.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		for p in [Vector2.ZERO, b, a]:
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(0.5 - p.x / FACE.x, 0.5 + p.y / FACE.y))
			st.add_vertex(Vector3(p.x, -THICKNESS, p.y))
	st.index()
	st.commit(mesh)
	mesh.surface_set_name(2, "Back")

	var err := ResourceSaver.save(mesh, PATH)
	# KEEP THE UID: card.tscn references the mesh by it, and a plain save of a new resource writes none.
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(PATH, uid)
	print("[CardMesh] %d outline points (radius %.3f, %d steps per corner), aabb %s, saved: %s" % [
		n, CARD_EDGE.CARD_EDGE_RADIUS, CARD_EDGE.CARD_EDGE_CORNER_STEPS, mesh.get_aabb(), error_string(err)])
	get_tree().quit()


## The wall's own outline (card_edge._build_mesh), so face and wall share every vertex.
func _outline() -> Array[Vector2]:
	var hx: float = FACE.x * 0.5
	var hz: float = FACE.y * 0.5
	var r: float = minf(CARD_EDGE.CARD_EDGE_RADIUS, minf(hx, hz))
	var corners: Array = [
		[Vector2(hx - r, hz - r), 0.0],
		[Vector2(-(hx - r), hz - r), PI * 0.5],
		[Vector2(-(hx - r), -(hz - r)), PI],
		[Vector2(hx - r, -(hz - r)), PI * 1.5],
	]
	var steps: int = CARD_EDGE.CARD_EDGE_CORNER_STEPS
	var outline: Array[Vector2] = []
	for corner in corners:
		for step in range(steps + 1):
			var angle: float = corner[1] + (PI * 0.5) * (float(step) / steps)
			outline.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	return outline


## Least-squares affine fit of the old Front's UVs: u, v = (a, b, c) . (x, z, 1).
func _fit_uv(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var sxx := 0.0; var sxz := 0.0; var sx := 0.0; var szz := 0.0; var sz := 0.0; var s1 := 0.0
	var bu := Vector3.ZERO
	var bv := Vector3.ZERO
	for i in range(verts.size()):
		var x: float = verts[i].x
		var z: float = verts[i].z
		sxx += x * x; sxz += x * z; sx += x; szz += z * z; sz += z; s1 += 1.0
		bu += Vector3(x, z, 1.0) * uvs[i].x
		bv += Vector3(x, z, 1.0) * uvs[i].y
	var m := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, s1))
	var inv := m.inverse()
	return [inv * bu, inv * bv]


func _apply(fit: Array, p: Vector2) -> Vector2:
	var q := Vector3(p.x, p.y, 1.0)
	return Vector2(fit[0].dot(q), fit[1].dot(q))


## Whether the old Front's first triangle's geometric normal ((p1 - p0) x (p2 - p0)) points +Y.
func _faces_up(arrays: Array) -> bool:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var p0: Vector3 = verts[idx[0]] if idx.size() > 0 else verts[0]
	var p1: Vector3 = verts[idx[1]] if idx.size() > 0 else verts[1]
	var p2: Vector3 = verts[idx[2]] if idx.size() > 0 else verts[2]
	return (p1 - p0).cross(p2 - p0).y > 0.0


## The new Front's first triangle [centre, a, b] has normal +Y when this returns true; used to match the old winding.
func _new_front_up() -> bool:
	var o: Array[Vector2] = _outline()
	var a := Vector3(o[0].x, 0, o[0].y)
	var b := Vector3(o[1].x, 0, o[1].y)
	return (a - Vector3.ZERO).cross(b - Vector3.ZERO).y > 0.0
