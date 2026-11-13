extends MeshInstance3D
## SUMMONING SICKNESS: soft dark circular pulses rippling outward from the card's centre while it is waiting to act
## (shaders/sickness_waves.gdshader; reference Clips/sick). Card-owned and persistent, built lazily by
## card_status_overlays.gd; Card.shows_summoning_sickness() decides when it is wanted. Pure presentation.
##
## A card-aligned PlaneMesh parented to the card's HandMesh, exactly like the frozen overlay, so it follows the
## visible card through hover, a hit reaction or a tilt instead of being laid out separately.
##
##   show_waves()  fades in once the card has landed
##   wake()        the sickness is gone (end of the turn it was played): the waves fade out slowly
##   burst()       the card gained Haste: a quick fade as the haste clock appears
##   dismiss()     it dulled (a dull card already reads as "cannot act"): a short fade, back if it stands up
## Preloaded by PATH (no class_name), for the headless cache.

const SHADER := preload("res://shaders/sickness_waves.gdshader")

## Seconds for one ring to ripple from the centre to the corners (calm: it sits on every new Forward).
const TRAVEL_SECONDS := 2.4
const APPEAR_SECONDS := 0.6
const WAKE_SECONDS := 0.9
const BURST_SECONDS := 0.3
const DISMISS_SECONDS := 0.25
## A hair above the card face (the frozen overlay sits at 0.003), so neither z-fights.
const FACE_OFFSET := 0.004

enum State { HIDDEN, APPEARING, IDLE, LEAVING }

var _card: Node3D
var _mat: ShaderMaterial
var _state: State = State.HIDDEN
var _t := 0.0
var _leave_seconds := 0.0
var _clock := 0.0
var _level := 0.0          # current intensity 0..1
var _leave_from := 0.0


func setup(card: Node3D) -> void:
	_card = card
	var face: Vector2 = card.call("_card_face_size")
	var plane := PlaneMesh.new()
	plane.size = face
	mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("card_size", face)
	_mat.set_shader_parameter("intensity", 0.0)
	# Written explicitly: get_shader_parameter() returns null for a uniform left at its default.
	_mat.set_shader_parameter("travel_seconds", TRAVEL_SECONDS)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1.0
	position = Vector3(0.0, FACE_OFFSET, 0.0)
	visible = false
	set_process(false)


func is_showing() -> bool:
	return _state == State.APPEARING or _state == State.IDLE

func state_name() -> String:
	return State.keys()[_state]


func show_waves() -> void:
	if is_showing():
		return
	_state = State.APPEARING
	_t = 0.0
	visible = true
	set_process(true)
	_apply()

func wake() -> void:
	_leave(WAKE_SECONDS)

func burst() -> void:
	_leave(BURST_SECONDS)

func dismiss() -> void:
	_leave(DISMISS_SECONDS)

func hide_now() -> void:
	_state = State.HIDDEN
	_level = 0.0
	visible = false
	set_process(false)


func _leave(seconds: float) -> void:
	if not is_showing():
		return
	_state = State.LEAVING
	_leave_seconds = seconds
	_leave_from = _level
	_t = 0.0
	if not is_inside_tree():
		hide_now()


func _process(delta: float) -> void:
	_t += delta
	_clock += delta
	match _state:
		State.APPEARING:
			_level = smoothstep(0.0, 1.0, _t / APPEAR_SECONDS)
			if _t >= APPEAR_SECONDS:
				_state = State.IDLE
				_level = 1.0
		State.LEAVING:
			_level = _leave_from * (1.0 - smoothstep(0.0, 1.0, _t / maxf(_leave_seconds, 0.01)))
			if _t >= _leave_seconds:
				hide_now()
				return
	_apply()


func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", _level)
	_mat.set_shader_parameter("time", _clock)


## Probe hooks.
func level() -> float:
	return _level

func shader_time() -> float:
	return float(_mat.get_shader_parameter("time")) if _mat != null else 0.0
