extends Node
## CARD DAMAGE REACTION probe.
##
## The reference is clip4: effect damage makes a card pop off the table, scale
## up and tilt, then shake/settle. The reaction must live on HandMesh (not the
## Card layout) and must not survive a zone change.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DamageReaction] ok   %s" % what)
	else:
		_fails += 1
		print("[DamageReaction] FAIL %s" % what)


func _play_card(game: Node, field: Node, id: int) -> Card:
	var card: Card = game.create_card(id, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")

	var card: Card = _play_card(game, field, 41)
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	_expect(card.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"the card starts at its resting mesh pose")

	var fx = card.damage_fx
	var edge: Node3D = card.get_node("CardEdge")
	var badge: Node3D = card.get_node("CostBadge")
	var label_home: Transform3D = card.power_label.transform
	var badge_home: Transform3D = badge.transform
	var far_at := func() -> Vector3: return card.global_transform * (card.hand_mesh.transform * Vector3(0, 0, -0.3))
	var near_at := func() -> Vector3: return card.global_transform * (card.hand_mesh.transform * Vector3(0, 0, 0.3))
	var rest_far: Vector3 = far_at.call()
	var rest_near: Vector3 = near_at.call()
	card.suffer_damage(5000, "Ability", "player")
	# SNAP: up within a couple of frames (reference frames 62 -> 63).
	await get_tree().create_timer(0.08).timeout
	_expect(fx.is_reacting(), "effect damage starts a hit reaction")
	var near_rise: float = near_at.call().y - rest_near.y
	var far_rise: float = far_at.call().y - rest_far.y
	_expect(near_rise > 0.25, "the card snaps up off the board (bottom edge +%.2f m)" % near_rise)
	var tip: float = rad_to_deg(asin(clampf((far_rise - near_rise) / (0.6 * card.global_basis.get_scale().y), -1.0, 1.0)))
	_expect(tip > 15.0 and tip < 28.0, "it tips toward the camera about its bottom edge (%.1f deg)" % tip)
	var toward: Vector3 = card.get_viewport().get_camera_3d().global_position - card.global_position
	toward.y = 0.0
	_expect((far_at.call() - rest_far).dot(toward) > 0.0, "the far edge swings toward the camera")
	_expect(absf(card.hand_mesh.scale.x - 1.0) < 0.001, "it does not scale")
	# SHADING: turned toward the light, the face is brighter (the wolf: ~+15%).
	var lit: float = fx.face_light()
	_expect(lit > 0.1 and lit < 0.25, "the tipped face is lit brighter (face_light %+.3f)" % lit)
	_expect(edge.transform.is_equal_approx(card.hand_mesh.transform), "the thickness edge rides with the face")
	_expect(badge.transform.is_equal_approx(card.hand_mesh.transform * badge_home), "the cost crystal rides with the face")
	_expect(card.power_label.transform.is_equal_approx(card.hand_mesh.transform * label_home), "the power readout rides with the face")
	_expect(fx.shadow_strength() > 0.3, "the lifted card casts a shadow on the board")

	# Every hit is rolled. Sweep many rolls (every tier, both seats): within range, never into the board, and different.
	var lowest := INF
	var in_range := true
	var yaw_signs := {}
	var rock_signs := {}
	for seed_value in range(60):
		var tier: int = seed_value % 4
		var p: Dictionary = fx.roll_reaction(tier, seed_value)
		in_range = in_range and p.lift >= fx.REACTION_LIFT[tier] * 0.85 - 0.0001 and p.lift <= fx.REACTION_LIFT[tier] * 1.15 + 0.0001 \
			and absf(p.pitch - fx.REACTION_PITCH_DEG[tier]) <= 3.0001 and p.end <= 1.0 and p.rock_start < p.land
		yaw_signs[signf(p.yaw)] = true
		rock_signs[p.rock_sign] = true
		for far_sign in [-1.0, 1.0]:
			for i in range(0, 101):
				var pose: Transform3D = fx.reaction_pose(float(i) * 0.01, far_sign, p)
				for corner in [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(-0.2145, 0, 0.3), Vector3(0.2145, 0, 0.3)]:
					lowest = minf(lowest, (pose * corner).y)
	_expect(in_range, "60 rolls keep every size and timing inside its range")
	_expect(yaw_signs.size() == 2 and rock_signs.size() == 2, "rolls turn both ways and land on both edges")
	_expect(lowest > -0.001, "no corner ever enters the board, in any roll (%.4f)" % lowest)
	var a: Dictionary = fx.roll_reaction(1, 11)
	var b: Dictionary = fx.roll_reaction(1, 12)
	var differ: float = (fx.reaction_pose(0.1, 1.0, a).origin - fx.reaction_pose(0.1, 1.0, b).origin).length() \
		+ absf(fx.landing_spring(a.land + 0.1, a).x - fx.landing_spring(b.land + 0.1, b).x)
	_expect(differ > 0.01, "two hits of the same strength do not look the same (%.3f)" % differ)
	# The shape of one roll: the fall EASES into the board, then a weakly damped rock and two hops.
	var p0: Dictionary = fx.roll_reaction(1, 5)
	var mid: float = (p0.hang_end + p0.land) * 0.5
	var mid_speed: float = absf(fx.reaction_envelope(mid + 0.01, p0).x - fx.reaction_envelope(mid, p0).x)
	var late_speed: float = absf(fx.reaction_envelope(p0.land - 0.005, p0).x - fx.reaction_envelope(p0.land - 0.015, p0).x)
	_expect(late_speed < mid_speed * 0.5, "the fall slows before it lands (%.3f vs %.3f per 10 ms)" % [late_speed, mid_speed])
	var swings: Array[float] = []
	var t := float(p0.rock_start)
	while t < float(p0.end):
		var roll: float = fx.landing_spring(t, p0).x
		if absf(roll) > 0.05:
			if swings.is_empty() or signf(roll) != signf(swings.back()):
				swings.append(roll)
			elif absf(roll) > absf(swings.back()):
				swings[swings.size() - 1] = roll
		t += 0.005
	var decays := swings.size() >= 2 and absf(swings.back()) < absf(swings[0])
	_expect(swings.size() >= 5 and decays, "it rocks edge to edge %d times as it lands, dying out slowly" % swings.size())
	var hops := 0
	var was_up := false
	t = float(p0.land)
	while t < float(p0.end):
		var up: bool = fx.landing_spring(t, p0).y > 0.05
		if up and not was_up:
			hops += 1
		was_up = up
		t += 0.005
	_expect(hops == 2, "it bounces twice after landing, the second smaller (%d hops)" % hops)
	_expect(fx.landing_spring(float(p0.end) - 0.001, p0).length() < 0.02, "the spring has died out by the end")

	await get_tree().create_timer(1.0).timeout
	_expect(not fx.is_reacting(), "the hit reaction finishes")
	_expect(card.hand_mesh.position.is_equal_approx(Vector3.ZERO)
		and card.hand_mesh.scale.is_equal_approx(Vector3.ONE)
		and card.hand_mesh.rotation.is_equal_approx(Vector3.ZERO),
		"the card returns exactly to its resting pose")
	_expect(fx.face_light() == 0.0, "the face's lighting is back to normal")
	_expect(fx.shadow_strength() == 0.0, "no shadow once the card rests")
	_expect(badge.transform.is_equal_approx(badge_home) and card.power_label.transform.is_equal_approx(label_home)
		and card.power_label.visible, "the cost crystal and power readout are back home")

	# Combat damage keeps the clash presentation and must not trigger this.
	card.clear_damage()
	card.suffer_damage(1000, "", "player")
	await get_tree().create_timer(0.04).timeout
	_expect(not card.damage_fx.is_reacting()
		and card.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"combat damage does not play the effect-damage reaction")
	card.clear_damage()

	# Multi-target effect damage is staggered: the second card must still be at
	# rest when the first one has already popped.
	var second: Card = _play_card(game, field, 12)
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	var ctx = EFFECT_CONTEXT.new(game, card, "test", {}, card, [card, second])
	ctx.damage([card, second], 1000, "multi")
	await get_tree().create_timer(0.05).timeout
	_expect(card.hand_mesh.position.y > 0.005,
		"the first target reacts immediately")
	_expect(second.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"the second target waits for the stagger")
	await get_tree().create_timer(0.24).timeout
	_expect(second.damage_fx.is_reacting() and second.hand_mesh.position.y > 0.005,
		"the second target reacts after the stagger")

	await get_tree().create_timer(0.80).timeout
	# A zone change must normalize any still-running reaction.
	card.suffer_damage(1000, "Ability", "player")
	await get_tree().create_timer(0.04).timeout
	card.enter_zone(Card.Zone.GRAVEYARD)
	await get_tree().process_frame
	_expect(not card.damage_fx.is_reacting()
		and card.hand_mesh.position.is_equal_approx(Vector3.ZERO)
		and card.hand_mesh.rotation.is_equal_approx(Vector3.ZERO),
		"leaving the field normalizes the reaction pose")

	print("[DamageReaction] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageReaction] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
