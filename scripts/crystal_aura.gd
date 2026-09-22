extends MeshInstance3D
class_name CrystalAura
## The glowing shell around a mana crystal.
##
## It is a second MeshInstance3D carrying a COPY of the crystal's own mesh, scaled up so it sits just outside the
## geometry, wearing an additive Fresnel shader. Two consequences are worth knowing:
##
##   * It follows the silhouette at every angle, so it cannot end up "not enveloping" the crystal the way a
##     rounded-rectangle ring did. There is nothing to align, because the shell IS the shape.
##   * It must be a child of the crystal's MESH, not of the crystal root. The mesh carries the fit scale and does
##     the spinning, so a child of it inherits both and stays wrapped around the crystal as it turns. Parented to
##     the root instead, it would sit still while the crystal spun inside it.
##
## Everything here is an @export so it can be tuned in the Inspector.

## The glow's colour. Alpha matters: under additive blending ALPHA is what actually decides how much light lands.
@export var aura_color: Color = Color(1.0, 0.45, 0.05, 1.0):
	set(value):
		aura_color = value
		_apply()

@export var rim_power: float = 3.0:
	set(value):
		rim_power = value
		_apply()

## How bright the rim is at full strength. This is the "lit" level; set_lit() fades to and from it.
@export var intensity: float = 2.0:
	set(value):
		intensity = value
		_apply()

@export var pulse_speed: float = 2.0:
	set(value):
		pulse_speed = value
		_apply()

@export var pulse_amount: float = 0.15:
	set(value):
		pulse_amount = value
		_apply()

## How far outside the crystal the shell sits. 1.08 is a shell 8% larger — close enough to hug the shape, far
## enough that it does not z-fight with the surface underneath it.
@export var shell_scale: float = 1.08

## Seconds to fade in or out. Small: this marks the moment a cost is paid, and it should feel immediate.
@export var fade_seconds: float = 0.12

@export var aura_material: ShaderMaterial = preload("res://shaders/aura_material.tres")

var _material: ShaderMaterial = null
var _fade: Tween = null
var _lit: bool = false

func _ready() -> void:
	scale = Vector3.ONE * shell_scale
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = aura_material.duplicate() as ShaderMaterial
	set_surface_override_material(0, _material)
	# THE MODEL'S SECOND SURFACE MUST BE HIDDEN. neo_crystal3 carries its black edge and outline geometry on
	# surface 1; without this the shell would draw a black copy of it 8% larger, i.e. a black halo around the very
	# thing it is supposed to be lighting.
	set_surface_override_material(1, _invisible_material())
	visible = false
	_apply()
	print("[CrystalAura] ready: mesh=%s surfaces=%d override0=%s scale=%s global_scale=%s visible=%s" % [
		mesh, mesh.get_surface_count() if mesh != null else -1,
		_material, scale, global_transform.basis.get_scale(), visible])

## Turn the glow on or off, fading between the two.
func set_lit(on: bool) -> void:
	if _lit == on:
		return
	_lit = on
	visible = true
	if _material == null:
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if fade_seconds <= 0.0:
		_material.set_shader_parameter("intensity", intensity if on else 0.0)
		visible = on
		return
	_fade = create_tween()
	_fade.tween_method(_set_intensity, _current_intensity(), intensity if on else 0.0, fade_seconds)
	if not on:
		_fade.tween_callback(func(): visible = false)
	print("[CrystalAura] set_lit(%s): visible=%s writing_intensity=%s rim_power=%s color=%s parent=%s" % [
		on, visible, intensity if on else 0.0, rim_power, aura_color, get_parent()])

func _current_intensity() -> float:
	return float(_material.get_shader_parameter("intensity"))

func _set_intensity(value: float) -> void:
	_material.set_shader_parameter("intensity", value)

func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("aura_color", aura_color)
	_material.set_shader_parameter("rim_power", rim_power)
	_material.set_shader_parameter("pulse_speed", pulse_speed)
	_material.set_shader_parameter("pulse_amount", pulse_amount)
	# `intensity` is owned by the fade while one is running, so only write it when idle.
	if _fade == null or not _fade.is_valid():
		_material.set_shader_parameter("intensity", intensity if _lit else 0.0)

## A material that draws nothing, for hiding a surface of the shell.
func _invisible_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
