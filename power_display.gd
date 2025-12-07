extends Label3D

var power: int
var life: int
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	power = get_parent().power
	life = get_parent().life
	self.text = '%s/%s' % [power, power]
	pass # Replace with function body.

func changePower(newPower):
	animate_power_change(newPower)
	
func changeLife(newLife):
	life = newLife
	self.text = '%s/%s' % [power, life]
# Called every frame. 'delta' is the elapsed time since the previous frame.


func animate_power_change(end_power: int, duration: float = 0.75):
	var tween = create_tween()
	tween.tween_method(update_power_display, power, end_power, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(pulse_label)

func pulse_label():
	var tween = create_tween()
	var original_scale = scale
	
	tween.tween_property(self, "scale", original_scale * 1.4, 0.1)
	tween.tween_property(self, "scale", original_scale, 0.1)

func update_power_display(newPower: int):
	power = newPower
	self.text = '%s/%s' % [power, life]
	
