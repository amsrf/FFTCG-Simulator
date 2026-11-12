extends Label3D

var power: int
var accumulated_damage: int
## The value the readout is heading for (or showing). Card.power_fx compares the card's new power against THIS, not
## against what is on screen mid-count, to decide whether a change is a power-up.
var target_power: int

var _power_tween: Tween = null
var _damage_tween: Tween = null
var _pulse_tween: Tween = null
## The power-up swell (animate_power_up). Owns `scale`, `modulate` and the render priorities while it runs.
var _boost_tween: Tween = null
var _rest_scale := Vector3.ONE
var _rest_modulate := Color.WHITE
var _rest_priority := 0
var _rest_outline_priority := 0

## POWER-UP NUMBER (the third beat of Card.power_fx): the count runs while the readout SWELLS, holds big for a moment
## and settles back, so the eye lands on the new value. Tinted warm while big; the gas puff sits behind it.
const BOOST_SCALE := 1.5
const BOOST_GROW_SECONDS := 0.22
const BOOST_COUNT_SECONDS := 0.85
const BOOST_HOLD_SECONDS := 0.30
const BOOST_SETTLE_SECONDS := 0.28
const BOOST_TINT := Color(1.0, 0.86, 0.55)
## Above the power-up gas/swords (power_up_burst.gd draws at 18..24), so the number is never painted over.
const BOOST_RENDER_PRIORITY := 40


func _ready() -> void:
	power = get_parent().power
	target_power = power
	accumulated_damage = get_parent().accumulated_damage
	_rest_scale = scale
	_rest_modulate = modulate
	_rest_priority = render_priority
	_rest_outline_priority = outline_render_priority
	self.text = '%s/%s' % [power, accumulated_damage]

func changePower(newPower):
	animate_power_change(newPower)

func changeAccumulatedDamage(newDamage):
	animate_accumulated_damage_change(newDamage)

func animate_power_change(end_power: int, duration: float = 0.75):
	# A board refresh can recompute several times in one frame. Kill the previous tween so the last value wins and
	# two tweens cannot fight over `power`.
	_stop_boost()
	target_power = end_power
	if _power_tween != null and _power_tween.is_valid():
		_power_tween.kill()
	_power_tween = create_tween()
	_power_tween.tween_method(update_power_display, power, end_power, duration).set_ease(Tween.EASE_OUT)
	_power_tween.tween_callback(pulse_label)

## The power-up count: wait `delay` (the swords' beat), then swell, count from what is shown to `end_power`, hold and
## settle. Calling it again mid-run re-aims the count at the new value without restarting the swell.
func animate_power_up(end_power: int, delay: float = 0.0) -> void:
	target_power = end_power
	if _power_tween != null and _power_tween.is_valid():
		_power_tween.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		scale = _rest_scale
	var already_big: bool = _boost_tween != null and _boost_tween.is_valid()
	if already_big:
		_boost_tween.kill()
	else:
		render_priority = BOOST_RENDER_PRIORITY
		outline_render_priority = BOOST_RENDER_PRIORITY - 1
	_boost_tween = create_tween()
	if delay > 0.0:
		_boost_tween.tween_interval(delay)
	_boost_tween.tween_property(self, "scale", _rest_scale * BOOST_SCALE, BOOST_GROW_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_boost_tween.parallel().tween_property(self, "modulate", BOOST_TINT, BOOST_GROW_SECONDS)
	_boost_tween.parallel().tween_method(update_power_display, power, end_power, BOOST_COUNT_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# A parallel step lasts as long as its LONGEST member (the count), so the hold starts when the count ends.
	_boost_tween.tween_interval(BOOST_HOLD_SECONDS)
	_boost_tween.tween_property(self, "scale", _rest_scale, BOOST_SETTLE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_boost_tween.parallel().tween_property(self, "modulate", _rest_modulate, BOOST_SETTLE_SECONDS)
	_boost_tween.tween_callback(_restore_rest)

func is_boosting() -> bool:
	return _boost_tween != null and _boost_tween.is_valid() and _boost_tween.is_running()

## Seconds from the start of animate_power_up(…, delay) until the readout is back at rest.
static func boost_seconds(delay: float) -> float:
	return delay + BOOST_COUNT_SECONDS + BOOST_HOLD_SECONDS + BOOST_SETTLE_SECONDS

## Drop a running swell at once (a zone change, or a plain change superseding it), showing the target value.
func _stop_boost() -> void:
	if _boost_tween == null:
		return
	if _boost_tween.is_valid():
		_boost_tween.kill()
	_boost_tween = null
	update_power_display(target_power)
	_restore_rest()

func cancel_power_up() -> void:
	_stop_boost()

func _restore_rest() -> void:
	scale = _rest_scale
	modulate = _rest_modulate
	render_priority = _rest_priority
	outline_render_priority = _rest_outline_priority
	_boost_tween = null

func animate_accumulated_damage_change(end_damage: int, duration: float = 0.75):
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_tween = create_tween()
	_damage_tween.tween_method(update_accumulated_damage_display, accumulated_damage, end_damage, duration).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_callback(pulse_label)

func update_power_display(newPower: int):
	power = newPower
	self.text = '%s/%s' % [power, accumulated_damage]

func update_accumulated_damage_display(newDamage: int):
	accumulated_damage = newDamage
	self.text = '%s/%s' % [power, accumulated_damage]

func pulse_label():
	# The swell owns the scale while it runs; a damage pulse must not record a swollen size as "rest".
	if is_boosting():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", _rest_scale * 1.4, 0.1)
	_pulse_tween.tween_property(self, "scale", _rest_scale, 0.1)
