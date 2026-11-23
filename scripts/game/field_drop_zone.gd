extends MeshInstance3D
## THE LOCAL PLAYER'S WOOD SLAB AS A DROP TARGET. A held hand card is played by releasing the pointer over it; while
## the pointer is there (and the card could be played) this lights a gold rim around the slab.
##
## The slab is baked into the board mesh, so its outline is copied here from Blender/build_board_slabs.py (the
## 'Volcanic single wood slab': x -4.01..4.01, Blender y river_y+0.075..1.71 with river_y = -0.29, top at z 0.065),
## mapped to Godot (x, z, -y). Measured against assets/board/board_mesh.bin: top y 0.065, z -1.71..0.215. Both seats
## keep the wood in local gameplay coordinates (assets/board/README.md), so the near slab is always the local one.
## Move or resize the slab in Blender and these numbers must follow.

const SHADER := preload("res://shaders/field_drop_glow.gdshader")
# x +-4.30 since Blender/widen_board.py widened both slabs by 0.28 m at each end (2026-11-21).
const SLAB_MIN := Vector2(-4.30, -1.71)   # (x, z)
const SLAB_MAX := Vector2(4.30, 0.215)
const SLAB_TOP_Y := 0.065
## Lifted off the wood so it never z-fights the slab top.
const GLOW_LIFT := 0.006
## Room around the slab for the outer spill.
const MARGIN := 0.30
const FADE_SECONDS := 0.14

var lit := false
var _material: ShaderMaterial
var _fade: Tween

func _ready() -> void:
	# World coordinates, whatever the parent is.
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half := (SLAB_MAX - SLAB_MIN) * 0.5
	var centre := (SLAB_MAX + SLAB_MIN) * 0.5
	var quad_half := half + Vector2.ONE * MARGIN
	var plane := PlaneMesh.new()
	plane.size = quad_half * 2.0
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("rect_half", half)
	_material.set_shader_parameter("quad_half", quad_half)
	_material.set_shader_parameter("intensity", 0.0)
	# The board is drawn in the transparent pass; distance sorting would otherwise draw it over this quad.
	_material.render_priority = 1
	material_override = _material
	# The quad's extent is not where the shader's light ends; never let a frustum test drop the near edge.
	extra_cull_margin = MARGIN
	global_transform = Transform3D(Basis(), Vector3(centre.x, SLAB_TOP_Y + GLOW_LIFT, centre.y))
	visible = false

## True when `pointer` (screen pixels) looks at the slab's top face.
func contains_pointer(camera: Camera3D, pointer: Vector2) -> bool:
	if camera == null:
		return false
	var hit = Plane(Vector3.UP, SLAB_TOP_Y).intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
	if hit == null:
		return false
	var p := Vector2((hit as Vector3).x, (hit as Vector3).z)
	return p.x >= SLAB_MIN.x and p.x <= SLAB_MAX.x and p.y >= SLAB_MIN.y and p.y <= SLAB_MAX.y

## Fade the rim in or out. Idempotent: the same state twice does nothing.
func set_lit(value: bool) -> void:
	if value == lit:
		return
	lit = value
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if lit:
		visible = true
	var from: float = intensity()
	_fade = create_tween()
	_fade.tween_method(func(v: float) -> void: _material.set_shader_parameter("intensity", v),
		from, 1.0 if lit else 0.0, FADE_SECONDS)
	if not lit:
		_fade.tween_callback(func() -> void: visible = false)

func intensity() -> float:
	var v = _material.get_shader_parameter("intensity") if _material != null else null
	return float(v) if v is float else 0.0
