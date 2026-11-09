extends BigButton
class_name GemButton
## The gem button: BigButton's structure and interaction (Area3D, text viewport, hover scale,
## press pulse) with the generated capsule model in place of the flat plate.
##
## FOUR THINGS DIFFER FROM BigButton, and the first is a fix for a real overflow:
##
## 1. TEXT IS FITTED TO THE BUTTON, NOT THE VIEWPORT. BigButton._autofit_label() fits the label to
##    85% of the TEXT VIEWPORT. The button's face only covers part of the text quad — the quad is
##    2.048 units across while the face is ~1.37 — so "85% of the viewport" is nearly 3x wider than
##    the button. Here the budget is the face itself, converted into viewport pixels, with an
##    explicit margin each side, and BOTH axes are checked (BigButton checked width only). It also
##    runs in _ready(), because BigButton only fits when set_text() is called — so a button whose
##    text came from the scene kept its authored size (128) until someone configured it.
##
## 2. THE GEM'S COLOUR, NOT THE FRAME'S ALBEDO, CARRIES HOVER AND DISABLED. BigButton._dim_to()
##    tweens a material's `albedo_color`, which is invisible on a full metal — metal has almost no
##    diffuse response. Disabled drives the stone's `grey_mix` (the reference's grey stone) and drops
##    its emission; hover raises the emission. Per the design decision the FRAME stays polished
##    chrome when disabled — only the gem greys.
##
## 3. The model is an INSTANCED glb, so `$Background/MeshInstance3D` is a placeholder kept only so
##    BigButton's lookup path resolves. It is deliberately left WITHOUT a material: an override would
##    reference the shared `gem_button_metal.tres`, and BigButton's tween would then dim every button
##    at once — and persist that if the resource were ever saved.

const LIT_EMISSION := 1.1         # matches the shipped gem_button_stone.tres
const HOVER_EMISSION := 1.8       # pointer over: the stone brightens
const DISABLED_EMISSION := 0.06   # the grey stone keeps only a trace of glow

## Text budget. The font starts here and shrinks until the label fits the face minus these margins,
## so long labels shrink rather than spilling. BigButton's MIN_FONT_SIZE (24) is the inherited floor.
const GEM_BASE_FONT_SIZE := 76   # BigButton's 96 is a bit large for this button; 88 was still too big
const MARGIN_X := 0.10           # each side, as a fraction of the face width
const MARGIN_Z := 0.14           # each side, as a fraction of the face height

const TEXT_QUAD_UNITS := 2.048   # QuadMesh size in GemButton.tscn

## -----------------------------------------------------------------------------------------------
## SLIDE-IN — THE KNOBS ARE HERE, and they are @exported so the Inspector shows them too.
##
## A button that appears out of nowhere reads as a glitch, so it starts beyond the right edge of the
## screen and eases into its slot. Screen-right is world -x for this camera (its basis.x is
## (-1, 0, 0)), so the start offset is NEGATIVE x and the tween runs it back to 0.
##
##   slide_in_duration    how long the entry takes — 0.5 s.
##   slide_in_distance    how far off-screen it starts. Derived, not guessed: the orthographic camera's
##                        visible width is 10.25 m, so its right edge sits at x = -5.125; at the rack's
##                        x = -3.8 with a button half-width of 0.90, the button only fully clears the
##                        edge once it starts 2.23 m further out, and 2.4 leaves a margin. If the rack
##                        is ever moved further right (a more negative x), raise this to match.
##   slide_in_flip_degrees  how far it turns over as it arrives — 180 puts its BACK to the camera, so
##                        the entry reveals the gem and the label rather than showing them from the
##                        start. The axis is x: the same axis it travels along, so the button rolls
##                        into place, its face tipping away from and then back toward the viewer.
##                        Try 90 for a quarter turn, 360 for a full roll, or 0 to disable.
##   slide_in_trans       the curve. TRANS_CUBIC with EASE_OUT is "fast at the start, smooth at the
##   slide_in_ease        end"; TRANS_QUINT or TRANS_EXPO with EASE_OUT is more dramatic, TRANS_QUAD
##                        with EASE_IN_OUT gentler, and TRANS_BACK with EASE_OUT overshoots slightly.
##                        Both the slide and the flip share it; give the flip its own tween if you
##                        ever want it to arrive later than the button does.
##
## The distance and the flip are LOCAL state, not new values: both settle back to the slot captured
## below, so the rack still owns where the buttons live and the main-slot rule is untouched.
##
## NOTE ON THE BACK FACE — deliberately no culling tricks. Rotating the node rotates its normals with
## it, so at 180 degrees the button's UNDERSIDE becomes the front-facing surface: it renders normally
## and the gem/label side is culled in its place. That is also what hides the label's own quad, which
## is the behaviour wanted — the content is not merely dimmed, it is not drawn at all.
## -----------------------------------------------------------------------------------------------
@export var slide_in_duration: float = 0.5
@export var slide_in_distance: float = 2.4
@export var slide_in_flip_degrees: float = 180.0
@export var slide_in_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var slide_in_ease: Tween.EaseType = Tween.EASE_OUT

## Where this button sits inside the rack, captured before any animation runs so repeated show/hide
## cycles can never drift. @onready rather than a line in _ready(): it is assigned earlier, and the
## notification below refuses to animate until the node is ready anyway.
@onready var _slot_position: Vector3 = position
@onready var _slot_rotation: Vector3 = rotation

var _slide_tween: Tween = null
var _was_visible: bool = false

## Hooking the VISIBILITY notification instead of overriding show_button() means every path is
## covered — BigButton.show_button(), hide_button(), and anything a future caller does — and toggling
## the `visible` checkbox while GemButtonPreview.tscn runs animates too, which is the quickest way to
## try the parameters out.
func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED:
		return
	var now: bool = is_inside_tree() and is_visible_in_tree()
	if now == _was_visible:
		return
	_was_visible = now
	if now:
		slide_in()
	else:
		_snap_to_slot()

## How long this button waits before its entry starts, in seconds. Declared here rather than with the
## other knobs because it is a property of the PAIR, not of the movement: when a modal shows two
## buttons they should arrive in sequence instead of as one slab. Confirm and PassPhase are 0; Cancel
## is 0.1, set per instance in game.tscn, so the pair reads as a cascade — the second starting only
## once the first is under way. Raise it for a more deliberate stagger, set 0 to make them simultaneous.
@export var slide_in_delay: float = 0.0

## Enter from off-screen right, turning over as it arrives, and ease into the slot. Public, so a
## caller can replay it.
func slide_in() -> void:
	# Fires on the enter-tree notification too, before @onready has run — animating then would slide
	# the button to a _slot_position of Vector3.ZERO, i.e. the rack's origin.
	if not is_node_ready():
		return
	_kill_slide()
	# Offset and turn IMMEDIATELY, before the tween starts, so the button waits out any delay already
	# off-screen and turned over, rather than sitting visible in its slot and then jumping.
	position = _slot_position + Vector3(-slide_in_distance, 0.0, 0.0)
	rotation = _slot_rotation + Vector3(deg_to_rad(slide_in_flip_degrees), 0.0, 0.0)
	_slide_tween = create_tween()
	_slide_tween.set_trans(slide_in_trans).set_ease(slide_in_ease)
	if slide_in_delay > 0.0:
		# A sequential step, and tween_interval is not affected by parallel(): everything after it still
		# runs together, so the whole entry is simply postponed.
		_slide_tween.tween_interval(slide_in_delay)
	_slide_tween.tween_property(self, "position", _slot_position, slide_in_duration)
	# parallel(), not a second tween_property: chained tweeners run one after the other, which would
	# slide the button in and only then flip it. The two have to overlap to read as one movement.
	_slide_tween.parallel().tween_property(self, "rotation", _slot_rotation, slide_in_duration)

## Hide with no exit animation: a button lingering over the board on its way out reads as a stuck
## one. Snapping back to the slot also means the next show starts from the edge again — and it is
## what puts the rotation back, so a hidden button is never left face-down.
func _kill_slide() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null

func _snap_to_slot() -> void:
	_kill_slide()
	position = _slot_position
	rotation = _slot_rotation

@onready var _model: GemButtonModel = $Background/Model

## The animated 0..1 states. These are PROPERTIES with setters so that tween_property can animate
## them, and so that every write funnels through _apply_stone() — the two shader parameters then
## cannot disagree. `set()` inside a setter assigns the backing field, it does not recurse.
var _hover_t: float = 0.0:
	set(value):
		_hover_t = value
		_apply_stone()

var _disabled_t: float = 0.0:
	set(value):
		_disabled_t = value
		_apply_stone()

func _ready() -> void:
	super()
	# Fit whatever text the scene authored, not just later set_text() calls.
	var label: Label = $ButtonTextViewport/Control/CenterContainer/Label
	if label != null:
		set_text(label.text)
	_apply_stone()

## The button's visible face in the BUTTON's local space: x = width, z = face height, both scaled by
## the Background node. The meshes' own AABBs are in model units because Background carries the
## scale, so no global transform is needed — reading one here would be a "!is_inside_tree()" error.
func face_size() -> Vector2:
	var box := _model_box()
	var s: float = $Background.scale.x
	return Vector2(box.size.x * s, box.size.z * s)

## Where the model's top face ends up in the button's local space. The text quad is placed just above
## this and the button is positioned around it, so it is worth being able to assert: when the plate
## was thinned from 0.34 to 0.20 units, Background's offset was left at the value for the OLD
## thickness and the whole button sank 0.027 m, which pushed the text visibly high on screen.
func face_height() -> float:
	var bg: Node3D = $Background
	return bg.position.y + _model_box().end.y * bg.scale.y

func _model_box() -> AABB:
	var model: Node3D = $Background/Model
	if model == null:
		return AABB()
	var box := AABB()
	var found := false
	for node in _meshes(model):
		if not found:
			box = node.get_aabb()
			found = true
		else:
			box = box.merge(node.get_aabb())
	return box if found else AABB()

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			out.append(child)
		out.append_array(_meshes(child))
	return out

## Replaces BigButton's viewport-relative fit. Same shape of loop, honest budget.
func _autofit_label(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return
	var face: Vector2 = face_size()
	if face.x <= 0.0 or face.y <= 0.0:
		super(label)
		return

	# Pixels of label space that one local unit of the button covers.
	var px_per_unit: float = float(VIEWPORT_SIZE.x) / TEXT_QUAD_UNITS
	var budget := Vector2(
		face.x * px_per_unit * (1.0 - 2.0 * MARGIN_X),
		face.y * px_per_unit * (1.0 - 2.0 * MARGIN_Z))

	var size: int = GEM_BASE_FONT_SIZE
	var measured: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var line: float = font.get_height(size)
	while size > MIN_FONT_SIZE and (measured.x > budget.x or line > budget.y):
		size -= 2
		measured = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		line = font.get_height(size)
	label.add_theme_font_size_override("font_size", size)
	print("[GemButton] '%s' fitted to %dpx: text %.0f x %.0f px of a %.0f x %.0f px budget (face %.2f x %.2f m)"
		% [label.text, size, measured.x, line, budget.x, budget.y, face.x, face.y])

func frame_material() -> Material:
	return _model.frame_material if _model != null else null

func stone_material() -> ShaderMaterial:
	return _model.stone_material if _model != null else null

## One place that writes the stone's two state parameters, so they cannot drift apart.
func _apply_stone() -> void:
	var mat: ShaderMaterial = stone_material()
	if mat == null:
		return
	var lit: float = LIT_EMISSION + (HOVER_EMISSION - LIT_EMISSION) * _hover_t
	mat.set_shader_parameter("grey_mix", _disabled_t)
	mat.set_shader_parameter("emission_strength",
		lit * (1.0 - _disabled_t) + DISABLED_EMISSION * _disabled_t)

## Animates one of the state properties. tween_property reads the current value itself, which is why
## this is not tween_method: a method tween needs the FROM value passed in, and asking a setter for
## its own current value by calling it with no arguments raises "Expected 1 argument(s)" — which is
## exactly what an earlier version of this did at runtime.
##
## Outside the tree there is no tween, so the value is applied directly — which is also what lets
## tests/button_probe.tscn exercise the disabled state on an instantiated (untreed) button.
##
## The property is a NodePath, not a StringName: tween_property() rejects a StringName outright
## ("argument 2 should be NodePath but is StringName"), and that parse failure took the whole script
## down with it, so every button in the scene silently became a plain Node3D.
func _animate_to(prop: NodePath, to: float) -> void:
	if not is_inside_tree():
		set(String(prop), to)
		return
	var tween := create_tween()
	tween.tween_property(self, prop, to, 0.12)

func _on_area_hovered() -> void:
	super()
	if not _disabled:
		_animate_to(^"_hover_t", 1.0)

func _on_area_unhovered() -> void:
	super()
	if not _disabled:
		_animate_to(^"_hover_t", 0.0)

func set_disabled(value: bool) -> void:
	super(value)
	_animate_to(^"_disabled_t", 1.0 if value else 0.0)
