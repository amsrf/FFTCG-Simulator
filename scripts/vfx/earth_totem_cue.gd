extends "res://scripts/vfx/vfx_cue.gd"
## Surviving targets launch; lethal hits keep the normal immediate break FX.
const TOTEM := preload("res://assets/effects/earth/earth_totem.tscn")
var _active: Array[Dictionary] = []

func play(event: VfxEvent) -> void:
	var longest := 0.0
	for i in range(event.targets.size()):
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error, and it would abort this cue
		# mid-play (and with it the presentation queue that awaits it).
		var entry = event.targets[i]
		if not is_instance_valid(entry):
			continue
		var target: Card = entry
		var visual: Dictionary = event.target_visuals.get(target.get_instance_id(), {})
		if not target.is_drawn_on_field() and visual.is_empty():
			continue
		var delay := float(i) * (0.20 if event.mode != "sequence" else 0.35)
		var lethal: bool = visual.get("lethal", not target.is_drawn_on_field())
		var presentation_seconds := 2.15 if lethal else 0.07 + target.damage_fx.earth_launch_seconds(event.amount) + 1.2
		longest = maxf(longest, delay + presentation_seconds)
		_strike(target, event.amount, event.seed + i * 173, delay, visual)
	await get_tree().create_timer(maxf(longest, 0.01)).timeout
	_restore_active()

func _strike(target: Card, damage: int, seed_value: int, delay: float, visual: Dictionary) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(target):
		return
	if visual.is_empty():
		if not target.is_drawn_on_field():
			return
		visual = {"transform": target.global_transform, "floor_y": target.get_parent().global_position.y}
	var pose: Transform3D = visual.transform
	var totem := TOTEM.instantiate()
	add_child(totem)
	totem.global_position = Vector3(pose.origin.x, float(visual.floor_y), pose.origin.z)
	totem.scale = Vector3.ONE * 0.42
	totem.get_node("GroundCrack").material_override.set_shader_parameter("seed", float(seed_value % 10000))
	totem.play()
	var retreat_delay := 0.35
	if not visual.get("lethal", false) and target.is_drawn_on_field():
		var motion: Tween = target.damage_fx.play_earth_launch(damage, seed_value, 0.07)
		_active.append({"card": target, "motion": motion})
		retreat_delay = 0.07 + target.damage_fx.earth_launch_seconds(damage) * 0.5
	await get_tree().create_timer(retreat_delay).timeout
	if is_instance_valid(totem):
		totem.retreat()

func cancel() -> void:
	_restore_active()
	queue_free()

func _exit_tree() -> void:
	_restore_active()

func _restore_active() -> void:
	for entry in _active:
		var card: Card = entry.card
		if is_instance_valid(card) and card.damage_fx.tween == entry.motion:
			card.damage_fx.normalize()
	_active.clear()
