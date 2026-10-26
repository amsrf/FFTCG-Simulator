extends Label3D

var power: int
var accumulated_damage: int

# Called when the node enters the scene tree for the first time.
var _power_tween: Tween = null
var _damage_tween: Tween = null


func _ready() -> void:
	power = get_parent().power
	accumulated_damage = get_parent().accumulated_damage
	self.text = '%s/%s' % [power, accumulated_damage]

func changePower(newPower):
	animate_power_change(newPower)

func changeAccumulatedDamage(newDamage):
	animate_accumulated_damage_change(newDamage)

func animate_power_change(end_power: int, duration: float = 0.75):
	# A board refresh can recompute several times in one frame. Kill the previous tween so the last value wins and
	# two tweens cannot fight over `power`.
	if _power_tween != null and _power_tween.is_valid():
		_power_tween.kill()
	_power_tween = create_tween()
	_power_tween.tween_method(update_power_display, power, end_power, duration).set_ease(Tween.EASE_OUT)
	_power_tween.tween_callback(pulse_label)

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
	var tween = create_tween()
	var original_scale = scale

	tween.tween_property(self, "scale", original_scale * 1.4, 0.1)
	tween.tween_property(self, "scale", original_scale, 0.1)
