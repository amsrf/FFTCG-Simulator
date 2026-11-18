extends Label3D
## Animates the power on the lower band and the damage counter over the art independently.
## The parent still exposes the combined readout as text for existing observers.

const FIELD_CARD_FACE := preload("res://scripts/cards/field_card_face.gd")

var power: int
var accumulated_damage: int
## The value the readout is heading for (or showing). Card.power_fx compares the card's new power against THIS, not
## against what is on screen mid-count, to decide whether a change is a power-up.
var target_power: int

var _power_tween: Tween = null
var _damage_tween: Tween = null
var _pulse_tween: Tween = null
## The power-up swell (animate_power_up). Owns the POWER part's `scale`, `modulate` and render priorities while it runs.
var _boost_tween: Tween = null
var _damage_pulse_tween: Tween = null
var _rest_scale := Vector3.ONE
var _rest_modulate := Color.WHITE
var _rest_priority := 0
var _rest_outline_priority := 0
var _power_part: Label3D = null
var _damage_part: Label3D = null
var _damage_counter: MeshInstance3D = null
## Label3D settings the parts copy from this node (as authored in card.tscn).
const PART_PROPERTIES := ["font", "font_size", "pixel_size", "outline_size", "outline_modulate", "modulate",
	"billboard", "double_sided", "no_depth_test", "fixed_size", "alpha_cut", "texture_filter", "shaded",
	"render_priority", "outline_render_priority", "vertical_alignment", "line_spacing"]

## POWER-UP NUMBER (the third beat of Card.power_fx): the count runs while the readout SWELLS, holds big for a moment
## and settles back, so the eye lands on the new value. Tinted warm while big; the gas puff sits behind it.
const BOOST_SCALE := 1.5
const BOOST_GROW_SECONDS := 0.22
const BOOST_COUNT_SECONDS := 0.85
const BOOST_HOLD_SECONDS := 0.30
const BOOST_SETTLE_SECONDS := 0.28
const BOOST_TINT := Color(1.0, 0.86, 0.55)
## POWER-DOWN NUMBER (power_down_drain.gd): squashed and smaller, RED - deflating rather than swelling.
const DRAIN_SCALE := Vector3(1.08, 0.74, 1.0)
const DRAIN_SHRINK_SECONDS := 0.16
const DRAIN_COUNT_SECONDS := 0.55
const DRAIN_HOLD_SECONDS := 0.18
const DRAIN_SETTLE_SECONDS := 0.30
const DRAIN_TINT := Color(1.0, 0.30, 0.26)
## Above the power-up gas/swords (power_up_burst.gd draws at 18..24), so the number is never painted over.
const BOOST_RENDER_PRIORITY := 40


func _ready() -> void:
	font = FIELD_CARD_FACE.label_font()
	pixel_size = FIELD_CARD_FACE.LABEL_PIXEL_SIZE
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	power = get_parent().power
	target_power = power
	accumulated_damage = get_parent().accumulated_damage
	_power_part = _make_part("PowerNumber")
	_damage_part = _make_part("DamagePart")
	_damage_part.position = Vector3(0.136, 0.092, -0.009)
	_damage_part.font_size = 58
	_damage_part.modulate = Color("#ffd08a")
	_rest_scale = _power_part.scale
	_rest_modulate = _power_part.modulate
	_rest_priority = _power_part.render_priority
	_rest_outline_priority = _power_part.outline_render_priority
	# This node now only carries the text; the parts draw it.
	modulate = Color(modulate.r, modulate.g, modulate.b, 0.0)
	outline_modulate = Color(outline_modulate.r, outline_modulate.g, outline_modulate.b, 0.0)
	_refresh_text()


## The power digits (probes: this is what swells, deflates and tints).
func power_part() -> Label3D:
	return _power_part


func damage_part() -> Label3D:
	return _damage_part


func _make_part(part_name: String) -> Label3D:
	var part := Label3D.new()
	part.name = part_name
	for property in PART_PROPERTIES:
		part.set(property, get(property))
	add_child(part)
	return part


func _add_damage_counter() -> void:
	_damage_counter = MeshInstance3D.new()
	_damage_counter.name = "DamageCounter"
	_damage_counter.position.z = -0.004
	_damage_counter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape := BoxMesh.new()
	shape.size = Vector3(0.123, 0.045, 0.006)
	_damage_counter.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#633718")
	_damage_counter.material_override = material
	_damage_part.add_child(_damage_counter)


func _refresh_text() -> void:
	var power_text := str(power)
	self.text = "%s/%s" % [power_text, accumulated_damage]
	if _power_part == null:
		return
	_power_part.text = power_text
	_damage_part.text = str(accumulated_damage)
	_damage_part.visible = accumulated_damage > 0
	if _damage_part.visible and _damage_counter == null:
		_add_damage_counter()


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
	_animate_emphasis(end_power, delay, Vector3.ONE * BOOST_SCALE, BOOST_TINT, BOOST_GROW_SECONDS,
		BOOST_COUNT_SECONDS, BOOST_HOLD_SECONDS, BOOST_SETTLE_SECONDS)

## The power-DOWN count (power_down_drain.gd): the readout DEFLATES - squashed, smaller, red - while it counts
## down, then recovers its rest. Same slot as the swell, so cancel_power_up() and a zone change stop either.
func animate_power_down(end_power: int, delay: float = 0.0) -> void:
	_animate_emphasis(end_power, delay, DRAIN_SCALE, DRAIN_TINT, DRAIN_SHRINK_SECONDS,
		DRAIN_COUNT_SECONDS, DRAIN_HOLD_SECONDS, DRAIN_SETTLE_SECONDS)

func _animate_emphasis(end_power: int, delay: float, scale_k: Vector3, tint: Color, grow: float, count: float,
		hold: float, settle: float) -> void:
	target_power = end_power
	if _power_tween != null and _power_tween.is_valid():
		_power_tween.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_power_part.scale = _rest_scale
	var already_big: bool = _boost_tween != null and _boost_tween.is_valid()
	if already_big:
		_boost_tween.kill()
	else:
		_power_part.render_priority = BOOST_RENDER_PRIORITY
		_power_part.outline_render_priority = BOOST_RENDER_PRIORITY - 1
	_boost_tween = create_tween()
	if delay > 0.0:
		_boost_tween.tween_interval(delay)
	_boost_tween.tween_property(_power_part, "scale", _rest_scale * scale_k, grow) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_boost_tween.parallel().tween_property(_power_part, "modulate", tint, grow)
	_boost_tween.parallel().tween_method(update_power_display, power, end_power, count) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# A parallel step lasts as long as its LONGEST member (the count), so the hold starts when the count ends.
	_boost_tween.tween_interval(hold)
	_boost_tween.tween_property(_power_part, "scale", _rest_scale, settle) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_boost_tween.parallel().tween_property(_power_part, "modulate", _rest_modulate, settle)
	_boost_tween.tween_callback(_restore_rest)

func is_boosting() -> bool:
	return _boost_tween != null and _boost_tween.is_valid() and _boost_tween.is_running()

## Seconds from the start of animate_power_up(…, delay) until the readout is back at rest.
static func boost_seconds(delay: float) -> float:
	return delay + BOOST_COUNT_SECONDS + BOOST_HOLD_SECONDS + BOOST_SETTLE_SECONDS

## Seconds from the start of animate_power_down(…, delay) until the readout is back at rest.
static func drain_seconds(delay: float) -> float:
	return delay + DRAIN_COUNT_SECONDS + DRAIN_HOLD_SECONDS + DRAIN_SETTLE_SECONDS

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
	_power_part.scale = _rest_scale
	_power_part.modulate = _rest_modulate
	_power_part.render_priority = _rest_priority
	_power_part.outline_render_priority = _rest_outline_priority
	_boost_tween = null

func animate_accumulated_damage_change(end_damage: int, duration: float = 0.75):
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_tween = create_tween()
	_damage_tween.tween_method(update_accumulated_damage_display, accumulated_damage, end_damage, duration).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_callback(_pulse_damage)

func update_power_display(newPower: int):
	power = newPower
	_refresh_text()

func update_accumulated_damage_display(newDamage: int):
	accumulated_damage = newDamage
	_refresh_text()

## The power number's pulse after a plain change.
func pulse_label():
	# The swell owns the number's scale while it runs; a pulse must not record a swollen size as "rest".
	if is_boosting():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_power_part, "scale", _rest_scale * 1.4, 0.1)
	_pulse_tween.tween_property(_power_part, "scale", _rest_scale, 0.1)

## The damage part's own pulse: it changes on its own, and it never touches the power number.
func _pulse_damage() -> void:
	if _damage_pulse_tween != null and _damage_pulse_tween.is_valid():
		_damage_pulse_tween.kill()
	_damage_part.scale = Vector3.ONE
	_damage_pulse_tween = create_tween()
	_damage_pulse_tween.tween_property(_damage_part, "scale", Vector3.ONE * 1.4, 0.1)
	_damage_pulse_tween.tween_property(_damage_part, "scale", Vector3.ONE, 0.1)
