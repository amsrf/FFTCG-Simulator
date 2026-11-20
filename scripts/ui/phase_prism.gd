extends Node3D
## A faceted crystal with three broad reading faces, beveled edges and tapered ends. Its crown sits just above
## the carved socket in the board. A phase change brings the next reading face up with a 120-degree roll.
## Blender/build_phase_cradle.py shares the cavity dimensions and CENTRE below. Rebuild and export both seats
## after changing the socket. Fed by Game.phase_entered. World coordinates are fixed for both seats.

const CRYSTAL_SHADER := preload("res://shaders/mana_crystal.gdshader")
const FONT := preload("res://assets/fonts/FOT-NewRodin Pro EB.otf")

const NAMES: Array[String] = ["Active Phase", "Draw Phase", "Main Phase 1", "Attack Phase", "Main Phase 2", "End Phase"]
const STEP_NAMES: Array[String] = ["Attack Preparation Step", "Attack Declaration Step", "Block Declaration Step",
	"Damage Resolution Step"]
enum Slot { ACTIVE, DRAW, MAIN_1, ATTACK, MAIN_2, END }

## Dimensions before cutting the three long edges of the triangular cross section.
const FACE_WIDTH := 0.194
const LENGTH := 0.98
const EDGE_CUT := 0.18
const END_CUT := 0.115
const END_SCALE := 0.38
const CRADLE_TOP_Y := 0.073
const FACE_ABOVE_LIP := 0.033
const CAVITY_LENGTH := 0.998
const CAVITY_WIDTH := 0.179
const CAVITY_FLOOR_Y := -0.053
## The axis (the triangle's centre) sits one inradius under the top face.
const INRADIUS := FACE_WIDTH / (2.0 * 1.7320508)
const CENTRE := Vector3(-2.85, CRADLE_TOP_Y + FACE_ABOVE_LIP - INRADIUS, -0.85)

const FONT_SIZE := 48
const PIXEL_SIZE := 0.0011
## THE TURN is a damped spring: it flicks past the new face (~16 degrees), swings back a little and settles, ending
## exactly on the face. ROLL_SECONDS is the whole settle; SPRING_DAMPING / SPRING_WOBBLE shape it (see _spring()).
const ROLL_SECONDS := 0.85
const SPRING_DAMPING := 6.0
const SPRING_WOBBLE := 3.0
const COLOUR_SECONDS := 0.4
## A little darker than the payment crystals, with a GRADIENT across the face (lighter at its top edge on screen,
## darker toward the bottom): mana_crystal.gdshader's gradient_* uniforms read the vertex colour _build_mesh writes.
const YOUR_COLOUR := Color(0.24, 0.47, 0.92)
const THEIR_COLOUR := Color(0.74, 0.06, 0.13)
const EMISSION := 0.30
const GRADIENT_TOP := 1.34
const GRADIENT_BOTTOM := 0.49
const TURN := TAU / 3.0
## Tilt the reading face toward the camera so the near bevel recedes and the far bevel shows.
const REST_TILT := -12.0 * PI / 180.0

var _prism: MeshInstance3D
var _material: ShaderMaterial
var _labels: Array[Label3D] = []   # one per face (3)
var _angle := 0.0                  # roll progress about world X, before the visual rest tilt
var _face := 0                     # the face that is up (or coming up)
var _roll: Tween
var _tint_tween: Tween
var _slot := -1
var _step := -1
var _yours := true

func _ready() -> void:
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, CENTRE)
	_prism = MeshInstance3D.new()
	_prism.name = "Prism"
	_prism.mesh = _build_mesh()
	_material = ShaderMaterial.new()
	_material.shader = CRYSTAL_SHADER
	_material.set_shader_parameter("tint", YOUR_COLOUR)
	_material.set_shader_parameter("paid", 1.0)
	_material.set_shader_parameter("emission_energy", EMISSION)
	_material.set_shader_parameter("pulse", 0.0)
	_material.set_shader_parameter("roughness_value", 0.2)
	_material.set_shader_parameter("occlusion_y", CAVITY_FLOOR_Y)
	_material.set_shader_parameter("occlusion_depth", CRADLE_TOP_Y - CAVITY_FLOOR_Y)
	_material.set_shader_parameter("occlusion_floor", 0.32)
	_material.set_shader_parameter("gradient_amount", 1.0)
	_material.set_shader_parameter("gradient_top", GRADIENT_TOP)
	_material.set_shader_parameter("gradient_bottom", GRADIENT_BOTTOM)
	_material.set_shader_parameter("facet_seam_pixels", 0.8)
	_material.render_priority = 2
	_prism.material_override = _material
	_prism.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_prism)
	for f in 3:
		_labels.append(_face_label(f))
	visible = false

## Face f's outward normal in the PRISM's frame: faces at -f * 120 degrees round X, so turning forward (+120) brings
## the next face up.
static func face_normal(f: int) -> Vector3:
	var phi := -float(f) * TURN
	return Vector3(0.0, cos(phi), sin(phi))

## Up the face, for reading: the text runs along world -X (screen right); on the top face this is screen up.
static func _face_up(f: int) -> Vector3:
	return face_normal(f).cross(Vector3.LEFT)

## The label font as a MULTI-CHANNEL SIGNED DISTANCE FIELD: crisp at any size and angle. A copy, so other users of
## the font are untouched.
static var _msdf: FontFile = null
static func _crisp_font() -> FontFile:
	if _msdf == null:
		_msdf = FONT.duplicate()
		_msdf.multichannel_signed_distance_field = true
		_msdf.msdf_pixel_range = 24
		_msdf.msdf_size = 64
		_msdf.generate_mipmaps = true
	return _msdf

func _face_label(f: int) -> Label3D:
	var label := Label3D.new()
	label.font = _crisp_font()
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.outline_size = 5
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0.02, 0.03, 0.08, 0.85)
	label.double_sided = false
	label.shaded = false
	label.render_priority = 4
	label.outline_render_priority = 3
	var n := face_normal(f)
	label.transform = Transform3D(Basis(Vector3.LEFT, _face_up(f), n), n * (INRADIUS + 0.002))
	_prism.add_child(label)
	return label

func _write_face(f: int, text: String) -> void:
	var label := _labels[f]
	var width := label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE).x
	label.pixel_size = minf(PIXEL_SIZE, (LENGTH - 2.0 * END_CUT - 0.05) / width)
	label.text = text

func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LENGTH * 0.5
	var corners: Array[Vector2] = []
	for f in 3:
		var angle := TURN * (0.5 - f)
		corners.append(Vector2(cos(angle), sin(angle)) * INRADIUS * 2.0)
	var profile: Array[Vector2] = []
	for f in 3:
		var a := corners[f]
		var b := corners[(f + 1) % 3]
		profile.append(a.lerp(b, EDGE_CUT))
		profile.append(b.lerp(a, EDGE_CUT))
	var rings: Array[PackedVector3Array] = []
	var positions := [-half, -half + END_CUT, half - END_CUT, half]
	var scales := [END_SCALE, 1.0, 1.0, END_SCALE]
	for ring in positions.size():
		var vertices := PackedVector3Array()
		for p in profile:
			vertices.append(Vector3(positions[ring], p.x * scales[ring], p.y * scales[ring]))
		rings.append(vertices)

	for ring in rings.size() - 1:
		for i in profile.size():
			var j := (i + 1) % profile.size()
			var a := rings[ring][i]
			var b := rings[ring][j]
			var c := rings[ring + 1][j]
			var d := rings[ring + 1][i]
			var normal := (b - a).cross(c - a).normalized()
			if normal.dot(Vector3(0.0, a.y + b.y, a.z + b.z)) < 0.0:
				normal = -normal
			# Even sides carry the labels. The narrow bevels and tapered ends have their own tones.
			var reading_face := i % 2 == 0
			var edge_tone := 0.82 if ring == 1 else (0.65 if reading_face else 0.28)
			var shade_a := 0.2 if reading_face and ring == 1 else edge_tone
			var shade_b := 0.36 if reading_face and ring == 1 else edge_tone
			# Both triangles share one set of facet UVs, so the shader traces only the facet perimeter.
			_tri(st, a, b, c, normal, Vector3(shade_a, shade_b, shade_b),
				[Vector2.ZERO, Vector2.DOWN, Vector2.ONE])
			_tri(st, a, c, d, normal, Vector3(shade_a, shade_b, shade_a),
				[Vector2.ZERO, Vector2.ONE, Vector2.RIGHT])
	for ring: int in [0, rings.size() - 1]:
		var normal := Vector3.LEFT if ring == 0 else Vector3.RIGHT
		for i in range(1, profile.size() - 1):
			_tri(st, rings[ring][0], rings[ring][i], rings[ring][i + 1], normal, Vector3.ONE * 0.65)
	return st.commit()

## Godot expects clockwise winding seen from outside. Keep each facet's explicit flat normal.
func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, outward: Vector3, shade: Vector3,
		uv: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)]) -> void:
	var vertices := [p0, p1, p2]
	var order := [0, 1, 2]
	if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(outward)
		st.set_color(Color(shade[i], 0.0, 0.0))
		st.set_uv(uv[i])
		st.add_vertex(vertices[i])

func _process(_delta: float) -> void:
	_prism.basis = Basis(Vector3.RIGHT, _angle + REST_TILT)
	_fade_labels()

## ONE NAME AT A TIME: a label shows only while its face is up. The other faces are under the lip anyway; mid-turn
## the outgoing and incoming names cross-fade.
func _fade_labels() -> void:
	for f in 3:
		var off := wrapf(_angle - float(f) * TURN, -PI, PI)
		var a := smoothstep(0.55, 0.95, cos(off))
		_labels[f].modulate.a = a
		_labels[f].outline_modulate.a = 0.85 * a
		_labels[f].visible = a > 0.001

## Game.phase_entered. `yours` = the local player is the turn player.
func show_phase(phase: int, yours: bool) -> void:
	var slot := slot_for(phase)
	# The combat-end step keeps the last step's face (it would otherwise turn back to "Attack Phase" for a moment).
	if slot < 0 or phase == GlobalVariables.Phase.COMBAT_END_STEP:
		return
	_step = step_for(phase)
	var text := STEP_NAMES[_step] if _step >= 0 else NAMES[slot]
	if yours != _yours or not visible:
		_set_colour(yours, visible)
	_yours = yours
	if not visible:
		_slot = slot
		_write_face(_face, text)
		_angle = float(_face) * TURN
		visible = true
		return
	_slot = slot
	# EVERY change of name turns it, the Attack Phase's steps included (Preparation -> Declaration -> Block -> Damage).
	if text == _labels[_face].text:
		return
	# Write the name on the hidden face that comes up next, then turn it up. Always forward.
	_face = (_face + 1) % 3
	_write_face(_face, text)
	if _roll != null and _roll.is_valid():
		_roll.kill()
	# From wherever it is (mid-wobble included) to the next face up, never backwards.
	var from := _angle
	var target := float(_face) * TURN
	while target <= from + 0.001:
		target += TAU
	_roll = create_tween()
	_roll.tween_method(func(p: float) -> void: _angle = lerpf(from, target, _spring(p)), 0.0, 1.0, ROLL_SECONDS)

## A damped spring from 0 to 1 over p in 0..1: rises fast, overshoots (~13% of the turn), swings back, settles. The
## (1 - p) factor on the wobble makes it land exactly on the next face's resting pose.
static func _spring(p: float) -> float:
	return 1.0 - exp(-SPRING_DAMPING * p) * cos(SPRING_WOBBLE * PI * p) * (1.0 - p)

func _apply_tint(c: Color) -> void:
	_material.set_shader_parameter("tint", c)

func _set_colour(yours: bool, animate: bool) -> void:
	var to := YOUR_COLOUR if yours else THEIR_COLOUR
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	if not animate:
		_apply_tint(to)
		return
	var from: Color = _material.get_shader_parameter("tint")
	_tint_tween = create_tween()
	_tint_tween.tween_method(_apply_tint, from, to, COLOUR_SECONDS)

## Which phase name a phase shows (every Attack Phase step belongs to ATTACK), or -1.
static func slot_for(phase: int) -> int:
	match phase:
		GlobalVariables.Phase.ACTIVE_PHASE: return Slot.ACTIVE
		GlobalVariables.Phase.DRAW_PHASE: return Slot.DRAW
		GlobalVariables.Phase.FIRST_MAIN_PHASE: return Slot.MAIN_1
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP, GlobalVariables.Phase.ATTACK_DECLARATION_STEP, \
				GlobalVariables.Phase.BLOCKER_DECLARATION_STEP, GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP, \
				GlobalVariables.Phase.COMBAT_END_STEP:
			return Slot.ATTACK
		GlobalVariables.Phase.SECOND_MAIN_PHASE: return Slot.MAIN_2
		GlobalVariables.Phase.END_PHASE: return Slot.END
	return -1

## The Attack Phase step the face names (an index into STEP_NAMES), or -1 for the phase itself.
static func step_for(phase: int) -> int:
	match phase:
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP: return 0
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP: return 1
		GlobalVariables.Phase.BLOCKER_DECLARATION_STEP: return 2
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP: return 3
	return -1

## Probe hooks.
func shown_slot() -> int:
	return _slot

## The face currently up, measured from the roll (0..2).
func up_face() -> int:
	return posmod(roundi(_angle / TURN), 3)

## The text on the face that is up.
func shown_text() -> String:
	return _labels[up_face()].text

func is_rolling() -> bool:
	return _roll != null and _roll.is_valid() and _roll.is_running()

func label_alpha(f: int) -> float:
	return _labels[f].modulate.a if _labels[f].visible else 0.0
