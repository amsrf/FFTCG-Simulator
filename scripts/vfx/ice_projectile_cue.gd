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
		projectile.global_position = Vector3(pose.origin.x, maxf(pose.origin.y, float(visual.floor_y)) + 0.015, pose.origin.z)
		var delay := float(i) * (0.35 if event.mode == "sequence" else 0.20)
		var start := create_tween()
		start.tween_interval(delay)
		start.tween_callback(projectile.play.bind(event.seed + i * 173))
		longest = maxf(longest, delay + projectile.duration())
	await get_tree().create_timer(longest).timeout
