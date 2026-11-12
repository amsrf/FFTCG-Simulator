extends Node3D

func _ready() -> void:
	# Freeze an exact effect frame for the existing screenshot harness.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ice-tier="):
			$IceProjectile.set_damage_tier(argument.trim_prefix("--ice-tier=").to_int())
		if argument.begins_with("--ice-time="):
			$IceProjectile.reset()
			$IceProjectile.sample(argument.trim_prefix("--ice-time=").to_float())

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
		# Damage tiers: weak (<=3000), medium (<=6000), high (<9000), maximum (9000+). Shows the formed crystal.
		KEY_5, KEY_6, KEY_7, KEY_8:
			$IceProjectile.set_damage_tier(event.keycode - KEY_5)
			$IceProjectile.show_conjured()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

