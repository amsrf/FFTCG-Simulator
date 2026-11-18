extends Node3D
## THE PHASE PRISM: a TRIANGULAR crystal prism lying in a stone cradle above the local priority buttons, like a
## rotating triangular sign. At rest its top face lies FLAT AND FLUSH with the cradle's lip, its two edges on the
## slot's two edges (a plain rectangular slot: no gap anywhere), and its other two faces are hidden below. That face
## shows the current phase by the Comprehensive Rules' name (9.1-9.5: Active Phase ... End Phase); during the Attack
## Phase it shows the current step instead (10.1.1-10.1.4, e.g. "Block Declaration Step"). A phase change TURNS it
## forward 120 degrees: the name is written on the hidden face that is about to come up, so three faces carry all
## six phases. The angle only ever increases. Filled in the turn's colour: BLUE on your turn, RED on the opponent's
## (the mana crystal's own shader, so it matches the cost row). Tried and removed at the user's request: a coloured
## glow on the lip, a sweeping glint, and deeper matte colours.
##
## History: a six-sided crystal came first (floating, then in a hexagonal cradle). A horizontal lip never lines up
## with a hexagon's faces, so it always showed slivers, cut tips and gaps; a triangle with one face up does line up.
##
## The cradle is baked into the board by Blender/build_phase_cradle.py, which READS FACE_WIDTH / LENGTH /
## CRADLE_TOP_Y / FACE_ABOVE_LIP / CENTRE from this file: change them here, then re-run it and re-export the board
## (both seats). Fed by Game.phase_entered. World coordinates (top_level), fixed for both seats.

const CRYSTAL_SHADER := preload("res://shaders/mana_crystal.gdshader")
const FONT := preload("res://assets/fonts/FOT-NewRodin Pro EB.otf")

const NAMES: Array[String] = ["Active Phase", "Draw Phase", "Main Phase 1", "Attack Phase", "Main Phase 2", "End Phase"]
const STEP_NAMES: Array[String] = ["Attack Preparation Step", "Attack Declaration Step", "Block Declaration Step",
	"Damage Resolution Step"]
enum Slot { ACTIVE, DRAW, MAIN_1, ATTACK, MAIN_2, END }

## The prism: an equilateral triangle FACE_WIDTH on a side, LENGTH long, lying along world X.
const FACE_WIDTH := 0.12
const LENGTH := 1.0
## The cradle (Blender/build_phase_cradle.py): lip top height, and how far ABOVE it the top face stands: negative =
## just below, flush, the stone's edge framing it (raised 1.5 cm was tried and reverted). Above the lip the cradle
## would narrow its slot to the prism's width at the lip.
const CRADLE_TOP_Y := 0.10
const FACE_ABOVE_LIP := -0.002
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
const EMISSION := 0.5
const GRADIENT_TOP := 1.12
const GRADIENT_BOTTOM := 0.55
const TURN := TAU / 3.0

var _prism: MeshInstance3D
var _material: ShaderMaterial
var _labels: Array[Label3D] = []   # one per face (3)
var _angle := 0.0                  # roll about world X, only ever increased; face f is up at f * TURN
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
	_material.set_shader_parameter("gradient_amount", 1.0)
	_material.set_shader_parameter("gradient_top", GRADIENT_TOP)
	_material.set_shader_parameter("gradient_bottom", GRADIENT_BOTTOM)
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
	label.outline_size = 8
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

## Three flat glass faces and two end caps. Godot's front faces are CLOCKWISE seen from outside, so each triangle is
## wound with (p1-p0)x(p2-p0) pointing INWARD, and its normal is set explicitly (outward, flat).
func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LENGTH * 0.5
	var circ := INRADIUS * 2.0
	var corners: Array[Vector2] = []   # (y, z); face f lies between corners f and f+1
	for j in 3:
		var a := -float(j) * TURN + TURN * 0.5
		corners.append(Vector2(cos(a), sin(a)) * circ)
	for f in 3:
		var a: Vector2 = corners[f]
		var b: Vector2 = corners[(f + 1) % 3]
		var a0 := Vector3(-half, a.x, a.y); var a1 := Vector3(half, a.x, a.y)
		var b0 := Vector3(-half, b.x, b.y); var b1 := Vector3(half, b.x, b.y)
		# The gradient runs from corner f (0: the face's TOP edge on screen once it is up, toward +z) to corner f+1 (1).
		var shade := {a0: 0.0, a1: 0.0, b0: 1.0, b1: 1.0}
		_tri(st, a0, b0, b1, face_normal(f), shade); _tri(st, a0, b1, a1, face_normal(f), shade)
	for side: float in [-1.0, 1.0]:
		var p: Array[Vector3] = []
		for c in corners:
			p.append(Vector3(half * side, c.x, c.y))
		_tri(st, p[0], p[1], p[2], Vector3(side, 0, 0), {})
	return st.commit()

## `shade` maps a vertex to its gradient value (vertex colour R); vertices not in it get the middle.
func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, outward: Vector3, shade: Dictionary) -> void:
	if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0:
		var t := p1; p1 = p2; p2 = t
	st.set_normal(outward.normalized())
	for p in [p0, p1, p2]:
		st.set_color(Color(float(shade.get(p, 0.5)), 0.0, 0.0))
		st.set_uv(Vector2(p.x, p.y))
		st.add_vertex(p)

func _process(_delta: float) -> void:
	_prism.basis = Basis(Vector3.RIGHT, _angle)
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
		_labels[_face].text = text
		_angle = float(_face) * TURN
		visible = true
		return
	_slot = slot
	# EVERY change of name turns it, the Attack Phase's steps included (Preparation -> Declaration -> Block -> Damage).
	if text == _labels[_face].text:
		return
	# Write the name on the hidden face that comes up next, then turn it up. Always forward.
	_face = (_face + 1) % 3
	_labels[_face].text = text
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
## (1 - p) factor on the wobble makes it land EXACTLY on 1 at p = 1, so the face rests square in the slot.
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
