extends Node

const CARD_EDGE_SCRIPT := preload("res://scripts/cards/card_edge.gd")
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


## How far a card face leans ON SCREEN: its bottom-to-top line, projected, against the screen's vertical (degrees).
func _screen_tilt(node: Node3D) -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var top: Vector2 = camera.unproject_position(node.global_transform * Vector3(0, 0, -0.3))
	var bottom: Vector2 = camera.unproject_position(node.global_transform * Vector3(0, 0, 0.3))
	var up: Vector2 = top - bottom
	return rad_to_deg(absf(wrapf(atan2(up.x, -up.y), -PI, PI)))


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
	_expect(near_rise > 0.10 and near_rise < 0.32, "the card snaps up off the board: a little jump (bottom edge +%.2f m)" % near_rise)
	var tip: float = rad_to_deg(asin(clampf((far_rise - near_rise) / (0.6 * card.global_basis.get_scale().y), -1.0, 1.0)))
	_expect(tip > 15.0 and tip < 28.0, "it tips toward the camera about its bottom edge (%.1f deg)" % tip)
	var toward: Vector3 = card.get_viewport().get_camera_3d().global_position - card.global_position
	toward.y = 0.0
	_expect((far_at.call() - rest_far).dot(toward) > 0.0, "the far edge swings toward the camera")
	_expect(absf(card.hand_mesh.scale.x - 1.0) < 0.001, "it does not scale")
	# SHADING: turned toward the light, the face is brighter (the wolf: ~+15%).
	var lit: float = fx.face_light()
	_expect(lit > 0.1 and lit < 0.25, "the tipped face is lit brighter (face_light %+.3f)" % lit)
	# The edge's REST is its thickness (its y scale), so it rides as face pose * that.
	var edge_rest := Transform3D(Basis.from_scale(Vector3(1.0, CARD_EDGE_SCRIPT.thickness_for(true), 1.0)), Vector3.ZERO)
	_expect(edge.transform.is_equal_approx(card.hand_mesh.transform * edge_rest), "the thickness edge rides with the face")
	_expect(badge.transform.is_equal_approx(card.hand_mesh.transform * badge_home), "the cost crystal rides with the face")
	_expect(card.power_label.transform.is_equal_approx(card.hand_mesh.transform * label_home), "the power readout rides with the face")
	_expect(fx.shadow_strength() > 0.3, "the lifted card casts a shadow on the board")

	# Every hit is rolled. Sweep many rolls (every tier, both seats): within range, never into the board, and different.
	var lowest := INF
	var in_range := true
	var yaw_signs := {}
	for seed_value in range(60):
		var tier: int = seed_value % 4
		var p: Dictionary = fx.roll_reaction(tier, seed_value)
		in_range = in_range and p.lift >= fx.REACTION_LIFT[tier] * 0.85 - 0.0001 and p.lift <= fx.REACTION_LIFT[tier] * 1.15 + 0.0001 \
			and absf(p.pitch - fx.REACTION_PITCH_DEG[tier]) <= 3.0001 and p.end > 1.0 and p.end < 2.5
		yaw_signs[signf(p.yaw)] = true
		for far_sign in [-1.0, 1.0]:
			var t := 0.0
			while t <= float(p.end):
				var pose: Transform3D = fx.reaction_pose(t, far_sign, p)
				for corner in [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(-0.2145, 0, 0.3), Vector3(0.2145, 0, 0.3)]:
					lowest = minf(lowest, (pose * corner).y)
				t += 0.01
	_expect(in_range, "60 rolls keep every size and timing inside its range")
	_expect(yaw_signs.size() == 2, "rolls turn both ways")
	_expect(lowest > -0.001, "no corner ever enters the board, in any roll, through the whole return (%.4f)" % lowest)
	var a: Dictionary = fx.roll_reaction(1, 11)
	var b: Dictionary = fx.roll_reaction(1, 12)
	var differ: float = (fx.reaction_pose(0.3, 1.0, a).origin - fx.reaction_pose(0.3, 1.0, b).origin).length() \
		+ absf(fx.reaction_spring(0.7, a) - fx.reaction_spring(0.7, b))
	_expect(differ > 0.01, "two hits of the same strength do not look the same (%.3f)" % differ)
	# The shape of one roll: a fast snap, then a SLOW return on a WEAKLY damped spring, with no snap back.
	var p0: Dictionary = fx.roll_reaction(1, 5)
	_expect(fx.reaction_spring(float(p0.rise), p0) > 0.99 and float(p0.rise) <= 0.05,
		"the jump is a snap: full height in %.2f s" % float(p0.rise))
	var back_down := -1.0
	var swings: Array[float] = []
	var biggest_step := 0.0
	var t0 := float(p0.rise)
	while t0 < float(p0.end):
		var value: float = fx.reaction_spring(t0, p0)
		if back_down < 0.0 and value <= 0.0:
			back_down = t0 - float(p0.rise)
		if absf(value) > 0.03:
			if swings.is_empty() or signf(value) != signf(swings.back()):
				swings.append(value)
			elif absf(value) > absf(swings.back()):
				swings[swings.size() - 1] = value
		biggest_step = maxf(biggest_step, absf(fx.reaction_spring(t0 + 0.01, p0) - value))
		t0 += 0.005
	_expect(back_down > 0.2, "the return is slow: back on the board %.2f s after the jump" % back_down)
	var decays := swings.size() >= 3
	for i in range(1, swings.size()):
		decays = decays and absf(swings[i]) < absf(swings[i - 1])
	_expect(decays, "weak damping: it swings past rest and back %d times, each smaller (%s)" % [
		swings.size() - 1, str(swings.map(func(v): return snappedf(v, 0.01)))])
	_expect(biggest_step < 0.08, "after the snap nothing jumps: the largest change in 10 ms is %.3f of the jump" % biggest_step)
	_expect(absf(fx.reaction_spring(float(p0.end) - 0.001, p0)) < 0.001, "the spring is exactly at rest when it ends")

	await get_tree().create_timer(float(fx.reaction_params().end) + 0.2).timeout
	_expect(not fx.is_reacting(), "the hit reaction finishes")
	_expect(card.hand_mesh.position.is_equal_approx(Vector3.ZERO)
		and card.hand_mesh.scale.is_equal_approx(Vector3.ONE)
		and card.hand_mesh.rotation.is_equal_approx(Vector3.ZERO),
		"the card returns exactly to its resting pose")
	_expect(fx.face_light() == 0.0, "the face's lighting is back to normal")
	_expect(fx.shadow_strength() == 0.0, "no shadow once the card rests")
	_expect(badge.transform.is_equal_approx(badge_home) and card.power_label.transform.is_equal_approx(label_home)
		and card.power_label.visible, "the cost crystal and power readout are back home")

	# A DULLED CARD IS HIT STRAIGHT. Dulled the real way (it attacks), then hit by an ability: on screen the face is
	# upright while it is knocked loose (only the rolled turn of a few degrees), and dulled again when it settles.
	field.set_attacker(card)
	field.execute_card_attack()
	await get_tree().create_timer(0.5).timeout
	var dulled_tilt: float = _screen_tilt(card.hand_mesh)
	_expect(card.tapped and dulled_tilt > 8.0, "attacking dulls the card (%.1f° on screen)" % dulled_tilt)
	card.suffer_damage(3000, "Ability", "opponent")
	var hit_start: int = Time.get_ticks_msec()
	var worst_hit := 0.0
	var settled_tilt := 0.0
	await get_tree().process_frame
	var end_s: float = float(fx.reaction_params().end)
	while fx.is_reacting():
		var at: float = (Time.get_ticks_msec() - hit_start) / 1000.0
		if at > 0.06 and at < end_s - fx.UNTILT_RETURN - 0.05:
			worst_hit = maxf(worst_hit, _screen_tilt(card.hand_mesh))
		await get_tree().process_frame
	settled_tilt = _screen_tilt(card.hand_mesh)
	print("[DamageReaction] dulled hit: dulled %.1f°, worst while hit %.1f°, settled %.1f°" % [dulled_tilt, worst_hit, settled_tilt])
	_expect(worst_hit < 7.0, "while it is knocked loose the dulled card is STRAIGHT on screen (worst %.1f°)" % worst_hit)
	_expect(absf(settled_tilt - dulled_tilt) < 1.0, "and it settles dulled again (%.1f° vs %.1f°)" % [settled_tilt, dulled_tilt])
	field.reset_attacker()
	card.untap()
	card.clear_damage()
	await get_tree().create_timer(0.4).timeout

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
	# The SOURCE is a Lightning card (Kain 127): an element whose cue does not take the recoil over. Fire, Ice, Wind and
	# Earth own it (VfxPreset.owns_damage_reaction) and play it at their own impact, so the stagger is not theirs.
	var lightning: Card = _play_card(game, field, 127)
	await get_tree().process_frame
	var ctx = EFFECT_CONTEXT.new(game, lightning, "test", {}, lightning, [card, second])
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
