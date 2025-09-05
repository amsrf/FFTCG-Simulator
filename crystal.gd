extends Node3D

# Rotation speed in degrees per second
var rotation_speed: float = 100.0

func _process(delta: float):
	# Rotate the crystal around the Y-axis
	rotate_z(deg_to_rad(rotation_speed * delta))
