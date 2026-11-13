extends Node3D
## ONE PROTECT SHELL ON ONE CARD: the card gained "cannot be broken" (the `unbreakable` status). An egg of hexagonal
## glass panels closes around the card (a ragged outline of whole panels, not a full half-sphere), its outermost
## panels flare frosty white, and it fades out leaving the gold rims last.
## Presentation only; one camera-facing quad drawn by shaders/protect_shell.gdshader (no art assets).
##
##   0 .. 0.20               comets and two coloured motes appear around the card
##   BUILD_START .. BUILD_END  the panels form, from the outline inward, in a scattered order
##   ~FLARE_AT               the outline flares frosty white (the shell has closed)
##   FADE_START .. LIFETIME  the glass fades first, the gold rims last; then the node frees itself
##
## Reference: frames 47-90 of the Protect clip (~/Desktop/Clips/protect), read at 30 fps. The shell FOLLOWS the card
## while it lives. It lives under the tree root and frees itself; the cue (protect_shell_cue.gd) holds the presentation
## queue only until the shell has closed.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const SHELL_SHADER := preload("res://shaders/protect_shell.gdshader")

const BUILD_START := 0.20
const BUILD_END := 0.62
const FLARE_AT := 0.62
const FLARE_WIDTH := 0.13
const COMETS_OUT_START := 0.70
const COMETS_OUT_END := 1.00
const FADE_START := 1.05
const LIFETIME := 1.60
## How long the cue holds the presentation queue: until the shell has closed.
const APPEAR_SECONDS := BUILD_END
## The quad, in card heights. The shell is a little taller than the card and a little wider; sideways it must stay
## clear of a NEIGHBOURING card (field cards are 0.65 m apart and 0.515 m wide, so everything visible must stay inside
## ~0.39 m of the centre). tests/protect_vfx_probe asserts it.
const WIDTH_IN_CARD_HEIGHTS := 1.05
const HEIGHT_IN_CARD_HEIGHTS := 1.30
## The farthest anything is drawn, as a fraction of the half-side: the kept panels end at ~0.90 (edge_keep + jitter;
## the outermost ring is dropped to leave a ragged outline) and the comets orbit at up to 0.92.
const VISIBLE_EXTENT := 0.92
## The appearance grows the shell from this scale to 1.
const APPEAR_FROM_SCALE := 0.88
## Drawn after the board and the cards (both are in the transparent pass), like the haste clock.
const RENDER_PRIORITY := 20
## How far the shell's LOWEST point stays above the card face (see haste_clock.gd lift_for()).
const CLEARANCE := 0.05

var _target: Node3D
var _centre := Vector3.ZERO
var _height := 0.6
var _age := 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	set_process(false)


## Call after adding to the tree.
func setup(target: Node3D) -> void:
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

	_mat = ShaderMaterial.new()
	_mat.shader = SHELL_SHADER
	_mat.render_priority = RENDER_PRIORITY
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH_IN_CARD_HEIGHTS, HEIGHT_IN_CARD_HEIGHTS) * _height
	_quad = MeshInstance3D.new()
	_quad.name = "Shell"
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


## The whole shell at `t` seconds (deterministic, so a demo can freeze any moment).
func sample(t: float) -> void:
	if is_instance_valid(_target) and _target.is_inside_tree():
		_centre = _target.global_position
	var cam_basis := _camera_basis()
	var grow := lerpf(APPEAR_FROM_SCALE, 1.0, smoothstep(0.0, BUILD_END, t))
	var half_height: float = _height * HEIGHT_IN_CARD_HEIGHTS * 0.5 * grow
	_quad.global_transform = Transform3D(cam_basis.scaled(Vector3.ONE * grow),
		_centre + cam_basis.z * lift_for(cam_basis, half_height))
	_mat.set_shader_parameter("time", t)
	# Up to 1.1: the last panels start forming at ~0.95 and take 0.12 to land.
	_mat.set_shader_parameter("build", clampf((t - BUILD_START) / (BUILD_END - BUILD_START), 0.0, 1.0) * 1.1)
	_mat.set_shader_parameter("comets", smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(COMETS_OUT_START, COMETS_OUT_END, t)))
	_mat.set_shader_parameter("flare", exp(-pow((t - FLARE_AT) / FLARE_WIDTH, 2.0)))
	_mat.set_shader_parameter("fade", smoothstep(FADE_START, LIFETIME, t))


## Distance along the view axis that keeps the quad's lowest point CLEARANCE above the board plane (haste_clock.gd).
func lift_for(cam_basis: Basis, half: float) -> float:
	var up_z: float = maxf(cam_basis.z.dot(Vector3.UP), 0.2)
	var dip: float = half * (absf(cam_basis.x.dot(Vector3.UP)) + absf(cam_basis.y.dot(Vector3.UP)))
	return (dip + CLEARANCE) / up_z


## Probe hooks.
func age() -> float:
	return _age

func shader_value(param: String) -> Variant:
	return _mat.get_shader_parameter(param) if _mat != null else null

## How far the quad's lowest corner is above the card's centre (must stay > 0, or the card covers it).
func lowest_corner_height() -> float:
	if _quad == null:
		return 0.0
	var size: Vector2 = (_quad.mesh as QuadMesh).size * 0.5
	var lowest := INF
	for corner in [Vector3(-size.x, -size.y, 0), Vector3(size.x, -size.y, 0), Vector3(-size.x, size.y, 0), Vector3(size.x, size.y, 0)]:
		lowest = minf(lowest, (_quad.global_transform * corner - _centre).dot(Vector3.UP))
	return lowest

## The farthest anything visible reaches SIDEWAYS from the card's centre, in metres (the shell is full size by then).
func max_visible_half_width() -> float:
	return _height * WIDTH_IN_CARD_HEIGHTS * 0.5 * VISIBLE_EXTENT


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
