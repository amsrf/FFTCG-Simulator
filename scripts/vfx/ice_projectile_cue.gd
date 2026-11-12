extends "res://scripts/vfx/vfx_cue.gd"
const PROJECTILE := preload("res://assets/effects/ice/ice_projectile.tscn")

func play(event: VfxEvent) -> void:
	var longest := 0.01
	for i in event.targets.size():
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error, and it would abort this cue
		# mid-play (and with it the presentation queue that awaits it).
		var entry = event.targets[i]
		if not is_instance_valid(entry):
			continue
		var target: Card = entry
		var visual: Dictionary = event.target_visuals.get(target.get_instance_id(), {})
		if visual.is_empty():
			if not target.is_drawn_on_field():
				continue
			visual = {"transform": target.global_transform, "floor_y": target.get_parent().global_position.y}
		var pose: Transform3D = visual.transform
		var projectile := PROJECTILE.instantiate()
		add_child(projectile)
		# Harder hits conjure a bigger crystal of a different cut, raised higher before the drop.
		projectile.set_damage_tier(event.damage_tier())
		# THE BOARD CAMERA LOOKS ALMOST STRAIGHT DOWN, from close by. Held straight up, the crystal drifts up the screen
		# away from its target and is seen end-on. So the two are split:
		#   * it is HELD mostly along the line to the camera, which keeps it over its target on screen (the drop then
		#     reads as the crystal coming down at the table), with a little lift up the screen;
		#   * its long axis lies mostly ALONG the screen, so it is seen side-on, point aimed down at the card.
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var toward_camera: Vector3 = (camera.global_position - projectile.global_position).normalized()
			var screen_up := camera.global_basis.y.normalized()
			var held: Vector3 = (toward_camera * 0.95 + screen_up * 0.12).normalized()
			var axis: Vector3 = (screen_up * 0.75 + toward_camera * 0.65).normalized()
			var to_local: Basis = projectile.global_basis.inverse()
			projectile.fall_direction = to_local * held
			projectile.spike_axis = to_local * axis
		projectile.global_position = Vector3(pose.origin.x, maxf(pose.origin.y, float(visual.floor_y)) + 0.015, pose.origin.z)
		var delay := float(i) * (0.35 if event.mode == "sequence" else 0.20)
		var start := create_tween()
		start.tween_interval(delay)
		start.tween_callback(projectile.play.bind(event.seed + i * 173))
		longest = maxf(longest, delay + projectile.duration())
	await get_tree().create_timer(longest).timeout
