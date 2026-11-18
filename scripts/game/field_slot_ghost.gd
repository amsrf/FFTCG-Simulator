extends MeshInstance3D
## THE SLOT A HELD CHARACTER WILL LAND IN (after Artifact's summon slots). While the local player holds a Character in
## the cast stance and could play it, a faint card-sized gold outline sits on the exact slot `Field.landing_slot()`
## reports — the same free slot play_card() will pick, so the preview cannot lie. Pointing at the wood (a release
## would play it) or paying for it brightens and pulses it. Nothing for a Summon, an unplayable card, or a sixth Backup
## (that one asks which Backup to replace first). Owned by the Hand, beside FieldDropZone; world-space (top_level).

const SHADER := preload("res://shaders/field_slot_ghost.gdshader")
## Above the card plane, so the outline is never under the landing card's neighbours' faces.
const LIFT := 0.004
const MARGIN := 0.14
const FADE_SECONDS := 0.14

var _material: ShaderMaterial
var _fade: Tween
var _arm_fade: Tween
var _target_intensity := 0.0
var _target_armed := 0.0

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = PlaneMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("intensity", 0.0)
	_material.set_shader_parameter("armed", 0.0)
	# The board is in the transparent pass: above it in the sort, or the wood draws over the outline.
	_material.render_priority = 1
	material_override = _material
	extra_cull_margin = MARGIN
	visible = false

## Show the ghost on `slot` (a Field.landing_slot() result; empty hides it). `armed` = a release would play it now.
func show_slot(slot: Dictionary, armed: bool) -> void:
	if slot.is_empty():
		_fade_to(0.0)
		return
	var size: Vector2 = slot["size"]
	var half: Vector2 = size * 0.5
	var quad_half: Vector2 = half + Vector2.ONE * MARGIN
	# Called every frame of a held card: rebuild the plane only when the footprint changes.
	if not (mesh as PlaneMesh).size.is_equal_approx(quad_half * 2.0):
		(mesh as PlaneMesh).size = quad_half * 2.0
		_material.set_shader_parameter("card_half", half)
		_material.set_shader_parameter("quad_half", quad_half)
	global_transform = Transform3D(Basis(), (slot["position"] as Vector3) + Vector3.UP * LIFT)
	_fade_to(1.0)
	_arm_to(1.0 if armed else 0.0)

func hide_slot() -> void:
	_fade_to(0.0)

func _fade_to(value: float) -> void:
	if is_equal_approx(value, _target_intensity):
		return
	_target_intensity = value
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if value > 0.0:
		visible = true
	_fade = create_tween()
	_fade.tween_method(func(v: float) -> void: _material.set_shader_parameter("intensity", v),
		intensity(), value, FADE_SECONDS)
	if value <= 0.0:
		_fade.tween_callback(func() -> void: visible = false)

func _arm_to(value: float) -> void:
	if is_equal_approx(value, _target_armed):
		return
	_target_armed = value
	if _arm_fade != null and _arm_fade.is_valid():
		_arm_fade.kill()
	_arm_fade = create_tween()
	_arm_fade.tween_method(func(v: float) -> void: _material.set_shader_parameter("armed", v),
		armed_amount(), value, FADE_SECONDS)

## Probe hooks: the shown amount and the armed amount, 0..1 (live, mid-fade included).
func intensity() -> float:
	var v = _material.get_shader_parameter("intensity") if _material != null else null
	return float(v) if v is float else 0.0

func armed_amount() -> float:
	var v = _material.get_shader_parameter("armed") if _material != null else null
	return float(v) if v is float else 0.0

## Probe hook: true while the ghost is showing or fading in (false once asked to hide).
func is_showing() -> bool:
	return _target_intensity > 0.0
