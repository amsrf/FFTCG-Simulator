extends Node3D
## ONE HASTE CLOCK ON ONE CARD: an ephemeral golden clock face that draws itself around the card, whirls its hands,
## and fades out. Presentation only; one camera-facing quad drawn by shaders/haste_clock.gdshader (no art assets).
##
##   0 .. APPEAR_SECONDS        the dial draws on clockwise from 12 while the clock swells to full size
##   ~APPEAR_SECONDS            a white-hot flare on every line
##   whole lifetime             the hands spin fast and keep accelerating; the block band turns against them
##   FADE_START .. LIFETIME     it fades while expanding a little, then the node frees itself
##
## Reference: references/haste/ (frames 204-258 of the haste clip). The clock FOLLOWS the card while it lives, so a
## card that moves (an attack lift, a re-layout) keeps its clock. It lives under the tree root and frees itself; the
## cue (haste_clock_cue.gd) only holds the presentation queue for the appearance.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const CLOCK_SHADER := preload("res://shaders/haste_clock.gdshader")

const APPEAR_SECONDS := 0.28
const FADE_START := 0.95
const LIFETIME := 1.35
## The quad's side in card heights. Sized so the clock never reaches a NEIGHBOURING card: field cards are 0.65 m apart
## and 0.515 m wide, so everything visible (the notches reach 0.90 of the half-side, their glow ~0.95) must stay inside
## ~0.39 m of the centre, even at the appearance overshoot and the fade growth. tests/haste_vfx_probe asserts it.
const SIZE_IN_CARD_HEIGHTS := 1.05
## How far the clock grows while it fades out.
const FADE_GROWTH := 1.06
## The outermost visible radius, as a fraction of the half-side (notch tips + their glow).
const VISIBLE_EXTENT := 0.95
## Minute-hand speed in turns per second at the start, and its acceleration (turns/s^2): "the clock running fast".
const MINUTE_TURNS_PER_SECOND := 2.6
const MINUTE_ACCEL := 2.4
const HOUR_RATIO := 0.25
const BAND_TURNS_PER_SECOND := -0.45
## Drawn after the board and the cards (both are in the transparent pass), like the fire burst.
const RENDER_PRIORITY := 20
## How far the clock's LOWEST point stays above the card face. The quad faces the camera, which looks at the board
## ~10 deg off vertical, so the quad is TILTED against the card and its lower half dips toward the board; a fixed
## lift (0.06 m) let the card face hide the bottom of the clock. lift_for() derives the lift from the tilt and the
## clock's size instead. The board camera is orthographic, so lifting along the view axis does not move it on screen.
const CLEARANCE := 0.05

var _target: Node3D
var _centre := Vector3.ZERO
var _height := 0.6
var _age := 0.0
var _phase := 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	set_process(false)


## Call after adding to the tree.
func setup(target: Node3D, clock_seed: int = 0) -> void:
	_target = target
	var at: Transform3D = target.global_transform
	_centre = at.origin
	var basis_scale: Vector3 = at.basis.get_scale()
	var card_scale: float = maxf((absf(basis_scale.x) + absf(basis_scale.z)) * 0.5, 0.01)
	var face := Vector2(0.429, 0.6)
	if target.has_method("_card_face_size"):
		var size = target.call("_card_face_size")
		if size is Vector2 and size.y > 0.0:
			face = size
	_height = face.y * card_scale
	# Where the hands start differs per clock, so two clocks side by side do not move in lockstep.
	var rng := RandomNumberGenerator.new()
	rng.seed = clock_seed
	_phase = rng.randf()

	_mat = ShaderMaterial.new()
	_mat.shader = CLOCK_SHADER
	_mat.render_priority = RENDER_PRIORITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * _height * SIZE_IN_CARD_HEIGHTS
	_quad = MeshInstance3D.new()
	_quad.name = "Clock"
	_quad.mesh = quad
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 2.0
	add_child(_quad)
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age >= LIFETIME:
		queue_free()


## The whole clock at `t` seconds (deterministic, so a demo can freeze any moment).
func sample(t: float) -> void:
	if is_instance_valid(_target) and _target.is_inside_tree():
		_centre = _target.global_position
	var cam_basis := _camera_basis()
	var appear := clampf(t / APPEAR_SECONDS, 0.0, 1.0)
	var fade := clampf((t - FADE_START) / (LIFETIME - FADE_START), 0.0, 1.0)
	var grow := lerpf(0.55, 1.0, _ease_out_back(appear)) * lerpf(1.0, FADE_GROWTH, fade)
	_quad.global_transform = Transform3D(cam_basis.scaled(Vector3.ONE * grow),
		_centre + cam_basis.z * lift_for(cam_basis, _height * SIZE_IN_CARD_HEIGHTS * 0.5 * grow))

	var minute := _phase + MINUTE_TURNS_PER_SECOND * t + 0.5 * MINUTE_ACCEL * t * t
	_mat.set_shader_parameter("reveal", 1.0 - pow(1.0 - appear, 2.0))
	_mat.set_shader_parameter("intensity", smoothstep(0.0, 0.5, appear) * (1.0 - fade * fade))
	_mat.set_shader_parameter("minute_hand", minute)
	_mat.set_shader_parameter("hour_hand", _phase * 0.37 + minute * HOUR_RATIO)
	_mat.set_shader_parameter("band_spin", BAND_TURNS_PER_SECOND * t)
	_mat.set_shader_parameter("flare", exp(-pow((t - APPEAR_SECONDS) / 0.09, 2.0)))


## Distance along the view axis that keeps every point of a camera-facing square of half-side `half` at least
## CLEARANCE above the board plane: a point at (u, v) on the quad sits at lift * z.y + u * x.y + v * y.y above the
## centre, lowest at the corner, so lift = (half * (|x.y| + |y.y|) + CLEARANCE) / z.y.
func lift_for(cam_basis: Basis, half: float) -> float:
	var up_z: float = maxf(cam_basis.z.dot(Vector3.UP), 0.2)
	var dip: float = half * (absf(cam_basis.x.dot(Vector3.UP)) + absf(cam_basis.y.dot(Vector3.UP)))
	return (dip + CLEARANCE) / up_z


## Probe hook: how far the quad's lowest corner is above the card's centre (must stay > 0, or the card covers it).
func lowest_corner_height() -> float:
	if _quad == null:
		return 0.0
	var size: Vector2 = (_quad.mesh as QuadMesh).size * 0.5
	var lowest := INF
	for corner in [Vector3(-size.x, -size.y, 0), Vector3(size.x, -size.y, 0), Vector3(-size.x, size.y, 0), Vector3(size.x, size.y, 0)]:
		lowest = minf(lowest, (_quad.global_transform * corner - _centre).dot(Vector3.UP))
	return lowest

## Probe hooks.
func age() -> float:
	return _age

func shader_value(param: String) -> Variant:
	return _mat.get_shader_parameter(param) if _mat != null else null

## The farthest anything visible reaches from the card's centre over the whole life (appearance overshoot or fade
## growth, whichever is bigger), in metres.
func max_visible_radius() -> float:
	var overshoot := lerpf(0.55, 1.0, _ease_out_back(0.8))  # ease_out_back peaks near x = 0.8
	return _height * SIZE_IN_CARD_HEIGHTS * 0.5 * VISIBLE_EXTENT * maxf(overshoot, FADE_GROWTH)

func screen_size_metres() -> float:
	return _height * SIZE_IN_CARD_HEIGHTS * _quad.global_transform.basis.get_scale().x if _quad != null else 0.0


func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
