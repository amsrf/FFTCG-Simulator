extends Node3D
## Headless probe for the blocking visuals.
##
## Run it instead of the game:
##   "<godot>" --headless res://tests/block_probe.tscn --quit-after 5000
##
## Covers the two cases the human sees, and the rules the cues are supposed to obey:
##
##   * LOCAL defender — everything that could block is marked (blue ring), the pick turns
##     orange and draws the arc centre-to-centre, a reselect moves BOTH, clicking the same
##     card deselects, and clearing the prompt leaves every card dark again
##   * OPPONENT defender — the arc appears for their pick, but NO blue ring is used, since
##     that cue means "the game is asking YOU to choose"
#---
## It says nothing about how any of it LOOKS.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _failures: Array[String] = []
var _field = null

func _ready() -> void:
	print("\n[BlockProbe] ================= blocking visuals =================")
	MatchSetup.config = MatchSetup.build_config("debug")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	$Camera3D.current = true
	_field = game.get("field")
	if _field == null:
		_expect(false, "the game scene exposed a Field")
		_report()
		get_tree().quit()
		return

	# The debug board gives the opponent one untapped Forward (Squall) and the player two
	# (Zack, Squall), which is exactly what the reselect case needs.
	var their_attacker: Card = _first_untapped_forward("opponent")
	var mine: Array = _untapped_forwards("player")
	_expect(their_attacker != null, "the opponent has an untapped Forward to attack with")
	_expect(mine.size() >= 2, "the player has at least two untapped Forwards (got %d)" % mine.size())
	if their_attacker == null or mine.size() < 2:
		_report()
		get_tree().quit()
		return
	_field.set_attacker(their_attacker)
	_expect(_field.attacker_card == their_attacker, "the attacker is declared")

	# ---- LOCAL DEFENDER: the game is asking the human ----------------------------
	_field.set_blockable("player", true)
	var marked: Array = _marked()
	print("[BlockProbe] marked blue: %s" % [_names(marked)])
	_expect(marked.size() == mine.size(),
		"exactly my %d untapped Forwards are marked (got %d)" % [mine.size(), marked.size()])
	var only_mine: bool = true
	for c in marked:
		if c.controller != "player" or not _field.can_block(c):
			only_mine = false
	_expect(only_mine, "every marked card is one of my own untapped Forwards")

	var first: Card = mine[0]
	_field.set_blocker_card(first)
	_expect(_field.blocker_card == first, "clicking a card selects it as the blocker")
	_expect(first.ring_selected(), "the selected blocker turns orange")
	# A single attacker still produces exactly one arc; a party produces one per member (see party_probe).
	var arrow = _field.block_arrows.back() if not _field.block_arrows.is_empty() else null
	_expect(_field.block_arrows.size() == 1, "a single-attacker block draws exactly ONE arc")
	_expect(arrow != null and arrow.is_aiming, "selecting a blocker draws an arc")
	if arrow != null:
		var start: Vector3 = first.get_global_face_centre()
		var target: Vector3 = their_attacker.get_global_face_centre()
		print("[BlockProbe] arc %s -> %s (blocker centre %.3f m from attacker centre)"
			% [arrow.start_pos, target, start.distance_to(target)])
		_expect(arrow.start_pos.distance_to(start) < 0.01,
			"the arc starts at the blocker's CENTRE")
		var tip_gap: float = _nearest_vertex(arrow, target)
		var path: float = _farthest_vertex(arrow, start)
		var chord: float = start.distance_to(target)
		print("[BlockProbe] tip is %.4f m from the attacker's centre; the ribbon runs %.3f m for a %.3f m chord"
			% [tip_gap, path, chord])
		_expect(tip_gap < 0.05, "the arc lands on the attacker's centre")
		# A cross-row link must NOT bow along its own chord: that made a 1.54 m path for an
		# 0.85 m span, reading as a long loop rather than an arc. (The shaft is trimmed for
		# the head, so this measures slightly under the true path.)
		_expect(path < chord * 1.5,
			"the arc bows instead of running along its own chord (%.2fx)" % (path / chord))

	# Reselect: the orange and the arc both move, nothing is left behind.
	var second: Card = mine[1]
	_field.set_blocker_card(second)
	print("[BlockProbe] reselected: %s" % second.card_name)
	_expect(not first.ring_selected(), "the previous blocker is no longer orange")
	_expect(second.ring_selected(), "the new blocker is orange")
	_expect(_field.blocker_card == second, "the new blocker is the selected one")
	# The arcs are recreated on every selection, so the earlier `arrow` node has been freed — read the new ones.
	_expect(_field.block_arrows.size() == 1, "reselecting keeps exactly one arc for a single attacker")
	var moved = _field.block_arrows.back() if not _field.block_arrows.is_empty() else null
	if moved != null:
		_expect(moved.start_pos.distance_to(second.get_global_face_centre()) < 0.01,
			"the arc moved to the new blocker's centre")

	# Clicking the same card again deselects.
	_field.set_blocker_card(second)
	_expect(_field.blocker_card == null, "clicking the same card again deselects it")
	_expect(not second.ring_selected(), "deselecting clears the orange")
	_expect(arrow == null or not arrow.is_aiming, "deselecting hides the arc")

	# --- block_disabled: a status the data has always applied and nothing consulted -------------------------------
	# Red Mage's ability hands this out, and it did nothing at all. It has to stop the RING and the CLICK together —
	# "everything that glows is also clickable" only holds if both go through can_block().
	var squall: Card = null
	for c in _field.get_front_cards_for("player"):
		if c.card_name == "Squall":
			squall = c
	_expect(squall != null, "the debug board has a player Forward to try this on")
	if squall != null:
		_expect(_field.can_block(squall), "an untapped Forward can block to begin with")
		squall.add_status_effect("block_disabled", 1)
		print("[BlockProbe] %s with block_disabled: can_block=%s can_attack=%s" % [
			squall.card_name, _field.can_block(squall), squall.can_attack()])
		_expect(not _field.can_block(squall), "block_disabled stops it blocking")
		_expect(squall.can_attack(), "but does NOT stop it attacking — the status is about blocking only")
		_field.set_blockable("player", true)
		_expect(not squall.is_valid_target, "and it is not offered as a blocker — no blue ring")
		squall.turn_end()
		_expect(_field.can_block(squall), "the status expires at the end of the turn and blocking comes back")

	# The prompt glow is only for the duration of the question.
	_field.set_blockable("player", false)
	_expect(_marked().is_empty(), "clearing the prompt leaves every card dark again")

	# ---- OPPONENT DEFENDER: not the human's choice -------------------------------
	var their_blocker: Card = their_attacker  # any of their untapped Forwards will do
	_field.show_block_arc(their_blocker)
	print("[BlockProbe] opponent blocks with %s" % their_blocker.card_name)
	# show_block_arc() recreates the arcs, so the node captured above is gone — read the fresh one.
	var their_arrow = _field.block_arrows.back() if not _field.block_arrows.is_empty() else null
	_expect(their_arrow != null and their_arrow.is_aiming, "the opponent's pick draws an arc for us to see")
	if their_arrow != null:
		_expect(their_arrow.start_pos.distance_to(their_blocker.get_global_face_centre()) < 0.01,
			"their arc starts at their blocker's centre")
	_expect(_marked().is_empty(),
		"no blue ring is used for the opponent's pick — that cue means \"your choice\"")

	# And the whole thing is cleared when the combat's blocker resets.
	_field.reset_blocker()
	_expect(_field.block_arrows.is_empty(), "reset_blocker() disposes of every arc")
	_expect(not their_blocker.ring_selected(), "reset_blocker() clears any orange")

	await _check_clash_presentation(game)
	_check_earth_totem()
	await _check_earth_launch(game)
	_report()
	get_tree().quit()

func _check_earth_launch(game: Node) -> void:
	var card: Card = _field.get_front_cards_for("player").front()
	var root_pose := card.global_transform
	var motion := card.damage_fx.play_earth_launch(3000, 42)
	motion.pause()
	motion.custom_step(card.damage_fx.earth_launch_seconds(3000) * 0.5)
	var weak_height := card.hand_mesh.global_position.y - card.global_position.y
	_expect(card.get_node("CardEdge").transform.is_equal_approx(card.hand_mesh.transform) and not card.power_label.visible,
		"earth waver carries the thickness edge and hides the stationary power readout")
	_expect(absf(weak_height - 1.0) < 0.01 and card.global_transform.is_equal_approx(root_pose),
		"earth launch follows its gravity arc while leaving the field-owned card root unchanged")
	var landed: Array = []
	var record_landing := func(): landed.append(true)
	card.damage_fx.earth_landed.connect(record_landing)
	motion.custom_step(card.damage_fx.earth_contact_seconds - card.damage_fx.earth_launch_seconds(3000) * 0.5 - 0.001)
	_expect(not card.hand_mesh.basis.is_equal_approx(Basis.IDENTITY) and landed.is_empty(),
		"earth target approaches the ground with only a small residual tilt")
	motion.custom_step(0.002)
	_expect(landed.size() == 1 and not card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"survivor makes first contact with a small residual pose before settling")
	motion.custom_step(0.08)
	_expect(card.damage_fx._earth_lowest_offset(card.hand_mesh.transform) >= card.damage_fx._earth_lowest_offset(Transform3D.IDENTITY) - 0.001,
		"post-contact settling keeps all card corners above the resting plane")
	card.damage_fx.earth_landed.disconnect(record_landing)
	motion.custom_step(card.damage_fx.earth_launch_seconds(3000))
	_expect(card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"earth launch lands exactly in its original mesh pose")
	motion = card.damage_fx.play_earth_launch(10000, 42)
	motion.pause()
	motion.custom_step(card.damage_fx.earth_launch_seconds(10000) * 0.5)
	_expect(card.hand_mesh.global_position.y - card.global_position.y > weak_height * 2.0
		and card.damage_fx.earth_launch_seconds(10000) > card.damage_fx.earth_launch_seconds(3000),
		"higher Earth damage produces greater launch height and longer airtime")
	card.damage_fx.normalize()
	_expect(card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY) and not card.damage_fx.is_reacting(),
		"interrupting an earth launch clears its tumbling pose")
	for amount in [3000, 6000, 8000, 10000]:
		for seed_value in [11, 42, 173, 901]:
			var contact_poses: Array[Transform3D] = []
			var save_contact := func(): contact_poses.append(card.hand_mesh.transform)
			card.damage_fx.earth_landed.connect(save_contact)
			motion = card.damage_fx.play_earth_launch(amount, seed_value)
			motion.pause()
			var contact_time := card.damage_fx.earth_contact_seconds
			# The thrown card flips end over end (pitch) and is flat again well before it lands: a whole number of
			# turns, with the spin dying out, so the landing needs no correction.
			var flipped := false
			var late_tilt := 0.0
			for step in range(24):
				motion.custom_step(contact_time / 25.0)
				var tilt := card.hand_mesh.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
				flipped = flipped or tilt > deg_to_rad(150.0)
				if step >= 21:
					late_tilt = maxf(late_tilt, tilt)
			_expect(flipped and late_tilt < deg_to_rad(12.0),
				"Earth card flips over in the air and is nearly flat for the last stretch of the fall")
			motion.custom_step(contact_time / 25.0 + 0.00001)
			var contact: Transform3D = contact_poses.front()
			var world_offset: Vector3 = card.global_basis * contact.origin
			_expect(contact.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < deg_to_rad(3.0)
				and Vector2(world_offset.x, world_offset.z).length() < 0.01,
				"planned Earth landing is within 3 degrees and 1 cm (damage %d, seed %d)" % [amount, seed_value])
			motion.custom_step(0.13)
			card.damage_fx.earth_landed.disconnect(save_contact)
			motion = card.damage_fx.play_earth_launch(amount, seed_value)
			motion.pause()
			_expect(is_equal_approx(card.damage_fx.earth_contact_seconds, contact_time),
				"Earth contact timing repeats deterministically for the same damage and seed")
			card.damage_fx.normalize()
	var cue = preload("res://assets/effects/earth/earth_totem_cue.tscn").instantiate()
	game.add_child(cue)
	cue.play(preload("res://scripts/vfx/vfx_event.gd").new(VfxEvent.Kind.DAMAGE, [card], "土", 6000))
	var totem: Node3D = cue.get_child(0)
	var dust_bursts: Array = []
	totem.dust_emitted.connect(func(): dust_bursts.append(true))
	await get_tree().create_timer(0.08 + card.damage_fx.earth_launch_seconds(6000) * 0.5 + 0.05).timeout
	_expect(totem.get_node("AnimationPlayer").current_animation == "retreat" and card.damage_fx.is_reacting(),
		"earth totem starts withdrawing while the launched card is still falling")
	await get_tree().create_timer(0.19).timeout
	_expect(dust_bursts.size() >= 2,
		"withdrawing earth totem emits another dust burst")
	cue.queue_free()
	await get_tree().process_frame
	_expect(card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"cancelling the Earth cue restores the target mesh")
	var preset := Vfx.preset_for_element("土")
	_expect(preset != null and preset.owns_damage_reaction and preset.impact_scene != null and preset.board_impact_scene != null,
		"Earth damage preset owns launch presentation for single and area hits")
	var source: Card = game.create_card(100, "player")
	game.add_child(source)
	var ctx = preload("res://scripts/effects/effect_context.gd").new(game, source, "test")
	ctx.damage([card], 1000)
	_expect(card.damage_fx.is_reacting() and Vfx.get_events().back().element == "土",
		"normal EffectContext Earth damage starts the configured launch presentation")
	await get_tree().create_timer(2.5).timeout
	_expect(card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"normal Earth damage completes with the field card back at rest")
	var second_target: Card = _field.get_front_cards_for("opponent").front()
	ctx.board_damage([card, second_target], 1000)
	await get_tree().create_timer(0.35).timeout
	var area_totems: Array[Node3D] = []
	for cue_node in Vfx.get_children():
		for effect in cue_node.get_children():
			if effect is Node3D and effect.has_node("GroundCrack"):
				area_totems.append(effect)
	_expect(area_totems.size() == 2 and card.damage_fx.is_reacting() and second_target.damage_fx.is_reacting(),
		"real area Earth damage launches every target with its own staggered totem")
	if area_totems.size() == 2:
		var crack_a := area_totems[0].get_node("GroundCrack") as MeshInstance3D
		var crack_b := area_totems[1].get_node("GroundCrack") as MeshInstance3D
		_expect(crack_a.material_override != crack_b.material_override
			and float(crack_a.material_override.get_shader_parameter("opacity")) > 0.5
			and float(crack_b.material_override.get_shader_parameter("opacity")) > 0.5,
			"multiple Earth impacts show independent ground cracks without shared fade state")
	await get_tree().create_timer(2.4).timeout
	_expect(card.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY)
		and second_target.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"all area Earth targets return to their resting poses")
	var snapshot := card.global_transform
	var shards_before := game.find_children("CardShards*", "Node3D", true, false).size()
	ctx.damage([card], 100000)
	_expect(not card.is_on_field() and card.current_zone == Card.Zone.GRAVEYARD,
		"lethal Earth damage moves the real card to the Break Zone immediately")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# THE BREAK IS STAGED: a stand-in holds the card on its slot, a golden crystal grows up through it, and it shatters
	# only when the crystal starts to sink (earth_break_crystal.gd). The real card waits, hidden, in the Break Zone.
	var held: Array = game.find_children("HeldCard*", "Node3D", true, false)
	_expect(held.size() == 1 and not card.visible
		and game.find_children("CardShards*", "Node3D", true, false).size() == shards_before,
		"lethal Earth damage holds the card on its slot (stand-in, real card hidden) instead of shattering at once")
	var crystals: Array = game.find_children("EarthBreakCrystal*", "Node3D", true, false)
	_expect(crystals.size() == 1, "and a crystal grows up through it")
	await get_tree().create_timer(0.55).timeout
	_expect(held.size() == 1 and is_instance_valid(held[0])
		and (held[0] as Node3D).global_position.distance_to(snapshot.origin) < 0.03,
		"the card stays on its slot (it is not carried) while the crystal stands")
	await get_tree().create_timer(0.45).timeout
	_expect(game.find_children("HeldCard*", "Node3D", true, false).size() == 1
		and game.find_children("CardShards*", "Node3D", true, false).size() == shards_before,
		"the card is still whole while the crystal sinks and vanishes from the top down")
	await get_tree().create_timer(0.75 + preload("res://scripts/vfx/earth_break_crystal.gd").BUILDUP).timeout
	_expect(game.find_children("CardShards*", "Node3D", true, false).size() == shards_before + 1
		and game.find_children("HeldCard*", "Node3D", true, false).is_empty() and card.visible,
		"it shatters once the crystal has gone back down, and the real card shows in the Break Zone")
	await Vfx.idle()
	# A break BY EFFECT from an Earth source gets the same impale.
	var victim: Card = game.create_card(41, "opponent")
	game.add_child(victim)
	_field.play_card(victim, true, false)
	await get_tree().process_frame
	ctx.break_cards([victim])
	await get_tree().process_frame
	_expect(not victim.is_on_field() and game.find_children("HeldCard*", "Node3D", true, false).size() == 1
		and game.find_children("EarthBreakCrystal*", "Node3D", true, false).size() == 1,
		"an Earth effect that breaks a card outright gets the crystal too")
	await get_tree().create_timer(3.0).timeout
	source.queue_free()
	var demo = preload("res://tools/earth_damage_demo.tscn").instantiate()
	add_child(demo)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(demo.target != null, "earth damage demo selects a real field card for preview")
	demo._hit()
	_expect(demo.target.damage_fx.is_reacting(), "earth damage demo replays the production launch cue")
	demo._area = true
	demo._hit()
	await get_tree().create_timer(0.25).timeout
	_expect(demo._preview_targets.size() > 1 and demo._cue.get_child_count() > 1,
		"damage demo multi-target mode previews several production totems")
	demo._area = false
	demo._lethal = true
	demo._hit()
	demo._hit()
	await get_tree().process_frame
	_expect(not demo.target.visible and not demo.target.damage_fx.is_reacting() and demo._preview_shards.size() == 1,
		"lethal preview immediately shatters the target without launching it")
	demo._reset()
	await get_tree().process_frame
	_expect(demo.target.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY) and demo.target.visible,
		"earth damage demo reset restores its target")
	demo.queue_free()


func _check_earth_totem() -> void:
	var demo = preload("res://tools/earth_totem_demo.tscn").instantiate()
	add_child(demo)
	var totem = demo.get_node("EarthTotem")
	totem.show_raised()
	var lower: Node3D = totem.get_node("Lift/LowerRock")
	var upper: Node3D = totem.get_node("Lift/UpperRock")
	var lower_pose := lower.transform
	var upper_pose := upper.transform
	_expect(lower.scene_file_path.ends_with("Free_Rock_Model_3.fbx") and upper.scene_file_path.ends_with("Free_Rock_Model_3.fbx"),
		"earth totem contains two independently editable Model 3 instances")
	var lower_bounds := _totem_bounds(lower)
	var upper_bounds := _totem_bounds(upper)
	var total := lower_bounds.merge(upper_bounds)
	print("[BlockProbe] totem assembly bounds: %s" % total)
	_expect(total.size.y > 1.4 and total.size.y < 2.2 and absf(total.position.y) < 0.1
		and upper_bounds.position.y <= lower_bounds.end.y,
		"two rocks form a continuous upright column resting on the floor")
	for model in [0, 1]:
		var emitter: GPUParticles3D = totem.get_node("Debris/Rocks%d" % model)
		var mesh: Mesh = emitter.draw_pass_1
		_expect(emitter.source_scene.resource_path.ends_with("Free_Rock_Model_%d.fbx" % model) and mesh != null,
			"debris emitter uses the selected Rock Model %d mesh" % model)
		if mesh != null:
			var mesh_bounds := mesh.get_aabb()
			_expect(mesh_bounds.get_center().length() < 0.001
				and maxf(mesh_bounds.size.x, maxf(mesh_bounds.size.y, mesh_bounds.size.z)) < 1.001,
				"debris Model %d is centered and normalized for small particle scales" % model)
		var particles := emitter.process_material as ParticleProcessMaterial
		_expect(emitter.one_shot and particles.scale_min < particles.scale_max and particles.scale_max < 0.2
			and particles.angular_velocity_min < 0.0 and particles.angular_velocity_max > 0.0
			and particles.gravity.y < 0.0,
			"debris Model %d has varied sizes, spin and falling gravity" % model)
		var minimum_upward_speed := particles.initial_velocity_min * cos(deg_to_rad(particles.spread))
		var minimum_peak := emitter.global_position.y + minimum_upward_speed * minimum_upward_speed / (2.0 * absf(particles.gravity.y))
		_expect(minimum_peak > total.end.y + 0.1 and emitter.lifetime > particles.initial_velocity_max / absf(particles.gravity.y),
			"debris Model %d can clear the totem even at its slowest wide-angle launch" % model)
	var base: Node3D = totem.get_node("BaseRocks")
	var used_models: Dictionary = {}
	for stone: MeshInstance3D in base.get_children():
		used_models[stone.source_scene.resource_path] = true
		_expect(stone.mesh != null and stone.material_override != null,
			"base stone has its selected normalized mesh and earth material")
	_expect(base.get_child_count() == 8 and used_models.size() == 3,
		"totem base combines eight individually editable rocks from Models 0, 1 and 2")
	var puffs: GPUParticles3D = totem.get_node("Dust/BasePuffs")
	var wisps: GPUParticles3D = totem.get_node("Dust/Wisps")
	for dust in [puffs, wisps]:
		var process := dust.process_material as ParticleProcessMaterial
		var dust_material := dust.material_override as ShaderMaterial
		_expect(dust.one_shot and dust.draw_pass_1 is QuadMesh and dust_material != null
			and dust_material.shader.resource_path == "res://shaders/earth_dust.gdshader",
			"dust layer uses a one-shot billboard with its own cloud shader")
		_expect(process.color_ramp.gradient.get_color(0).a == 0.0
			and process.color_ramp.gradient.get_color(process.color_ramp.gradient.get_point_count() - 1).a == 0.0
			and process.scale_curve.curve.sample(1.0) > process.scale_curve.curve.sample(0.0),
			"dust grows and fades fully over its lifetime")
	_expect(wisps.lifetime > puffs.lifetime and float(wisps.material_override.get_shader_parameter("opacity")) < float(puffs.material_override.get_shader_parameter("opacity")),
		"wisps linger longer and remain lighter than the base burst")
	var crack: MeshInstance3D = totem.get_node("GroundCrack")
	_expect(crack.position.y > 0.0 and crack.mesh is PlaneMesh
		and crack.mesh.size == Vector2(2.5, 2.5)
		and crack.material_override.shader.resource_path == "res://shaders/earth_ground_crack.gdshader",
		"totem has a procedural black crack plane just above the floor")
	var another = preload("res://assets/effects/earth/earth_totem.tscn").instantiate()
	add_child(another)
	another.reset()
	_expect(crack.material_override != another.get_node("GroundCrack").material_override
		and float(crack.material_override.get_shader_parameter("opacity")) > 0.9,
		"resetting one totem does not fade another totem's crack")
	another.queue_free()
	var rise: AnimationPlayer = totem.play()
	rise.advance(0.03)
	_expect(puffs.emitting and wisps.emitting and not totem.get_node("Debris/Rocks0").emitting,
		"rise timeline starts dust just before the flying rock burst")
	rise.advance(0.10 - 0.03)
	_expect(totem.get_node("Debris/Rocks0").emitting and totem.get_node("Debris/Rocks1").emitting,
		"rise animation triggers both debris bursts")
	var lift: Node3D = totem.get_node("Lift")
	_expect(lift.position.y > -0.4 and lift.position.y < 0.07
		and lower.transform.is_equal_approx(lower_pose) and upper.transform.is_equal_approx(upper_pose),
		"totem rises as one unit without overwriting editable rock offsets")
	rise.advance(0.10)
	_expect(lift.position.y > 0.0 and lift.position.y < 0.1, "totem punches slightly above its final height by 0.2 seconds")
	rise.advance(0.15)
	_expect(absf(lift.position.y) < 0.001, "totem settles back from its small overshoot by 0.35 seconds")
	rise.advance(totem.rise_seconds)
	_expect(lift.position.is_zero_approx(), "totem ascent finishes at its raised placement")
	_expect(base.position.is_zero_approx(), "base rocks emerge into their final ground placement")
	var retreat: AnimationPlayer = totem.retreat()
	retreat.advance(0.06)
	_expect(lift.position.y > 0.03, "retreat begins with a small upward wobble")
	retreat.advance(0.6)
	_expect(lift.position.y <= -1.79 and base.position.y < -0.3, "retreat sinks both totem and base beneath the floor")
	retreat.advance(0.4)
	_expect(float(crack.material_override.get_shader_parameter("opacity")) < 0.01,
		"ground crack fades away after the totem withdraws")
	totem.reset()
	_expect(base.position.y < -0.3, "reset hides the base stones beneath the ground before the next rise")
	_expect(not puffs.visible and not wisps.visible and not puffs.emitting and not wisps.emitting,
		"reset also hides and stops dust from the previous replay")
	_expect(not totem.get_node("Debris/Rocks0").visible and not totem.get_node("Debris/Rocks1").emitting,
		"reset hides and stops debris from the previous replay")
	demo.queue_free()

func _totem_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
		_expect(mesh.material_override != null, "totem rock uses the supplied earth texture material")
	return result

func _check_clash_presentation(game: Node) -> void:
	var player_cards: Array = _field.get_front_cards_for("player")
	var opponent_cards: Array = _field.get_front_cards_for("opponent")
	if player_cards.is_empty() or opponent_cards.is_empty():
		_expect(false, "clash presentation has two field cards")
		return
	var attacker: Card = player_cards.front()
	var defender: Card = opponent_cards.front()
	var original_a := attacker.global_transform
	var original_b := defender.global_transform
	var cinema = preload("res://scenes/game/clash_cinematic.tscn").instantiate()
	game.add_child(cinema)
	cinema.random_seed = 42
	cinema.play(attacker, defender, original_a, original_b, true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.10).timeout
	_expect(cinema._proxy_a.global_basis.get_scale().is_equal_approx(original_a.basis.get_scale())
		and cinema._proxy_b.global_basis.get_scale().is_equal_approx(original_b.basis.get_scale()),
		"clash lift preserves both cards' original scale")
	_expect(cinema._proxy_a.global_position.y > original_a.origin.y,
		"clash starts by lifting the card in world Y")
	var aligned: bool = not cinema._same_column(original_a.origin, original_b.origin)
	var lift_time: float = maxf(cinema.lift_seconds, cinema.align_seconds) if aligned else cinema.lift_seconds
	await get_tree().create_timer(lift_time + cinema.windup_seconds - 0.10 + 0.02).timeout
	var proxy_a: Card = cinema._proxy_a
	var aligned_rotation := Vector3(0.0, cinema._yaw_towards(original_a.origin, original_b.origin), 0.0) if aligned else original_a.basis.orthonormalized().get_euler()
	var relative := Basis.from_euler(aligned_rotation).inverse() * proxy_a.basis.orthonormalized()
	_expect(relative.is_equal_approx(Basis(Vector3.RIGHT, deg_to_rad(cinema.windup_pitch_degrees))),
		"wind-up pitches around the aligned card's own X axis")
	var defender_alignment := Vector3(0.0, cinema._yaw_towards(original_b.origin, original_a.origin), 0.0) if aligned else original_b.basis.orthonormalized().get_euler()
	var defender_relative: Basis = Basis.from_euler(defender_alignment).inverse() * cinema._proxy_b.basis.orthonormalized()
	_expect(defender_relative.is_equal_approx(Basis(Vector3.RIGHT, deg_to_rad(32.0))),
		"opponent winds up with positive 32-degree X pitch opposite the player")
	var away := original_a.origin - original_b.origin
	away.y = 0.0
	_expect((proxy_a.global_position - original_a.origin).dot(away.normalized()) > cinema.windup_distance * 0.8,
		"wind-up draws the card backward before the impact")
	await get_tree().create_timer(cinema.windup_hold_seconds + cinema.charge_seconds + cinema.hitstop_seconds + 0.02).timeout
	var defeated_proxy: Card = cinema._proxy_b
	var tumble_start := defeated_proxy.global_transform
	_expect(not cinema._defeated.is_empty() and defeated_proxy.visible,
		"defeated proxy remains intact at the start of knockback")
	await get_tree().create_timer(0.15).timeout
	_expect(defeated_proxy.visible and defeated_proxy.global_position.distance_to(tumble_start.origin) > 0.1
		and not defeated_proxy.global_basis.orthonormalized().is_equal_approx(tumble_start.basis.orthonormalized()),
		"defeated card travels and tumbles before shattering")
	await cinema.finished
	var shards: Array = game.find_children("CardShards*", "Node3D", true, false)
	_expect(not shards.is_empty(), "clash creates delayed shards for the defeated card")
	if not shards.is_empty():
		var effect: Node3D = shards.back()
		_expect(effect.global_transform.is_equal_approx(defeated_proxy.global_transform),
			"defeated card shatters at its current airborne spinning pose")
	_expect(attacker.global_transform.is_equal_approx(original_a) and defender.global_transform.is_equal_approx(original_b),
		"clash proxies leave the real card transforms unchanged")
	_expect(attacker.visible and defender.visible,
		"clash cleanup restores real card visibility")
	cinema.queue_free()

func _untapped_forwards(controller: String) -> Array:
	var out: Array = []
	for c in _field.get_all_cards():
		if c.controller == controller and _field.can_block(c):
			out.append(c)
	return out

func _first_untapped_forward(controller: String) -> Card:
	var found: Array = _untapped_forwards(controller)
	return found[0] if found.size() > 0 else null

func _marked() -> Array:
	var out: Array = []
	for c in _field.get_all_cards():
		if c.is_valid_target:
			out.append(c)
	return out

## Every vertex of every surface. The TIP lives in the head (surface 1), so scanning the
## shaft alone misses the very point the arrow lands on.
func _vertices(arrow) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = arrow.line.mesh
	if mesh == null:
		return out
	for s in range(mesh.get_surface_count()):
		out.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out

## Nearest vertex to a point. For the TARGET this is the head's tip, so "the arrow lands
## here" is this being ~0.
func _nearest_vertex(arrow, point: Vector3) -> float:
	var verts: PackedVector3Array = _vertices(arrow)
	if verts.is_empty():
		return -1.0
	var near: float = INF
	for v in verts:
		near = minf(near, point.distance_to(v))
	return near

func _farthest_vertex(arrow, point: Vector3) -> float:
	var mesh: ArrayMesh = arrow.line.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return -1.0
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var far: float = 0.0
	for v in verts:
		far = maxf(far, point.distance_to(v))
	return far

func _names(cards: Array) -> String:
	var out: Array[String] = []
	for c in cards:
		out.append("%s/%s" % [c.card_name, c.controller])
	return str(out)

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("[BlockProbe]  ok  %s" % what)
	else:
		_failures.append(what)
		print("[BlockProbe] FAIL %s" % what)

func _report() -> void:
	if _failures.is_empty():
		print("[BlockProbe] RESULT: all checks passed\n")
		return
	print("[BlockProbe] RESULT: %d check(s) FAILED" % _failures.size())
	for f in _failures:
		print("[BlockProbe]   x %s" % f)
	print("")
