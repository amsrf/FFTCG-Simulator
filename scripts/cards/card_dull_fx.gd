extends RefCounted
## How a card SHOWS being dull, on top of the small tap tilt. Pure presentation; the rules state is `Card.tapped`.
##
##   * DIM: card.gdshader's `dull_amount` greys and darkens the art while a NON-FORWARD is dull (tweened with the tap);
##     a dull Forward keeps its colour and only tilts.
##   * REFRESH: untapping in the Active Phase sweeps a soft light band across the art as its colour returns
##     (`refresh_sweep`), staggered card by card by Field.untap_cards_for().
##
## Owned by Card as `dull_fx`, like damage_fx / power_fx. Never name a helper `_set` / `_get` here (Object virtuals).

const DULL_SECONDS := 0.3
const SWEEP_SECONDS := 0.55

var _card: Node3D
var _dull_tween: Tween = null
var _sweep_tween: Tween = null
## Current shader value, for probes and for tweening from where it is.
var dull_amount: float = 0.0
var sweep: float = 0.0

func _init(card: Node3D) -> void:
	_card = card

## FORWARDS KEEP THEIR COLOUR: a dull Forward is only tilted. The grey is for Backups (and anything else that dulls),
## the cards whose art says "spent this turn" most usefully.
func _greys() -> bool:
	return str(_card.get("type")) != "Forward"

## Ease the dim in (true) or out (false), after `delay` seconds.
func set_dull(on: bool, delay: float = 0.0) -> void:
	_kill(_dull_tween)
	var target: float = 1.0 if on and _greys() else 0.0
	if not _card.is_inside_tree():
		_apply_dull(target)
		return
	_dull_tween = _card.create_tween()
	_dull_tween.tween_method(_apply_dull, dull_amount, target, DULL_SECONDS) \
		.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The Active Phase's light sweep across the art, after `delay` seconds.
func play_refresh(delay: float = 0.0) -> void:
	_kill(_sweep_tween)
	if not _card.is_inside_tree():
		return
	_sweep_tween = _card.create_tween()
	_sweep_tween.tween_method(_apply_sweep, 0.0, 1.0, SWEEP_SECONDS).set_delay(delay)
	_sweep_tween.tween_callback(_apply_sweep.bind(0.0))

## Snap to the card's real state with no animation: a card changing zone starts clean.
func sync() -> void:
	_kill(_dull_tween)
	_kill(_sweep_tween)
	_apply_dull(1.0 if bool(_card.get("tapped")) and _card.call("is_on_field") and _greys() else 0.0)
	_apply_sweep(0.0)

func _apply_dull(v: float) -> void:
	dull_amount = v
	var mat: ShaderMaterial = _card.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("dull_amount", v)

func _apply_sweep(v: float) -> void:
	sweep = v
	var mat: ShaderMaterial = _card.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("refresh_sweep", v)

func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()
