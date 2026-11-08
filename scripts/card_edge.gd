extends RefCounted
## CARD EDGE: gives every card a real side wall. Static only — the mesh and material are built once and shared.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache.

## CARDS HAVE THICKNESS. The art mesh is a single flat quad (its AABB is ~0 in y), which reads as
## a decal as soon as the camera is tilted. This builds a rounded-rectangle prism ONCE and shares
## it across every card, so the silhouette gets a real side wall without paying for a mesh per card.
##
## The prism matches the face's corner radius, so its outline cannot poke out past the rounded
## corners, and its top face is left open because the card art covers it.
const CARD_EDGE_THICKNESS := 0.02
const CARD_EDGE_RADIUS := 0.03
const CARD_EDGE_CORNER_STEPS := 5
static var _edge_mesh_cache: ArrayMesh = null
static var _edge_material_cache: StandardMaterial3D = null

static func install(card: Node3D, face: Vector2) -> void:
	if card.has_node("CardEdge"):
		return
	if _edge_mesh_cache == null:
		_edge_mesh_cache = _build_mesh(
			face, CARD_EDGE_THICKNESS, CARD_EDGE_RADIUS)
	if _edge_material_cache == null:
		_edge_material_cache = StandardMaterial3D.new()
		_edge_material_cache.albedo_color = Color(0.055, 0.06, 0.075)
		_edge_material_cache.metallic = 0.15
		_edge_material_cache.roughness = 0.55
		_edge_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge := MeshInstance3D.new()
	edge.name = "CardEdge"
	edge.mesh = _edge_mesh_cache
	edge.material_override = _edge_material_cache
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(edge)

static func _build_mesh(face: Vector2, thickness: float, radius: float) -> ArrayMesh:
	var hx: float = face.x * 0.5
	var hz: float = face.y * 0.5
	var r: float = minf(radius, minf(hx, hz))
	# Counter-clockwise in the XZ plane, starting at the top-right corner.
	var corners: Array = [
		[Vector2(hx - r, hz - r), 0.0],
		[Vector2(-(hx - r), hz - r), PI * 0.5],
		[Vector2(-(hx - r), -(hz - r)), PI],
		[Vector2(hx - r, -(hz - r)), PI * 1.5],
	]
	var outline: Array[Vector2] = []
	for corner in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		for step in range(CARD_EDGE_CORNER_STEPS + 1):
			var angle: float = start + (PI * 0.5) * (float(step) / CARD_EDGE_CORNER_STEPS)
			outline.append(centre + Vector2(cos(angle), sin(angle)) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = outline.size()
	for i in range(count):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		var side: Vector2 = (b - a).normalized()
		var normal := Vector3(side.y, 0.0, -side.x)
		st.set_normal(normal); st.add_vertex(Vector3(a.x, 0.0, a.y))
		st.set_normal(normal); st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.set_normal(normal); st.add_vertex(Vector3(b.x, -thickness, b.y))
		st.set_normal(normal); st.add_vertex(Vector3(a.x, 0.0, a.y))
		st.set_normal(normal); st.add_vertex(Vector3(b.x, -thickness, b.y))
		st.set_normal(normal); st.add_vertex(Vector3(a.x, -thickness, a.y))
	# Bottom cap, so the edge still reads on a card seen from below.
	var bottom_centre := Vector3(0.0, -thickness, 0.0)
	for i in range(count):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		st.set_normal(Vector3.DOWN); st.add_vertex(bottom_centre)
		st.set_normal(Vector3.DOWN); st.add_vertex(Vector3(b.x, -thickness, b.y))
		st.set_normal(Vector3.DOWN); st.add_vertex(Vector3(a.x, -thickness, a.y))
	return st.commit()
