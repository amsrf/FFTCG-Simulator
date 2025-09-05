extends Node3D

# In your main script or in _ready() of your Node3D
func _ready():
	pass


func set_text(text):
	$Label3D.text = text
	
func set_on_press_callback(callback: Callable):
	$Area3D.set_on_press_callback(callback)
