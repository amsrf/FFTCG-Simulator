extends "res://scripts/vfx/vfx_cue.gd"
## Presentation for one `DAMAGE` / `BOARD_DAMAGE` / `EFFECT_BREAK` event whose element is 氷.
##
## Each target gets one ice_projectile: a crystal forms, is held, and drops onto the card. Like fire, this cue owns the
## rules-facing beat at each IMPACT (the preset sets `owns_damage_reaction` and `effect_break`): the card recoils, or a
## card the ice breaks shatters, when the crystal LANDS — never at damage time, ~1.5 s before anything has hit it.
##
## The projectiles live under the tree root and free themselves once their debris and frost have played out; the cue
## only holds the presentation queue until shortly after the last impact.

const PROJECTILE := preload("res://assets/effects/ice/ice_projectile.tscn")
const MULTI_STAGGER_SECONDS := 0.20
const SEQUENCE_STAGGER_SECONDS := 0.35
## How long the queue waits past the last impact.
const HOLD_AFTER_IMPACT := 0.40

func play(event: VfxEvent) -> void:
	var amount: int = event.amount if event.kind != VfxEvent.Kind.EFFECT_BREAK else Vfx.EFFECT_BREAK_AMOUNT
	var last_impact := 0.0
	var count := 0
	for i in event.targets.size():
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error, and it would abort this cue
		# mid-play (and with it the presentation queue that awaits it).
		var entry = event.targets[i]
		if not is_instance_valid(entry) or not (entry is Card):
			continue
		var target: Card = entry
		var visual: Dictionary = event.target_visuals.get(target.get_instance_id(), {})
		if visual.is_empty():
			if not target.is_drawn_on_field():
				continue
			visual = {"transform": target.global_transform, "floor_y": target.get_parent().global_position.y}
		var pose: Transform3D = visual.transform
		var projectile := PROJECTILE.instantiate()
		projectile.name = "IceProjectile"
		get_tree().root.add_child(projectile)
		# Harder hits conjure a bigger crystal of a different cut, raised higher before the drop.
		projectile.set_damage_tier(event.damage_tier())
		# PLACE IT FIRST: the aim below is measured from the projectile's position, so it must already be on its target.
		# Aiming from wherever it was spawned bent the hold toward the wrong point, and an off-centre card (Auron on the
		# back row) saw the crystal form away from it.
		projectile.global_position = Vector3(pose.origin.x, maxf(pose.origin.y, float(visual.get("floor_y", pose.origin.y))) + 0.015, pose.origin.z)
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
		var spacing := SEQUENCE_STAGGER_SECONDS if event.mode == "sequence" else MULTI_STAGGER_SECONDS
		var delay := float(count) * spacing
		count += 1
		var timeline := projectile.create_tween()
		timeline.tween_interval(delay)
		timeline.tween_callback(projectile.play.bind(event.seed + i * 173))
		timeline.tween_interval(projectile.duration())
		timeline.tween_callback(projectile.queue_free)
		var impact: float = delay + projectile.impact_time()
		_impact(target, visual, impact, amount)
		last_impact = maxf(last_impact, impact)
	if count == 0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(last_impact + HOLD_AFTER_IMPACT).timeout


## The rules-facing beat of one crystal: a held break shatters, a surviving card recoils — when the ice lands.
func _impact(card: Card, visual: Dictionary, delay: float, amount: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(card):
		return
	if visual.has("stand_in"):
		Vfx.release_hold(card, visual, true)
	elif card.is_drawn_on_field():
		card.damage_fx.play_reaction(amount)
