extends RefCounted
## HOW A CHARACTER IS PLAYED (modelled on ~/Desktop/Clips/play, frames 148-202, 60 fps). Owned by Card as
## `card.hologram`. Pure presentation: it never touches the rules, and the real card is only hidden and shown.
##
##   play_out()  where the card was cast it turns into a translucent hologram in its element's colour, its printed face
##               gives way to a line drawing, and that dissolves from the bottom up, shedding sparks  (148-163)
##   play_in()   a faint line drawing of the card comes out of where it left and CROSSES THE BOARD to its slot
##               (170-180), sharpens there (181-188), fills with white light (189-191), and the real card is there
##               (192). Then, our addition: it SLAMS onto the board from a hand's height, kicking up dust, and a big card
##               jolts the camera (193-196): no jolt for cost 0-4, small for 5-7, bigger for 8+ (Field.slam_tier).
## The reference's empty beat between the two (164-169) is dropped, and every beat is slower than the clip (user: the
## clip's speed was too fast to read). A field card is a solid piece from the moment it appears (card_edge.gd).
##
## The crystal block-build (card_teleport.gd play_in) is kept, unused, for a special play some day.
##
## Preloaded by PATH (no class_name): see card_teleport.gd.

const BLUEPRINT_SHADER := preload("res://shaders/card_blueprint.gdshader")
const HOLOGRAM_SHADER := preload("res://shaders/card_hologram.gdshader")
const ELEMENTS := preload("res://scripts/core/elements.gd")
const CARD_EDGE := preload("res://scripts/cards/card_edge.gd")

## Reference timings (frames at 60 fps).
const FPS := 60.0
## How high over its slot the drawing hovers and the card appears, before it slams down (world metres).
const SLAM_HEIGHT := 0.35
## With no departure to leave from (a card put onto the field out of a hidden zone): the drawing comes down from here.
const FALLBACK_HEIGHT := 0.6
## The line drawing's quad reaches this far past the card, for the construction lines.
const BLUEPRINT_MARGIN := 0.1
const SLAM_DUST := preload("res://scripts/vfx/slam_dust.gd")
## Camera jolt per slam tier, in PIXELS at 1080 p for the card's depth (the reference: ~10 px).
const JOLT_PIXELS: Array[float] = [0.0, 5.0, 11.0]
## The reference's whole-frame shift on frames 193-197 relative to the peak, then still.
const JOLT_KEYS: Array[float] = [0.0, 1.0, 0.35, 0.65, -0.12, 0.0]
## A bigger card's jolt plays a little slower, so it reads as heavier.
const JOLT_STRETCH: Array[float] = [1.0, 1.0, 1.4]
const DEFAULT_TINT := Color(0.55, 0.87, 0.98)

var _card: Node3D
## Probe hooks: what is on screen right now. "" | "travel" | "hold" | "fill" | "drop" | "landed".
var phase: String = ""
var source_ghost: MeshInstance3D = null
var blueprint: MeshInstance3D = null
var _tween: Tween = null
## Where play_out() left the card (its face's pose), for the drawing to leave from.
var _depart_from: Transform3D = Transform3D.IDENTITY
var _has_departure: bool = false

static var _jolt_tween: Tween = null
static var _jolt_camera: Camera3D = null
static var _jolt_home: Vector3 = Vector3.ZERO

func _init(card: Node3D) -> void:
	_card = card

func tint() -> Color:
	var index: int = ELEMENTS.index_of(_card.get("element"))
	return ELEMENTS.ACCENT[index] if index >= 0 else DEFAULT_TINT

## The whole departure, on a stand-in left where the card is drawn right now; the real card is hidden at once and is
## free to be moved to its slot. Frees itself. Returns its length in seconds.
func play_out() -> float:
	_card.stop_hand_layout()
	_card.stop_stack_layout()
	var source := _card.get_node_or_null("HandMesh") as MeshInstance3D
	if source == null or _card.mat == null or not _card.is_inside_tree() or not _card.visible:
		_card.visible = false
		return 0.0
	var colour := tint()
	var seed_value := float(_card.get_instance_id() % 997)
	var ghost := MeshInstance3D.new()
	ghost.name = "HologramGhost"
	ghost.mesh = source.mesh
	var mat := ShaderMaterial.new()
	mat.shader = HOLOGRAM_SHADER
	mat.set_shader_parameter("texture_albedo", _card.mat.get_shader_parameter("texture_albedo"))
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("seed", seed_value)
	mat.render_priority = 2
	ghost.set_surface_override_material(0, mat)
	var hidden := _discard_material()
	for surface in range(1, source.mesh.get_surface_count()):
		ghost.set_surface_override_material(surface, hidden)
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card.get_tree().root.add_child(ghost)
	ghost.global_transform = source.global_transform
	source_ghost = ghost
	_depart_from = source.global_transform
	_has_departure = true
	# The line drawing rides on the hologram, a hair in front of its face.
	var lines := _make_blueprint(colour, seed_value)
	lines.position = Vector3(0.0, 0.003, 0.0)
	ghost.add_child(lines)
	var lines_mat := lines.material_override as ShaderMaterial
	lines_mat.set_shader_parameter("intensity", 0.0)
	_card.visible = false
	var t := ghost.create_tween()
	# The art drains into the hologram and the lines come up through it.
	t.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("holo", v)
		lines_mat.set_shader_parameter("intensity", 1.1 * v), 0.0, 1.0, out_holo_seconds)
	t.tween_callback(func() -> void:
		_sparks(ghost.global_transform, colour, 14, 0.55, 0.35, false))
	# The face fades out from under the lines, and both dissolve from the bottom up.
	t.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("dissolve", minf(v * 1.6, 1.0))
		lines_mat.set_shader_parameter("dissolve", v), 0.0, 1.0, out_dissolve_seconds)
	t.tween_callback(ghost.queue_free)
	return out_holo_seconds + out_dissolve_seconds

## The arrival at the card's CURRENT transform (the caller has already put the hidden card on its slot). The drawing
## leaves from where play_out() left the card (or from above the slot when there was no departure), crosses the board
## to hover over the slot, sharpens, fills with white light, and the real card appears there and SLAMS down onto the
## slot: dust, the field pulse's tier, and the camera jolt. Awaitable: returns once the card has hit the board; the
## light, dust and jolt finish on their own.
func play_in(tier: int) -> void:
	if not _card.is_inside_tree():
		_card.visible = true
		return
	_card.visible = false
	var colour := tint()
	var seed_value := float(_card.get_instance_id() % 991)
	var face_mesh := _card.get_node_or_null("HandMesh") as Node3D
	var home: Transform3D = face_mesh.global_transform if face_mesh != null else _card.global_transform
	var hover := home.translated(Vector3.UP * SLAM_HEIGHT)
	var from: Transform3D = _depart_from if _has_departure else home.translated(Vector3.UP * FALLBACK_HEIGHT)
	_has_departure = false
	var lines := _make_blueprint(colour, seed_value)
	_card.get_tree().root.add_child(lines)
	_add_slab_outline(lines, colour, seed_value)
	blueprint = lines
	var mat := lines.material_override as ShaderMaterial
	lines.global_transform = from
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("crisp", 0.0)
	_set_slab(lines, 0.0, 0.0)
	phase = "travel"
	var from_q := from.basis.get_rotation_quaternion()
	var to_q := hover.basis.get_rotation_quaternion()
	var from_s := from.basis.get_scale()
	var to_s := hover.basis.get_scale()
	var t := lines.create_tween()
	_tween = t
	# 1. Out of where the card left, across the board to hover over its slot, fading in as it goes.
	t.tween_method(func(v: float) -> void:
		var eased: float = v * v * (3.0 - 2.0 * v)
		var basis := Basis(from_q.slerp(to_q, eased)).scaled(from_s.lerp(to_s, eased))
		lines.global_transform = Transform3D(basis, from.origin.lerp(hover.origin, eased))
		var shown: float = smoothstep(0.0, 0.45, v)
		mat.set_shader_parameter("intensity", 0.7 * shown)
		mat.set_shader_parameter("crisp", 0.3 * v)
		_set_slab(lines, 0.45 * shown, 0.3 * v), 0.0, 1.0, travel_seconds)
	# 2. Holds over the slot, sharpening and brightening.
	t.tween_callback(func() -> void: phase = "hold")
	t.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("intensity", 0.7 + 0.65 * v)
		mat.set_shader_parameter("crisp", 0.3 + 0.7 * v)
		_set_slab(lines, 0.45 + 0.35 * v, 0.3 + 0.7 * v), 0.0, 1.0, hold_seconds)
	# 3. Fills with white light.
	t.tween_callback(func() -> void: phase = "fill")
	t.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("fill", v), 0.0, 1.0, fill_seconds)
	await t.finished
	# The card may have left the field while its drawing was still crossing (a response killed it): it is drawn in its
	# new zone by then, so only the drawing goes.
	if not is_instance_valid(_card) or not _card.is_drawn_on_field():
		phase = ""
		blueprint = null
		if is_instance_valid(lines):
			lines.queue_free()
		return
	# 4. The card is there, over its slot, a solid piece already, and drops onto the board.
	phase = "drop"
	var rest: Vector3 = _card.position
	var lift: Vector3 = _card.get_parent().global_basis.inverse() * (Vector3.UP * SLAM_HEIGHT)
	_card.position = rest + lift
	_card.visible = true
	_fade_light(lines, mat)
	var drop := _card.create_tween()
	drop.tween_property(_card, "position", rest, drop_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# The light rides ON the falling card, a hair above its face: left at the hover height it was coplanar with the
	# card for the first frame and z-fought into a white wedge.
	var ride := func() -> void:
		if is_instance_valid(lines) and is_instance_valid(face_mesh):
			lines.global_transform = face_mesh.global_transform.translated(Vector3.UP * 0.006)
	ride.call()
	drop.parallel().tween_method(func(_v: float) -> void: ride.call(), 0.0, 1.0, drop_seconds)
	await drop.finished
	if not is_instance_valid(_card):
		return
	_card.position = rest
	# 5. Impact.
	phase = "landed"
	blueprint = null
	SLAM_DUST.spawn(_card, home, tier)
	if tier > 0:
		jolt(_card, tier)

## Timings (seconds). The reference runs this in ~0.6 s at 60 fps; at our play rate that was too fast to read, so each
## beat is longer. Static so a probe or demo can set them in one place.
static var out_holo_seconds := 0.10       # ref 148-151: the art drains into the hologram
static var out_dissolve_seconds := 0.28   # ref 152-163: it dissolves
static var travel_seconds := 0.32         # ref 170-180: the drawing crosses to the slot
static var hold_seconds := 0.22           # ref 181-188: it sharpens over the slot
static var fill_seconds := 0.10           # ref 189-191: white fill
static var drop_seconds := 0.12           # the card falls the last SLAM_HEIGHT and hits the board
static var flash_seconds := 0.14          # the drawing's light leaving the card

## Total time from the start of play_in() until the card hits the board.
static func seconds_to_land() -> float:
	return travel_seconds + hold_seconds + fill_seconds + drop_seconds

func _fade_light(lines: MeshInstance3D, mat: ShaderMaterial) -> void:
	if not is_instance_valid(lines):
		return
	var out := lines.create_tween()
	out.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("fill", 1.0 - v)
		mat.set_shader_parameter("intensity", 1.35 * (1.0 - v) * (1.0 - v))
		_set_slab(lines, 0.8 * (1.0 - v) * (1.0 - v), 1.0), 0.0, 1.0, flash_seconds)
	out.tween_callback(lines.queue_free)

## The drawing is a SOLID PIECE too: its outline repeated at the field thickness under the face, so the drawing reads
## as the slab the card will be.
func _add_slab_outline(lines: MeshInstance3D, colour: Color, seed_value: float) -> void:
	var under := _make_blueprint(colour, seed_value)
	under.name = "SlabOutline"
	var m := under.material_override as ShaderMaterial
	m.set_shader_parameter("outline_only", true)
	under.position = Vector3(0.0, -CARD_EDGE.FIELD_THICKNESS, 0.0)
	lines.add_child(under)

func _set_slab(lines: MeshInstance3D, intensity: float, crisp: float) -> void:
	var under := lines.get_node_or_null("SlabOutline") as MeshInstance3D
	if under == null:
		return
	var m := under.material_override as ShaderMaterial
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("crisp", crisp)

func _make_blueprint(colour: Color, seed_value: float) -> MeshInstance3D:
	var face: Vector2 = _card._card_face_size()
	var quad_size := face + Vector2.ONE * BLUEPRINT_MARGIN * 2.0
	var plane := PlaneMesh.new()
	plane.size = quad_size
	var mat := ShaderMaterial.new()
	mat.shader = BLUEPRINT_SHADER
	mat.set_shader_parameter("card_size", face)
	mat.set_shader_parameter("quad_size", quad_size)
	mat.set_shader_parameter("line_color", colour)
	mat.set_shader_parameter("seed", seed_value)
	mat.render_priority = 3
	var node := MeshInstance3D.new()
	node.name = "CardBlueprint"
	node.mesh = plane
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 1.0
	return node

static var _hidden_material: ShaderMaterial = null
static func _discard_material() -> ShaderMaterial:
	if _hidden_material == null:
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
		_hidden_material = ShaderMaterial.new()
		_hidden_material.shader = shader
	return _hidden_material

static var _spark_material: StandardMaterial3D = null
## A one-shot burst of small additive sparks over a card laid at `at` (its face plane): spread over the face, or along
## its outline when `on_rim`. They drift up and fade. Frees itself.
func _sparks(at: Transform3D, colour: Color, amount: int, lifetime: float, rise: float, on_rim: bool) -> void:
	if not _card.is_inside_tree():
		return
	if _spark_material == null:
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		dot.gradient = g
		_spark_material = StandardMaterial3D.new()
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_material.vertex_color_use_as_albedo = true
		_spark_material.albedo_texture = dot
		_spark_material.no_depth_test = false
		_spark_material.render_priority = 4
	var face: Vector2 = _card._card_face_size()
	var basis_scale: Vector3 = at.basis.get_scale()
	var half := Vector2(face.x * 0.5 * basis_scale.x, face.y * 0.5 * basis_scale.z)
	var p := CPUParticles3D.new()
	p.name = "CardPlaySparks"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.03
	quad.material = _spark_material
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.gravity = Vector3(0.0, rise, 0.0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.direction = Vector3.UP
	p.spread = 70.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r, colour.g, colour.b, 1.0))
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	p.color_ramp = ramp
	if on_rim:
		var points := PackedVector3Array()
		for i in 24:
			var side := i % 4
			var u := randf() * 2.0 - 1.0
			match side:
				0: points.append(Vector3(u * half.x, 0.0, -half.y))
				1: points.append(Vector3(u * half.x, 0.0, half.y))
				2: points.append(Vector3(-half.x, 0.0, u * half.y))
				_: points.append(Vector3(half.x, 0.0, u * half.y))
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		p.emission_points = points
	else:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(half.x, 0.005, half.y)
	_card.get_tree().root.add_child(p)
	# Rotation about Y only: the points are laid in the card's plane, the sparks still rise in world Y.
	var yaw := Basis.from_euler(Vector3(0.0, at.basis.get_euler().y, 0.0))
	p.global_transform = Transform3D(yaw, at.origin + Vector3.UP * 0.01)
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)

## The landing jolt: the board camera knocked toward the card and up the screen, then damped back over a few frames,
## shaped like the reference's measured whole-frame shift. Sized in screen pixels at the card's depth.
static func jolt(card: Node3D, tier: int) -> void:
	if tier <= 0 or card == null or not card.is_inside_tree():
		return
	var camera := card.get_viewport().get_camera_3d()
	if camera == null:
		return
	if _jolt_tween != null and _jolt_tween.is_valid():
		_jolt_tween.kill()
		if is_instance_valid(_jolt_camera):
			_jolt_camera.global_position = _jolt_home
	_jolt_camera = camera
	_jolt_home = camera.global_position
	var index: int = clampi(tier, 0, JOLT_PIXELS.size() - 1)
	var viewport_h: float = maxf(card.get_viewport().get_visible_rect().size.y, 1.0)
	var depth: float = maxf(-(camera.global_transform.affine_inverse() * card.global_position).z, 0.5)
	var metres_per_px: float = 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / viewport_h
	var amount: float = JOLT_PIXELS[index] * (viewport_h / 1080.0) * metres_per_px
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		amount = JOLT_PIXELS[index] * (viewport_h / 1080.0) * camera.size / viewport_h
	# Toward the card's side of the screen (the reference: 18 px across, 12 px up at 4K), straight up for a centred card.
	var screen := camera.unproject_position(card.global_position)
	var width: float = maxf(card.get_viewport().get_visible_rect().size.x, 1.0)
	var across: float = clampf((screen.x - width * 0.5) / (width * 0.15), -1.0, 1.0)
	var dir: Vector3 = (camera.global_basis.x * across * 1.5 + camera.global_basis.y).normalized()
	var frame_seconds: float = JOLT_STRETCH[index] / FPS
	var total: float = frame_seconds * float(JOLT_KEYS.size() - 1)
	var home := _jolt_home
	var t := card.get_tree().create_tween()
	_jolt_tween = t
	t.tween_method(func(seconds: float) -> void:
		if not is_instance_valid(camera):
			return
		var k: float = seconds / frame_seconds
		var i: int = mini(int(k), JOLT_KEYS.size() - 2)
		var f: float = JOLT_KEYS[i] + (JOLT_KEYS[i + 1] - JOLT_KEYS[i]) * clampf(k - float(i), 0.0, 1.0)
		camera.global_position = home + dir * amount * f, 0.0, total, total)
	t.tween_callback(func() -> void:
		if is_instance_valid(camera):
			camera.global_position = home)

static func is_jolting() -> bool:
	return _jolt_tween != null and _jolt_tween.is_valid()
