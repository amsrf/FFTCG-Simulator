extends RefCounted
## Shared field geometry, typography, and artwork selection.

const ELEMENTS := preload("res://scripts/core/elements.gd")
const PRINTED_MESH := preload("res://assets/models/card.tres")
const LABEL_PIXEL_SIZE := 0.00055
const FACE := Vector2(0.429, 0.6)
const BAND_FRACTION := 0.13
const BAND_HEIGHT := 0.015
const BAND_CENTRE := FACE.y * (1.0 - BAND_FRACTION) * 0.5
const BEVEL := 0.004
const BEVEL_STEPS := 3
const MAX_PORTRAIT_STRETCH := 1.30
const RADIUS := 0.03
# Opus I type stripes are the colour reference. Keep a little depth for the raised satin bands.
const PALETTE := [
	Color("#ae3b28"), Color("#238fae"), Color("#308f5d"), Color("#d0b12d"),
	Color("#875d8d"), Color("#4f73a0"), Color("#a7a7b0"), Color("#535251"),
]
const DARK_INK := Color("#1a1b20")

# Hand-framed scan regions start below the printed name band and end above the type stripe.
const SCAN_SIZE := Vector2(429, 600)
const CROP_REGIONS := {
	"1-002R": Rect2(93, 65, 333, 290),
	"1-007R": Rect2(68, 65, 339, 290),
	"1-024C": Rect2(83, 65, 339, 290),
	"1-150R": Rect2(93, 66, 333, 289),
}

static var _mesh: ArrayMesh
static var _font: FontVariation
static var _portraits: Dictionary[String, Texture2D] = {}
var _heading: Node3D
var drawn_on_field := false


func enter_zone(mesh_instance: MeshInstance3D, material: ShaderMaterial, on_field: bool, revealed: bool,
		texture: Texture2D, code: String, title: String, cost: int, element: String) -> void:
	drawn_on_field = on_field
	if on_field:
		var index: int = ELEMENTS.index_of(element)
		material.set_shader_parameter("field_band_color", PALETTE[index] if index >= 0 else Color("#39363f"))
		var portrait := _field_portrait(code)
		material.set_shader_parameter("field_art_texture", portrait if portrait != null else texture)
		material.set_shader_parameter("field_art_rect",
			Vector4(0.0, 0.0, 1.0, 1.0) if portrait != null else illustration_crop(texture.get_size(), code))
		material.set_shader_parameter("field_band_fraction", BAND_FRACTION)
		if _heading == null:
			_build_heading(mesh_instance, title, cost, element)
	sync_reveal(mesh_instance, material, revealed)


func sync_reveal(mesh_instance: MeshInstance3D, material: ShaderMaterial, revealed: bool) -> void:
	var show_field := drawn_on_field and revealed
	var face_mesh: Mesh = _field_mesh() if show_field else PRINTED_MESH
	if mesh_instance.mesh != face_mesh:
		mesh_instance.mesh = face_mesh
	material.set_shader_parameter("field_face", show_field)


func show_heading(should_show: bool) -> void:
	if _heading != null:
		_heading.visible = drawn_on_field and should_show


static func label_color(element: String) -> Color:
	return DARK_INK if element == "光" else Color.WHITE


static func label_outline_size(element: String) -> int:
	match element:
		"土": return 4
		"氷", "風": return 2
		_: return 0


## Optional clean portraits use the printed card code. The source JPEG fallback also works before editor import.
static func _field_portrait(code: String) -> Texture2D:
	if _portraits.has(code):
		return _portraits[code]
	var path := "res://assets/field_art/%s.jpg" % code
	var texture: Texture2D
	if ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	if texture == null and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	if texture != null:
		_portraits[code] = texture
	return texture


static func label_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		var base := ThemeDB.fallback_font
		if base is FontFile:
			# Only the field labels use a distance field. The 2D UI keeps the default font settings.
			var distance_font := base.duplicate() as FontFile
			distance_font.msdf_size = 64
			distance_font.msdf_pixel_range = 12
			distance_font.multichannel_signed_distance_field = true
			base = distance_font
		_font.base_font = base
	return _font


## Standard FFTCG scans put the name/CP above this window and the type and rules stripes below it.
## Keep more of the wide illustration by allowing bounded vertical stretch instead of a tight centre crop.
static func illustration_crop(image_size: Vector2, code: String) -> Vector4:
	if CROP_REGIONS.has(code):
		var region: Rect2 = CROP_REGIONS[code]
		var origin := region.position / SCAN_SIZE
		var extent := region.size / SCAN_SIZE
		return Vector4(origin.x, origin.y, extent.x, extent.y)
	var layout := Rect2(0.0, 0.150, 1.0, 0.442)
	var target_aspect := FACE.x / (FACE.y * (1.0 - 2.0 * BAND_FRACTION))
	var window_aspect := layout.size.x * image_size.x / (layout.size.y * image_size.y)
	var crop_size := layout.size
	if window_aspect > target_aspect:
		crop_size.x *= minf(1.0, MAX_PORTRAIT_STRETCH * target_aspect / window_aspect)
	else:
		crop_size.y *= window_aspect / target_aspect
	var start := layout.get_center() - crop_size * 0.5
	return Vector4(start.x, start.y, crop_size.x, crop_size.y)


func _build_heading(parent: MeshInstance3D, title: String, cost: int, element: String) -> void:
	_heading = Node3D.new()
	_heading.name = "FieldHeading"
	_heading.position = Vector3(0.0, BAND_HEIGHT + 0.001, -BAND_CENTRE)
	parent.add_child(_heading)

	var cost_label := _add_label("Cost", str(cost), 100, element)
	cost_label.position.x = -FACE.x * 0.34
	var name_label := _add_label("CardName", title, 84, element)
	name_label.position.x = -FACE.x * 0.22
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var text_width: float = name_label.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.font_size).x
	var available_width := FACE.x * 0.67
	if text_width > 0.0:
		name_label.pixel_size = minf(name_label.pixel_size, available_width / text_width)


func _add_label(node_name: String, wording: String, size: int, element: String) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.rotation.x = -PI * 0.5
	label.font = label_font()
	label.font_size = size
	label.pixel_size = LABEL_PIXEL_SIZE
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	label.modulate = label_color(element)
	label.outline_modulate = DARK_INK
	label.outline_size = label_outline_size(element)
	label.double_sided = false
	label.text = wording
	_heading.add_child(label)
	return label


static func _field_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := FACE.x * 0.5
	var art_end := FACE.y * (0.5 - BAND_FRACTION)
	_quad(builder, Vector3(-half_width, 0, -art_end), Vector3(half_width, 0, -art_end),
		Vector3(half_width, 0, art_end), Vector3(-half_width, 0, art_end), Color.BLACK)
	for direction in [-1.0, 1.0]:
		var base := _band_loop(direction, 0.0, 0.0)
		var shoulder := _band_loop(direction, BAND_HEIGHT - BEVEL, 0.0)
		_join_band_loops(builder, base, shoulder, Color.BLACK)
		var lower := shoulder
		for step in range(1, BEVEL_STEPS + 1):
			var angle := PI * 0.5 * float(step) / BEVEL_STEPS
			var upper := _band_loop(direction, BAND_HEIGHT - BEVEL + BEVEL * sin(angle),
				BEVEL * (1.0 - cos(angle)))
			_join_band_loops(builder, lower, upper, Color(float(step) / BEVEL_STEPS, 0, 0))
			lower = upper
		for i in range(lower.size()):
			var next := (i + 1) % lower.size()
			_triangle(builder, Vector3(0.0, BAND_HEIGHT, -BAND_CENTRE * direction),
				lower[i], lower[next], Color(0.5, 0, 0))
	_mesh = builder.commit()
	# The original border and back remain usable by the zone transition effects.
	for surface in range(1, PRINTED_MESH.get_surface_count()):
		_mesh.add_surface_from_arrays(PRINTED_MESH.surface_get_primitive_type(surface),
			PRINTED_MESH.surface_get_arrays(surface))
		_mesh.surface_set_material(surface, PRINTED_MESH.surface_get_material(surface))
	return _mesh


static func _band_loop(direction: float, height: float, inset: float) -> PackedVector3Array:
	var half_width := FACE.x * 0.5 - inset
	var front := -FACE.y * 0.5 + inset
	var inner := front + FACE.y * BAND_FRACTION - 2.0 * inset
	var radius := RADIUS - inset
	var outline := PackedVector3Array()
	for side in [-1.0, 1.0]:
		var centre_x: float = side * (half_width - radius)
		var start := PI if side < 0.0 else PI * 1.5
		for step in range(6):
			var angle := start + PI * 0.5 * step / 5.0
			outline.append(Vector3(direction * (centre_x + cos(angle) * radius), height,
				direction * (front + radius + sin(angle) * radius)))
	outline.append(Vector3(direction * half_width, height, direction * inner))
	outline.append(Vector3(-direction * half_width, height, direction * inner))
	return outline


static func _join_band_loops(builder: SurfaceTool, lower: PackedVector3Array, upper: PackedVector3Array,
		tone: Color) -> void:
	for i in range(lower.size()):
		var next := (i + 1) % lower.size()
		_quad(builder, lower[i], lower[next], upper[next], upper[i], tone)


static func _quad(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tone: Color) -> void:
	_triangle(builder, a, b, c, tone)
	_triangle(builder, a, c, d, tone)


static func _triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tone: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point: Vector3 in [a, b, c]:
		builder.set_normal(normal)
		builder.set_color(tone)
		builder.set_uv(Vector2(point.x / FACE.x + 0.5, point.z / FACE.y + 0.5))
		builder.add_vertex(point)
