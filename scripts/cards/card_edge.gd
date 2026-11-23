extends RefCounted
## CARD EDGE: gives every card a real side wall. Static only — the mesh and material are built once and shared.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache.

## CARDS HAVE THICKNESS. The art mesh is a single flat quad (its AABB is ~0 in y), which reads as
## a decal as soon as the camera is tilted. This builds a rounded-rectangle prism ONCE and shares
## it across every card, so the silhouette gets a real side wall without paying for a mesh per card.
##
## The prism matches the face's corner radius, so its outline cannot poke out past the rounded
## corners, and its top face is left open because the card art covers it.
## Cards in their card format (hand, deck, damage zone, stack, piles): thin, like real card stock (user's call).
const CARD_EDGE_THICKNESS := 0.006
## The field has a thin body under the art. The raised bands supply the depth above it.
const FIELD_THICKNESS := 0.014
const CARD_EDGE_RADIUS := 0.03
## Shared with card.tres: tools/build_card_mesh.tscn builds the printed mesh from this radius and step count, so the
## face and the wall have the same outline. Change either, re-run that tool.
const CARD_EDGE_CORNER_STEPS := 8
static var _edge_mesh_cache: ArrayMesh = null
static var _edge_material_cache: ShaderMaterial = null
## The wall is GLASS tinted by the card's element (user's call: the black wall showed once field cards got thick).
const GLASS_SHADER := preload("res://shaders/card_glass_edge.gdshader")
const ELEMENTS := preload("res://scripts/core/elements.gd")
const NEUTRAL_GLASS := Color(0.75, 0.82, 0.92)
## The printed card back (cropped from the source art to the card's 0.715 ratio). The prism's bottom cap wears it, so a
## card seen from below (the turned-over deck, a draw's flip) shows its back; Card.set_revealed() uses the same material
## for a face-down card's face.
const BACK_TEXTURE_PATH := "res://assets/card_back/crystal_card_back.png"
static var _back_material_cache: StandardMaterial3D = null

static func back_material() -> StandardMaterial3D:
	if _back_material_cache == null:
		_back_material_cache = StandardMaterial3D.new()
		_back_material_cache.albedo_texture = _back_texture()
		# UNSHADED, like the card face (card.gdshader). Lit, the ambient sky + overhead light lifted the art's black
		# (RGB ~14) to a grey ~70.
		_back_material_cache.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_back_material_cache.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _back_material_cache

## The imported texture when the editor has imported it, else the PNG read straight from disk.
static func _back_texture() -> Texture2D:
	# MIPMAPS ARE REQUIRED: the 858 px art is drawn ~100 px wide on a deck, and without them the thin frame and lattice
	# lines alias into jagged steps. The import asks for them, but a stale import (or none: a headless run never
	# imports a new file) would not have them, so they are generated here whenever they are missing.
	var image: Image = null
	if ResourceLoader.exists(BACK_TEXTURE_PATH):
		var imported := load(BACK_TEXTURE_PATH) as Texture2D
		if imported != null:
			image = imported.get_image()
	if image == null or image.is_empty():
		image = Image.load_from_file(ProjectSettings.globalize_path(BACK_TEXTURE_PATH))
	if image == null or image.is_empty():
		push_error("card_edge: card back texture missing at %s" % BACK_TEXTURE_PATH)
		return null
	if image.is_compressed():
		image.decompress()
	if not image.has_mipmaps():
		image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func install(card: Node3D, face: Vector2) -> void:
	if card.has_node("CardEdge"):
		return
	if _edge_mesh_cache == null:
		_edge_mesh_cache = _build_mesh(face, 1.0, CARD_EDGE_RADIUS)
	if _edge_material_cache == null:
		_edge_material_cache = ShaderMaterial.new()
		_edge_material_cache.shader = GLASS_SHADER
	_paint_printed_mesh(card)
	var edge := MeshInstance3D.new()
	edge.name = "CardEdge"
	edge.mesh = _edge_mesh_cache
	# Surface 0 is the glass wall, surface 1 the bottom cap with the card back.
	edge.set_surface_override_material(0, _edge_material_cache)
	edge.set_surface_override_material(1, back_material())
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.scale = Vector3(1.0, CARD_EDGE_THICKNESS, 1.0)
	card.add_child(edge)

## card.tres has three surfaces: Front (0, the card's own material), Border (1) and Back (2), and the last two carry NO
## material, so they drew in the engine's default WHITE, and they share this prism's outline (tools/build_card_mesh
## builds them from CARD_EDGE_RADIUS / CARD_EDGE_CORNER_STEPS), so they z-fight with its wall: white specks along a
## deck's sides. Painted ON THE SHARED MESH, not per card, because the teleport/hologram effects reset
## per-card overrides to null, which falls back to the mesh's material. Done once; the field mesh copies these.
static func _paint_printed_mesh(card: Node3D) -> void:
	var mesh_instance := card.get_node_or_null("HandMesh") as MeshInstance3D
	if mesh_instance == null or not (mesh_instance.mesh is ArrayMesh):
		return
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh.get_surface_count() < 3 or mesh.surface_get_material(2) != null:
		return
	mesh.surface_set_material(1, _edge_material_cache)
	mesh.surface_set_material(2, back_material())

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
	var mesh: ArrayMesh = st.commit()
	# Bottom cap, so a card seen from below shows its back. Its own surface (index 1) carries UVs: seen from below
	# with the card's top (local -Z) up, screen-right is local -X, so u runs from +X to -X and v from -Z to +Z.
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap_uv := func(p: Vector2) -> Vector2:
		return Vector2(0.5 - p.x / face.x, 0.5 + p.y / face.y)
	for i in range(count):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		cap.set_normal(Vector3.DOWN); cap.set_uv(Vector2(0.5, 0.5)); cap.add_vertex(Vector3(0.0, -thickness, 0.0))
		cap.set_normal(Vector3.DOWN); cap.set_uv(cap_uv.call(b)); cap.add_vertex(Vector3(b.x, -thickness, b.y))
		cap.set_normal(Vector3.DOWN); cap.set_uv(cap_uv.call(a)); cap.add_vertex(Vector3(a.x, -thickness, a.y))
	return cap.commit(mesh)
