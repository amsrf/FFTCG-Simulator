extends "res://scripts/vfx/vfx_cue.gd"
## Surviving targets launch; lethal hits keep the normal immediate break FX. The damage tier
## (VfxEvent.damage_tier_for) sets the tornado's height and length, and the card's lift and hover follow it.
const MOTION := preload("res://scripts/vfx/wind_card_motion.gd")
const TIMELINE := preload("res://scripts/vfx/wind_tornado.gd")
const TORNADO := preload("res://assets/effects/wind/wind_tornado.tscn")
var _active: Array[Dictionary] = []

func play(event: VfxEvent) -> void:
	var longest := 0.0
	var tier := VfxEvent.damage_tier_for(event.amount)
	var length := TIMELINE.length_for(tier)
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
		var presentation_seconds := 2.15 if lethal else MOTION.total_for(length) + 0.1
		longest = maxf(longest, delay + maxf(length, presentation_seconds))
		_strike(target, tier, event.seed + i * 173, delay, visual)
	await get_tree().create_timer(maxf(longest, 0.01)).timeout
	_restore_active()

func _strike(target: Card, tier: int, seed_value: int, delay: float, visual: Dictionary) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(target):
		return
	if visual.is_empty():
		if not target.is_drawn_on_field():
			return
		visual = {"transform": target.global_transform, "floor_y": target.get_parent().global_position.y}
	var pose: Transform3D = visual.transform
	var tornado := TORNADO.instantiate()
	add_child(tornado)
	tornado.global_position = Vector3(pose.origin.x, float(visual.floor_y), pose.origin.z)
	tornado.set_damage_tier(tier)
	tornado.play()
	if not visual.get("lethal", false) and target.is_drawn_on_field():
		_launch(target, tier, seed_value)

func _launch(card: Card, tier: int, seed_value: int) -> void:
	card.damage_fx.normalize()
	var mesh: Node3D = card.hand_mesh
	if mesh == null:
		return
	var edge := card.get_node_or_null("CardEdge") as Node3D
	var home := mesh.transform
	var edge_home := edge.transform if edge != null else Transform3D.IDENTITY
	var phase := float(seed_value % 1000) * 0.01
	var height: float = TIMELINE.card_height_for(tier)
	var hover_end: float = TIMELINE.length_for(tier)
	var total: float = MOTION.total_for(hover_end)
	var motion := card.create_tween()
	card.damage_fx.tween = motion
	_active.append({"card": card, "motion": motion, "mesh": mesh, "home": home, "edge": edge, "edge_home": edge_home})
	# Driven in tornado seconds: rises with the buildup, falls only after the tornado has faded.
	motion.tween_method(func(seconds: float) -> void:
		if not is_instance_valid(card) or not card.is_drawn_on_field() or card.damage_fx.tween != motion:
			return
		var pose := MOTION.pose_at(seconds, height, phase, hover_end)
		pose.origin = card.global_basis.inverse() * pose.origin
		mesh.transform = pose * home
		if is_instance_valid(edge):
			edge.transform = pose * edge_home
	, 0.0, total, total)

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
			if is_instance_valid(entry.mesh):
				entry.mesh.transform = entry.home
			if is_instance_valid(entry.edge):
				entry.edge.transform = entry.edge_home
	_active.clear()
