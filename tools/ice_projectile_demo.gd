extends Node3D

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			$IceProjectile.play()
		KEY_R:
			$IceProjectile.reset()
		KEY_1:
			$IceProjectile.show_conjured()
		KEY_2:
			Engine.time_scale = 0.25 if is_equal_approx(Engine.time_scale, 1.0) else 1.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

