extends RefCounted
## THE TOP OF THE STACK, presented: a standing AURA on the card on top (the next to resolve), and the RESOLVE PULSE
## when it starts resolving - after ~/Desktop/Clips/stack_activate frames 24-50. Owned by Card as `card.stack_aura`;
## Stack decides which card is on top (Stack.refresh_top_aura) and awaits the pulse (Stack.resolve_top_effect).
##
## Two rectangles, both drawn by shaders/stack_aura.gdshader on one card-plane quad under the HandMesh:
##   * the AURA, a soft rim hugging the outline; it fades in on the top card and flares during the pulse;
##   * the WAVE, a second rectangle launched from the outline that grows outward and fades with distance.
## During the pulse the card itself grows a little and settles back. It animates the HandMesh, not the Card root (the
## stack's fan tween owns that), and Card.enter_zone() calls normalize(), so nothing survives the card leaving.
##
## Preloaded by PATH (no class_name), like the other card presentation modules.

const AURA_SHADER := preload("res://shaders/stack_aura.gdshader")

## The standing aura on the top card, and its flare during the pulse.
const STANDING_INTENSITY := 0.6
const FLARE_INTENSITY := 1.0
const FADE_SECONDS := 0.25
## The pulse: the card grows to PEAK_SCALE and settles back; the wave launches at WAVE_DELAY and travels WAVE_SECONDS.
const PEAK_SCALE := 1.08
const GROW_SECONDS := 0.18
const HOLD_SECONDS := 0.10
const SETTLE_SECONDS := 0.30
const WAVE_DELAY := 0.08
const WAVE_SECONDS := 0.62
## How far past the card the quad reaches (card-local metres); the wave's travel must fit inside it.
const QUAD_MARGIN := 0.3
const WAVE_REACH := 0.24

var _card: Node3D
var _aura: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _fade: Tween = null
var _pulse: Tween = null
var _is_top := false
var _intensity := 0.0
var _wave := -1.0

## NO REFERENCE CYCLES, NO STRANDED AWAITS. This module once leaked itself, its tweens, its material and a suspended
## coroutine for every card that had been on the stack (they were all still alive at exit): the tweens were SceneTree
## tweens whose lambdas captured `self`, stored in _fade/_pulse, so the aura and its tweens held each other forever;
## and pulse() awaited the tween's `finished`, which a KILLED tween never emits, so an interrupted pulse left its
## coroutine (and anyone awaiting it) suspended for good. Now: tweens are bound to the CARD (they die with it), every
## stored tween is dropped when it ends or is killed, pulse() awaits this module's own `pulse_ended` (emitted on
## completion AND on interruption), and release() (Card's NOTIFICATION_PREDELETE) lets go of everything.
signal pulse_ended

func _init(card: Node3D) -> void:
	_card = card

## Whether this card is the top of the stack. Fades the standing aura in or out; repeated calls are free.
func set_top(on: bool) -> void:
	if on == _is_top:
		return
	var mesh: Node3D = _mesh()
	if mesh == null or not _card.is_inside_tree():
		return    # not recorded: the next refresh, once the card is drawn, will try again
	_is_top = on
	if is_pulsing():
		return    # the pulse ends on the right level by itself
	_ensure_aura(mesh)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = _card.create_tween()
	_fade.tween_method(func(v: float) -> void: _apply_levels(v, _wave), _intensity, STANDING_INTENSITY if on else 0.0, FADE_SECONDS)
	_fade.tween_callback(func() -> void: _fade = null)

func is_top() -> bool:
	return _is_top

func is_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid() and _pulse.is_running()

## The resolve pulse; returns when it has completely finished (the card back at its size, the wave gone).
func pulse() -> void:
	var mesh: Node3D = _mesh()
	if mesh == null or not _card.is_inside_tree():
		return
	_ensure_aura(mesh)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var from: float = _intensity
	var total: float = pulse_seconds()
	_pulse = _card.create_tween()
	_pulse.tween_method(func(k: float) -> void: _pulse_step(k * total, from), 0.0, 1.0, total)
	_pulse.tween_callback(_end_pulse)
	await pulse_ended
	mesh = _mesh()
	if mesh != null:
		mesh.scale = Vector3.ONE
	_apply_levels(STANDING_INTENSITY if _is_top else 0.0, -1.0)

static func pulse_seconds() -> float:
	return maxf(GROW_SECONDS + HOLD_SECONDS + SETTLE_SECONDS, WAVE_DELAY + WAVE_SECONDS)

func _pulse_step(t: float, from: float) -> void:
	var mesh: Node3D = _mesh()
	if mesh == null:
		return
	var amount: float
	if t < GROW_SECONDS:
		amount = 1.0 - pow(1.0 - t / GROW_SECONDS, 3.0)
	elif t < GROW_SECONDS + HOLD_SECONDS:
		amount = 1.0
	elif t < GROW_SECONDS + HOLD_SECONDS + SETTLE_SECONDS:
		var s := (t - GROW_SECONDS - HOLD_SECONDS) / SETTLE_SECONDS
		amount = 1.0 - s * s * (3.0 - 2.0 * s)
	else:
		amount = 0.0
	mesh.scale = Vector3.ONE * lerpf(1.0, PEAK_SCALE, amount)
	var rest: float = STANDING_INTENSITY if _is_top else 0.0
	var level: float = lerpf(rest, FLARE_INTENSITY, amount) if t >= GROW_SECONDS else lerpf(from, FLARE_INTENSITY, amount)
	var w: float = (t - WAVE_DELAY) / WAVE_SECONDS
	_apply_levels(level, w if w >= 0.0 and w <= 1.0 else -1.0)

func _apply_levels(level: float, wave: float) -> void:
	_intensity = level
	_wave = wave
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", level)
	_mat.set_shader_parameter("wave", wave)
	if is_instance_valid(_aura):
		_aura.visible = level > 0.001 or wave >= 0.0

func _mesh() -> Node3D:
	return _card.get("hand_mesh") if is_instance_valid(_card) else null

func _ensure_aura(mesh: Node3D) -> void:
	if is_instance_valid(_aura) and _aura.get_parent() == mesh:
		return
	var size: Vector2 = _card.call("_card_face_size") if _card.has_method("_card_face_size") else Vector2(0.429, 0.6)
	_mat = ShaderMaterial.new()
	_mat.shader = AURA_SHADER
	_mat.set_shader_parameter("card_size", size)
	_mat.set_shader_parameter("margin", QUAD_MARGIN)
	_mat.set_shader_parameter("wave_reach", WAVE_REACH)
	_mat.render_priority = 6
	var plane := PlaneMesh.new()
	plane.size = size + Vector2.ONE * QUAD_MARGIN * 2.0
	_aura = MeshInstance3D.new()
	_aura.name = "StackAura"
	_aura.mesh = plane
	_aura.material_override = _mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.extra_cull_margin = 0.5
	_aura.position = Vector3(0.0, 0.004, 0.0)
	_aura.visible = false
	mesh.add_child(_aura)

## The pulse is over, finished or interrupted: drop the tween and wake whoever awaits pulse().
func _end_pulse() -> void:
	var was := _pulse != null
	_pulse = null
	if was:
		pulse_ended.emit()

## Leaving the stack (any zone change): stop everything, mesh back at rest, no aura. Called by Card.enter_zone().
func normalize() -> void:
	var was_pulsing: bool = is_pulsing()
	_stop_tweens()
	_is_top = false
	var mesh: Node3D = _mesh()
	if mesh != null and was_pulsing:
		mesh.scale = Vector3.ONE
	_apply_levels(0.0, -1.0)

func _stop_tweens() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_end_pulse()

## The card is being freed: stop and drop everything, wake any awaiting pulse(), and let go of the card.
func release() -> void:
	_stop_tweens()
	_aura = null
	_mat = null
	_card = null

## Probe hooks.
func aura() -> MeshInstance3D:
	return _aura

func intensity() -> float:
	return _intensity

func wave() -> float:
	return _wave
