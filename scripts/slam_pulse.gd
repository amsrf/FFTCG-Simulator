extends Node3D
## Expanding impact ring for a Character slamming onto the field.
##
## The pulse is a horizontal PlaneMesh, not a camera-facing card flash: it belongs
## to the board and spreads across it. Additive so it reads as light even though
## the Compatibility renderer has no bloom.

const SLAM_SHADER := preload("res://shaders/slam_pulse.gdshader")

var _mesh: MeshInstance3D = null
var _material: ShaderMaterial = null
var _age: float = 0.0
var _duration: float = 0.40
var _end_scale: float = 3.4


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = SLAM_SHADER
	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader expands nothing, but this keeps the additive quad safe at the
	# edges of the camera frustum while it grows.
	_mesh.extra_cull_margin = 4.0
	add_child(_mesh)
	visible = false
	set_process(false)


## tier 1 = mild (cost 5-7), tier 2 = big (cost 8+).
func play(tier: int) -> void:
	if _mesh == null:
		return
	_age = 0.0
	_duration = 0.40 if tier <= 1 else 0.62
	_end_scale = 3.4 if tier <= 1 else 5.1
	var strength: float = 1.0 if tier <= 1 else 1.75
	_material.set_shader_parameter("pulse_color", Color(0.62, 0.86, 1.0, 1.0))
	_material.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	_material.set_shader_parameter("ring_strength", 2.2 * strength)
	_material.set_shader_parameter("core_strength", 1.1 * strength)
	_material.set_shader_parameter("ring_width", 0.055 if tier <= 1 else 0.075)
	_material.set_shader_parameter("fade", 1.0)
	scale = Vector3.ONE * (0.7 if tier <= 1 else 0.9)
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / maxf(_duration, 0.001), 0.0, 1.0)
	# Fast expansion, then a soft fade. The ring is a travelling wave: it is
	# already at its widest when the light is almost gone.
	var grow: float = lerpf(0.7 if _end_scale < 4.0 else 0.9, _end_scale, sqrt(t))
	scale = Vector3.ONE * grow
	_material.set_shader_parameter("ring_radius", lerpf(0.10, 1.05, sqrt(t)))
	_material.set_shader_parameter("fade", pow(1.0 - t, 2.2))
	if t >= 1.0:
		queue_free()
