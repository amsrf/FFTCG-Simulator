extends RefCounted
## A FIELD CARD STARTING AN EFFECT, presented (after Master Duel, ~/Desktop/Clips/trigger frames 172-216): the card RISES
## toward the camera and grows a little, wearing a dense aura in its element colours, then FLASHES (the aura flares, a wave leaves the
## outline, the art brightens) and the effect's stack card leaves it (Stack._fly_from_source) while it settles back.
##
##   raise()  - up and lit, and it STAYS there, CHARGING: the local player's ability while its costs and targets are
##              chosen (nothing is on the stack yet; the card itself says what is being paid for). While it charges it
##              wavers like a Character held in the cast stance (Hand._apply_character_waver), and breathes.
##   flash()  - from raised: the flare, then the settle; returns at the flare's peak, which is when the stack card
##              should leave. Without a raise first it rises quickly on its own (a trigger, an opponent's ability).
##   lower()  - back down unlit, no flash (the activation was cancelled).
##
## The rise MOVES THE CARD ROOT, but only by the difference from the last frame (and scales it relatively), so the
## field's own placement and the tap's turn keep working under it, and normalize() takes back exactly what was added.
## Owned by Card as `card.activation_fx`; Card.enter_zone() calls normalize(), Card's predelete calls release().
## Tweens are bound to the card, as in card_stack_aura.gd (no reference cycles, no stranded awaits).

const AURA_SHADER := preload("res://shaders/activation_aura.gdshader")
const ELEMENTS := preload("res://scripts/core/elements.gd")
const PRESENTATION := preload("res://scripts/core/presentation.gd")

## How far the card comes toward the camera (world metres) and how much it grows.
const LIFT := 0.55
const GROW := 1.10
const RISE_SECONDS := 0.16
## A card with no element colour (a neutral one) charges in white-gold.
const NEUTRAL_COLORS := [Color(1.0, 0.86, 0.45), Color(1.0, 0.97, 0.85)]
const STANDING_INTENSITY := 1.0
const FLARE_INTENSITY := 1.0
## THE CHARGING WAVER: the hand's cast-stance waver (Hand._apply_character_waver: the same slow incommensurate sines),
## scaled for a card about twice as far from the camera, plus a slow breathing grow. Faded in over WAVER_FADE seconds.
const WAVER_DRIFT := Vector2(0.016, 0.011)       # world metres along the camera's right / up
const WAVER_TILT_DEG := Vector2(1.4, 1.0)        # about the card's own x (pitch) and z (roll)
const WAVER_BREATHE := 0.025                     # extra scale at the top of a breath
const WAVER_FADE := 0.35
## How long a charge can last before the hold stops animating (it then simply holds still).
const HOLD_MAX_SECONDS := 600.0
## The art brightens by this much at the flash (card.gdshader `face_light`).
const FLASH_LIGHT := 0.55
const FLASH_SECONDS := 0.10
const SETTLE_SECONDS := 0.32
const WAVE_SECONDS := 0.55
const QUAD_MARGIN := 0.3
const WAVE_REACH := 0.24

signal flash_peaked

var _card: Node3D
var _aura: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _tween: Tween = null
var _applied_offset := Vector3.ZERO     # world offset currently added to the card root
var _applied_scale := 1.0               # factor currently multiplied into the card root's scale
var _amount := 0.0                      # 0 = at rest, 1 = fully raised
var _raised := false
var _flash_pending := false             # a flash() is waiting for its peak: always woken, even when killed
var _applied_tilt := Vector2.ZERO       # pitch / roll (radians) currently added to the card root's rotation
var _waver_t := 0.0                     # seconds into the charge (drives the waver); < 0 = not charging
var _waver_from := 0.0                  # the waver's strength when the current tween took over (it fades out from there)
var _waver_strength := 0.0              # 0..1, how much of the waver the next _step applies

func _init(card: Node3D) -> void:
	_card = card

func is_raised() -> bool:
	return _raised

## Probe hook: 0 at rest, 1 fully raised.
func lift_amount() -> float:
	return _amount

func raise() -> void:
	if _raised or not _can_show():
		return
	_raised = true
	_restart()
	_tween.tween_method(_step.bind(0.0, -1.0), _amount, 1.0, RISE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_aura, _aura_level(), STANDING_INTENSITY, RISE_SECONDS)
	# Then it CHARGES until a flash() or lower() takes over (they restart the tween).
	_tween.tween_method(_charge_step, 0.0, HOLD_MAX_SECONDS, HOLD_MAX_SECONDS)

## The flare and the settle. Returns at the flare's peak (or at once when there is nothing to show).
## `hold_seconds`: how long the card stays up and lit at the top before it settles (Stack.blink_hold_seconds).
func flash(hold_seconds: float = 0.0) -> void:
	if not _can_show():
		return
	var from: float = _amount
	var rise: float = RISE_SECONDS * (1.0 - from)
	_raised = false
	_waver_from = _waver_strength
	_restart()
	if rise > 0.0:
		_tween.tween_method(_step.bind(0.0, -1.0), from, 1.0, rise).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_method(_set_aura, _aura_level(), STANDING_INTENSITY, rise)
	_tween.tween_method(_flare_step, 0.0, 1.0, FLASH_SECONDS)
	_tween.tween_callback(_peak)
	var hold: float = maxf(0.0, hold_seconds)
	var after: float = maxf(hold + SETTLE_SECONDS, WAVE_SECONDS)
	_tween.tween_method(_after_peak_step.bind(hold), 0.0, after, after)
	_tween.tween_callback(_finish)
	_flash_pending = true
	await flash_peaked

## Returns once nothing is animating (a lower() or a flash()'s settle has finished). A charge never ends by itself, so
## only call this after a lower() or flash().
func wait_idle() -> void:
	while is_instance_valid(_card) and _card.is_inside_tree() and _tween != null and _tween.is_valid() and _tween.is_running():
		await _card.get_tree().process_frame

## Seconds from flash() to its peak, from rest (what a caller staggering several flashes can plan with).
static func seconds_to_peak() -> float:
	return RISE_SECONDS + FLASH_SECONDS

func lower() -> void:
	if not _can_show() or (_amount <= 0.0 and not _raised):
		return
	_raised = false
	_waver_from = _waver_strength
	_restart()
	_tween.tween_method(_lower_step, _amount, 0.0, SETTLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_method(_set_aura, _aura_level(), 0.0, SETTLE_SECONDS)
	_tween.tween_callback(_finish)

## Any zone change: forget the lift (Card.enter_zone() assigns the new zone's scale outright and the new zone places the
## card, so undoing the offset here would only move it in its new parent), no light, no aura.
func normalize() -> void:
	_kill()
	_raised = false
	_amount = 0.0
	_applied_offset = Vector3.ZERO
	_applied_scale = 1.0
	_applied_tilt = Vector2.ZERO
	_waver_strength = 0.0
	_waver_from = 0.0
	_waver_t = 0.0
	if is_instance_valid(_card):
		var material = _card.get("mat")
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("face_light", 0.0)
	if _mat != null:
		_mat.set_shader_parameter("wave", -1.0)
	_set_aura(0.0)

func release() -> void:
	_kill()
	_aura = null
	_mat = null
	_card = null

# ------------------------------------------------------------------------------------------------ steps

## Charging: fully up, the waver fading in and running.
func _charge_step(t: float) -> void:
	_waver_t = t
	_waver_strength = smoothstep(0.0, WAVER_FADE, t)
	_step(1.0, 0.0, -1.0)

func _lower_step(amount: float) -> void:
	_waver_strength = _waver_from * amount
	_step(amount, 0.0, -1.0)

func _flare_step(k: float) -> void:
	_waver_strength = _waver_from * (1.0 - k)
	_step(1.0, FLASH_LIGHT * k, -1.0)
	_set_aura(lerpf(STANDING_INTENSITY, FLARE_INTENSITY, k))

## After the flash's peak, `t` seconds in: it HOLDS up and lit for `hold` seconds, then settles; the wave leaves the
## outline at the peak and travels through both.
func _after_peak_step(t: float, hold: float) -> void:
	var s: float = clampf((t - hold) / SETTLE_SECONDS, 0.0, 1.0)
	var down: float = 1.0 - s * s * (3.0 - 2.0 * s)
	var w: float = t / WAVE_SECONDS
	_waver_strength = 0.0
	_step(down, FLASH_LIGHT * down, w if w <= 1.0 else -1.0)
	_set_aura(FLARE_INTENSITY * down)

## Puts the card `amount` of the way up, with `light` on its art and the wave at `wave` (-1 = none).
func _step(amount: float, light: float, wave: float) -> void:
	if not is_instance_valid(_card):
		return
	_amount = amount
	var offset := Vector3.ZERO
	var camera: Camera3D = _card.get_viewport().get_camera_3d() if _card.is_inside_tree() else null
	if camera != null and amount > 0.0:
		offset = (camera.global_position - (_card.global_position - _applied_offset)).normalized() * LIFT * amount
	# THE WAVER (the hand's cast-stance sines): a small drift in the screen plane, a tilt, a breath.
	var t: float = _waver_t
	var w: float = _waver_strength
	if camera != null and w > 0.0:
		offset += (camera.global_basis.x * sin(t * 1.6) * WAVER_DRIFT.x + camera.global_basis.y * sin(t * 2.1) * WAVER_DRIFT.y) * w
	var tilt := Vector2(sin(t * 2.3) * WAVER_TILT_DEG.x, sin(t * 1.9) * WAVER_TILT_DEG.y) * (PI / 180.0) * w
	# Pitch and roll only, written as plain local angles: the dull's tween owns the turn about Y.
	_card.rotation.x += tilt.x - _applied_tilt.x
	_card.rotation.z += tilt.y - _applied_tilt.y
	_applied_tilt = tilt
	# Through the LOCAL position, never global_position: setting a global transform makes the node re-derive its Euler
	# angles from the basis, and a field card's half turn about Y comes back as (180, y, 180) - which the tap's
	# rotation_degrees:y tween then spun every frame. Converting the world delta into the parent's frame touches only
	# the origin.
	var parent := _card.get_parent() as Node3D
	if parent != null and _card.is_inside_tree():
		_card.position += parent.global_basis.inverse() * (offset - _applied_offset)
	_applied_offset = offset
	var factor: float = lerpf(1.0, GROW, amount) * (1.0 + WAVER_BREATHE * (0.5 + 0.5 * sin(t * 2.6)) * w)
	_card.scale *= factor / _applied_scale
	_applied_scale = factor
	var material = _card.get("mat")
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("face_light", light)
	if _mat != null:
		_mat.set_shader_parameter("wave", wave)

func _set_aura(level: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", level)
	if is_instance_valid(_aura):
		_aura.visible = level > 0.001 or float(_mat.get_shader_parameter("wave")) >= 0.0

func _aura_level() -> float:
	if _mat == null:
		return 0.0
	var v = _mat.get_shader_parameter("intensity")
	return float(v) if v is float else 0.0

func _finish() -> void:
	_tween = null
	_step(0.0, 0.0, -1.0)
	_set_aura(0.0)

func _restart() -> void:
	_kill()
	_ensure_aura()
	_apply_colors()
	_tween = _card.create_tween()

## The aura wears the card's element colours: two elements -> both; one -> it and a lighter neighbouring hue.
func _apply_colors() -> void:
	if _mat == null or not is_instance_valid(_card):
		return
	var elements: Array = _card.call("current_elements") if _card.has_method("current_elements") else []
	var accents: Array[Color] = []
	for e in elements:
		var i: int = ELEMENTS.index_of(e)
		if i >= 0:
			accents.append(ELEMENTS.ACCENT[i])
	var a: Color = NEUTRAL_COLORS[0]
	var b: Color = NEUTRAL_COLORS[1]
	if accents.size() >= 2:
		a = accents[0]
		b = accents[1]
	elif accents.size() == 1:
		a = accents[0]
		b = Color.from_hsv(fposmod(a.h + 0.08, 1.0), a.s * 0.55, 1.0)
	_mat.set_shader_parameter("color_a", a)
	_mat.set_shader_parameter("color_b", b)

func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_peak()

func _peak() -> void:
	if _flash_pending:
		_flash_pending = false
		flash_peaked.emit()

func _can_show() -> bool:
	return is_instance_valid(_card) and _card.is_inside_tree() and _card.get("hand_mesh") != null \
		and not PRESENTATION.fast_mode

func _ensure_aura() -> void:
	var mesh: Node3D = _card.get("hand_mesh")
	if is_instance_valid(_aura) and _aura.get_parent() == mesh:
		return
	var size: Vector2 = _card.call("_card_face_size") if _card.has_method("_card_face_size") else Vector2(0.429, 0.6)
	_mat = ShaderMaterial.new()
	_mat.shader = AURA_SHADER
	_mat.set_shader_parameter("card_size", size)
	_mat.set_shader_parameter("margin", QUAD_MARGIN)
	_mat.set_shader_parameter("wave_reach", WAVE_REACH)
	_mat.set_shader_parameter("intensity", 0.0)
	_mat.set_shader_parameter("wave", -1.0)
	_mat.render_priority = 6
	var plane := PlaneMesh.new()
	plane.size = size + Vector2.ONE * QUAD_MARGIN * 2.0
	_aura = MeshInstance3D.new()
	_aura.name = "ActivationAura"
	_aura.mesh = plane
	_aura.material_override = _mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.extra_cull_margin = 0.5
	_aura.position = Vector3(0.0, 0.004, 0.0)
	_aura.visible = false
	mesh.add_child(_aura)
