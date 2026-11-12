extends "res://scripts/vfx/vfx_cue.gd"
## Surviving targets launch. A card the hit BROKE was held on its slot (Vfx.hold_for_break): a golden crystal of light
## grows up through it and it breaks as the crystal sinks (earth_break_crystal.gd). An unheld lethal hit keeps the
## plain eruption over the immediate shatter.
const TOTEM := preload("res://assets/effects/earth/earth_totem.tscn")
const BREAK_CRYSTAL := preload("res://scripts/vfx/earth_break_crystal.gd")
## The ring thrown out along the board when the column hits the card.
const SHOCKWAVE_SHADER := preload("res://shaders/earth_shockwave.gdshader")
const SHOCKWAVE_SECONDS := 0.60
## Final diameter in metres, per damage tier.
## Kept around the card (it is ~0.5 x 0.7 m on the field): the ring should spill only a little past it.
const SHOCKWAVE_DIAMETER: Array[float] = [0.78, 0.86, 0.94, 1.02]
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
		if visual.has("stand_in"):
			longest = maxf(longest, delay + BREAK_CRYSTAL.DURATION)
			_break_crystal(target, visual, event.damage_tier(), event.seed + i * 173, delay)
			continue
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
	# CONTACT: the column reaches the card 0.07 s in (the launch below starts on the same beat).
	_shockwave(Vector3(pose.origin.x, pose.origin.y + 0.012, pose.origin.z), VfxEvent.damage_tier_for(damage), 0.07)
	var retreat_delay := 0.35
	if not visual.get("lethal", false) and target.is_drawn_on_field():
		var motion: Tween = target.damage_fx.play_earth_launch(damage, seed_value, 0.07)
		_active.append({"card": target, "motion": motion})
		retreat_delay = 0.07 + target.damage_fx.earth_launch_seconds(damage) * 0.5
	await get_tree().create_timer(retreat_delay).timeout
	if is_instance_valid(totem):
		totem.retreat()

## A circular shock ring on the board at the moment of contact: a bright front and a fainter one behind it, racing
## outward and thinning as they fade. Pale dust with a dark inner line (alpha-blended: additive light vanishes on the
## pale wood), level with the card faces.
func _shockwave(at: Vector3, tier: int, delay: float) -> void:
	for wave in 2:
		var material := ShaderMaterial.new()
		material.shader = SHOCKWAVE_SHADER
		material.set_shader_parameter("strength", 0.65 if wave == 0 else 0.35)
		material.set_shader_parameter("seed", float(wave) * 17.0 + at.x * 3.0)
		material.set_shader_parameter("fade", 0.0)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		var ring := MeshInstance3D.new()
		ring.name = "Shockwave"
		ring.mesh = plane
		ring.material_override = material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.extra_cull_margin = 4.0
		add_child(ring)
		ring.global_position = at
		var diameter: float = SHOCKWAVE_DIAMETER[tier] * (1.0 if wave == 0 else 0.72)
		var sample := func(t: float) -> void:
			var spread := sqrt(t)
			ring.scale = Vector3.ONE * lerpf(0.35, diameter, spread)
			material.set_shader_parameter("ring_radius", lerpf(0.25, 0.93, spread))
			material.set_shader_parameter("ring_width", lerpf(0.085, 0.030, t))
			material.set_shader_parameter("fade", 1.0 - t * t)
		var tween := ring.create_tween()
		tween.tween_interval(delay + 0.07 * wave)
		tween.tween_method(sample, 0.0, 1.0, SHOCKWAVE_SECONDS)
		tween.tween_callback(ring.queue_free)

func _break_crystal(target: Card, visual: Dictionary, tier: int, seed_value: int, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var crystal := BREAK_CRYSTAL.new()
	crystal.name = "EarthBreakCrystal"
	# Not under the cue: if the queue cuts the cue short, the crystal still finishes and releases its hold.
	var host: Node = visual.get("stand_in", null)
	host = host.get_parent() if is_instance_valid(host) else get_tree().root
	host.add_child(crystal)
	crystal.play(target, visual, tier, seed_value)
	var pose: Transform3D = visual.get("transform", Transform3D.IDENTITY)
	_shockwave(Vector3(pose.origin.x, pose.origin.y + 0.012, pose.origin.z), tier, 0.10)

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
