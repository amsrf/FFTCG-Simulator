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
## The field has a thin body under the art. The raised bands supply the depth above it.
const FIELD_THICKNESS := 0.014
const CARD_EDGE_RADIUS := 0.03
const CARD_EDGE_CORNER_STEPS := 5
static var _edge_mesh_cache: ArrayMesh = null
static var _edge_material_cache: ShaderMaterial = null
## The wall is GLASS tinted by the card's element (user's call: the black wall showed once field cards got thick).
const GLASS_SHADER := preload("res://shaders/card_glass_edge.gdshader")
const ELEMENTS := preload("res://scripts/core/elements.gd")
const NEUTRAL_GLASS := Color(0.75, 0.82, 0.92)

static func install(card: Node3D, face: Vector2) -> void:
	if card.has_node("CardEdge"):
		return
	if _edge_mesh_cache == null:
		_edge_mesh_cache = _build_mesh(face, 1.0, CARD_EDGE_RADIUS)
	if _edge_material_cache == null:
		_edge_material_cache = ShaderMaterial.new()
		_edge_material_cache.shader = GLASS_SHADER
	var edge := MeshInstance3D.new()
	edge.name = "CardEdge"
	edge.mesh = _edge_mesh_cache
	edge.material_override = _edge_material_cache
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.scale = Vector3(1.0, CARD_EDGE_THICKNESS, 1.0)
	card.add_child(edge)

## The thickness a card has in `on_field` or not: the one place that decides it (Card.enter_zone calls this).
static func thickness_for(on_field: bool) -> float:
	return FIELD_THICKNESS if on_field else CARD_EDGE_THICKNESS

static func set_field_style(card: Node3D, on_field: bool) -> void:
	var edge := card.get_node_or_null("CardEdge") as MeshInstance3D
	if edge != null:
		edge.scale.y = thickness_for(on_field)
		edge.set_instance_shader_parameter("field_edge", on_field)

## The glass takes the card's element colour (its first element; neutral glass for none).
static func set_tint(card: Node3D, element: Variant) -> void:
	var edge := card.get_node_or_null("CardEdge") as GeometryInstance3D
	if edge == null:
		return
	var index: int = ELEMENTS.index_of(element)
	edge.set_instance_shader_parameter("tint", ELEMENTS.ACCENT[index] if index >= 0 else NEUTRAL_GLASS)

static func thickness_of(card: Node3D) -> float:
	var edge := card.get_node_or_null("CardEdge") as Node3D
	return edge.scale.y if edge != null else 0.0

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
