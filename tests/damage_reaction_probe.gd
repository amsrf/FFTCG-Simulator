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
	# The first hit is pinned to the TIP style (the far edge toward the camera); the others are swept below.
	fx.next_style = "tip"
	card.suffer_damage(5000, "Ability", "player")
	# SNAP: up within a couple of frames (reference frames 62 -> 63).
	await get_tree().create_timer(0.08).timeout
	_expect(fx.is_reacting(), "effect damage starts a hit reaction")
	var near_rise: float = near_at.call().y - rest_near.y
	var far_rise: float = far_at.call().y - rest_far.y
	_expect(near_rise > 0.10 and near_rise < 0.32, "the card snaps up off the board: a little jump (bottom edge +%.2f m)" % near_rise)
	var tip: float = rad_to_deg(asin(clampf((far_rise - near_rise) / (0.6 * card.global_basis.get_scale().y), -1.0, 1.0)))
	_expect(tip > 27.0 and tip < 42.0, "it PITCHES hard toward the camera about its bottom edge (%.1f deg)" % tip)
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
	var styles_seen := {}
	var lowest_style := ""
	var by_name := {}
	for style in fx.STYLES:
		by_name[style.name] = style
	for seed_value in range(120):
		var tier: int = seed_value % 4
		var p: Dictionary = fx.roll_reaction(tier, seed_value)
		var style: Dictionary = by_name[p.style]
		styles_seen[p.style] = true
		var base_lift: float = fx.REACTION_LIFT[tier] * float(style.lift)
		in_range = in_range and p.lift >= base_lift * 0.85 - 0.0001 and p.lift <= base_lift * 1.15 + 0.0001 \
			and absf(p.pitch - fx.REACTION_PITCH_DEG[tier] * float(style.tilt)) <= 3.0001 * float(style.tilt) \
			and p.end > 0.7 and p.end < 2.0 and (style.axis as Array).has(p.axis_deg)
		yaw_signs[signf(p.yaw)] = true
		for far_sign in [-1.0, 1.0]:
			var t := 0.0
			while t <= float(p.end):
				var pose: Transform3D = fx.reaction_pose(t, far_sign, p)
				for corner in [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(-0.2145, 0, 0.3), Vector3(0.2145, 0, 0.3)]:
					if (pose * corner).y < lowest:
						lowest = (pose * corner).y
						lowest_style = p.style
				t += 0.01
	_expect(in_range, "120 rolls keep every size and timing inside their style's range")
	_expect(styles_seen.size() == fx.STYLES.size(), "every hit style turns up (%s)" % str(styles_seen.keys()))
	_expect(yaw_signs.size() == 2, "rolls turn both ways")
	_expect(lowest > -0.001, "no corner ever enters the board, in any roll of any style, through the whole return (%.4f, %s)"
		% [lowest, lowest_style])
	# Styles are different MOTIONS: at the top of the jump each tips the face a different way (or turns it).
	var tops := {}
	for style in fx.STYLES:
		var axes: Array = style.axis
		var q: Dictionary = fx.roll_reaction(2, 7, [], style.name)
		var top: Transform3D = fx.reaction_pose(float(q.rise), 1.0, q)
		tops[style.name] = [top.basis * Vector3.UP, top.basis * Vector3.FORWARD, top.origin.y]
	var closest := INF
	var closest_pair := ""
	var names: Array = tops.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a_top: Array = tops[names[i]]
			var b_top: Array = tops[names[j]]
			var apart: float = (a_top[0] - b_top[0]).length() + (a_top[1] - b_top[1]).length() + absf(a_top[2] - b_top[2])
			if apart < closest:
				closest = apart
				closest_pair = "%s/%s" % [names[i], names[j]]
	_expect(closest > 0.05, "every style's top pose differs from every other's (closest %s: %.3f)" % [closest_pair, closest])
	# Never the same style twice in a row: on one card, and across the board.
	var repeats := 0
	var last := ""
	for seed_value in range(50):
		var r: Dictionary = fx.roll_reaction(1, 1000 + seed_value, [last])
		if r.style == last:
			repeats += 1
		last = r.style
	_expect(repeats == 0, "a roll never repeats the style it is told to avoid (%d repeats in 50)" % repeats)
	var a: Dictionary = fx.roll_reaction(1, 11)
	var b: Dictionary = fx.roll_reaction(1, 12)
	var pose_a: Transform3D = fx.reaction_pose(0.3, 1.0, a)
	var pose_b: Transform3D = fx.reaction_pose(0.3, 1.0, b)
	var differ: float = (pose_a.origin - pose_b.origin).length() + (pose_a.basis * Vector3.UP - pose_b.basis * Vector3.UP).length() \
		+ absf(fx.reaction_spring(0.7, a) - fx.reaction_spring(0.7, b))
	_expect(differ > 0.01, "two hits of the same strength do not look the same (%.3f)" % differ)
	# The shape of one roll: a fast snap, a hang and a SLOW fall, then it settles on its bottom edge and never jumps again.
	var p0: Dictionary = fx.roll_reaction(1, 5, [], "tip")
	_expect(fx.reaction_spring(float(p0.rise), p0) > 0.99 and float(p0.rise) <= 0.05,
		"the jump is a snap: full height in %.2f s" % float(p0.rise))
	var landed_at: float = float(p0.rise) + float(p0.fall)
	_expect(float(p0.fall) > 0.35 and float(p0.fall) < 0.6, "the fall back is slow: on the board %.2f s after the top (0.35-0.6)" % float(p0.fall))
	var hang: float = fx.reaction_spring(float(p0.rise) + 0.1 * float(p0.fall), p0)
	_expect(hang > 0.95, "it HANGS at the top before falling (%.2f of the jump after a tenth of the fall)" % hang)
	var peaks: Array[float] = []
	var biggest_step := 0.0
	var below := 0.0
	var relifted := 0.0
	var bottom_edge_up := 0.0
	var rising := false
	var prev: float = fx.reaction_spring(landed_at, p0)
	var t0 := float(p0.rise)
	while t0 < float(p0.end):
		var value: float = fx.reaction_spring(t0, p0)
		below = minf(below, value)
		biggest_step = maxf(biggest_step, absf(fx.reaction_spring(t0 + 0.01, p0) - value))
		if t0 > landed_at:
			var pose: Transform3D = fx.reaction_pose(t0, 1.0, p0)
			relifted = maxf(relifted, fx.reaction_lift(t0, p0))
			bottom_edge_up = maxf(bottom_edge_up, maxf((pose * Vector3(-0.2145, 0, 0.3)).y, (pose * Vector3(0.2145, 0, 0.3)).y))
			if value < prev and rising:
				peaks.append(prev)
			rising = value > prev
			prev = value
		t0 += 0.002
	_expect(below >= 0.0, "it never tips the other way (lowest %.3f)" % below)
	_expect(relifted < 0.0001 and bottom_edge_up < 0.001,
		"after landing it never leaves the board again: lift %.4f, bottom edge %.4f m" % [relifted, bottom_edge_up])
	var settles := peaks.size() >= 2 and peaks[0] > 0.06 and peaks[0] < 0.25
	for i in range(1, peaks.size()):
		settles = settles and peaks[i] < peaks[i - 1] * 0.6
	_expect(settles, "it settles on a damped bounce on its bottom edge, each kick smaller (%s of the jump's tip)"
		% str(peaks.map(func(v): return snappedf(v, 0.01))))
	_expect(fx.reaction_wobble(landed_at + 0.05, p0) == 0.0, "the tip style lands square (no side wobble)")
	# THE WOBBLE (~/Desktop/Clips/damage 83-90): a wobbling style comes down on ONE long edge, then rocks onto the other,
	# back, ..., each rock smaller, and never pushes an edge into the board.
	var pw: Dictionary = fx.roll_reaction(1, 9, [], "corner")
	var landed_w: float = float(pw.rise) + float(pw.fall)
	var side_gap := func(at: float) -> float:
		var pose: Transform3D = fx.reaction_pose(at, 1.0, pw)
		return (pose * Vector3(0.2145, 0, 0)).y - (pose * Vector3(-0.2145, 0, 0)).y
	var at_touch: Transform3D = fx.reaction_pose(landed_w, 1.0, pw)
	var left_y: float = (at_touch * Vector3(-0.2145, 0, 0)).y
	var right_y: float = (at_touch * Vector3(0.2145, 0, 0)).y
	_expect(minf(left_y, right_y) < 0.001 and absf(left_y - right_y) > 0.02,
		"it touches down on ONE long edge first (edge heights %.3f / %.3f m)" % [left_y, right_y])
	var rocks: Array[float] = []
	var last_sign: float = signf(side_gap.call(landed_w))
	var extreme: float = absf(side_gap.call(landed_w))
	var tw: float = landed_w
	while tw < float(pw.end):
		var gap: float = side_gap.call(tw)
		if signf(gap) != last_sign and absf(gap) > 0.001:
			rocks.append(extreme)
			extreme = 0.0
			last_sign = signf(gap)
		extreme = maxf(extreme, absf(gap))
		tw += 0.002
	rocks.append(extreme)
	var visible_rocks: int = rocks.filter(func(v): return v > 0.012).size()
	_expect(rocks[0] > 0.07 and visible_rocks >= 3 and visible_rocks <= 4,
		"a BIG first lean (%.3f m of edge lift) and 3-4 rocks you can see (%d over 1.2 cm)" % [rocks[0], visible_rocks])
	var rock_seconds: float = PI / float(pw.wobble_w)
	_expect(rock_seconds > 0.12 and rock_seconds < 0.2, "each rock is slow: %.2f s from one edge to the other" % rock_seconds)
	var rocking := rocks.size() >= 3
	for i in range(1, rocks.size()):
		rocking = rocking and rocks[i] < rocks[i - 1]
	_expect(rocking, "then rocks from edge to edge, each rock smaller (%s m of edge lift)"
		% str(rocks.map(func(v): return snappedf(v, 0.001))))
	_expect(biggest_step < 0.08, "after the snap nothing jumps: the largest change in 10 ms is %.3f of the jump" % biggest_step)
	_expect(absf(fx.reaction_spring(float(p0.end) - 0.001, p0)) < 0.001, "it is exactly at rest when it ends")

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
	fx.next_style = "tip"   # the twist style turns more than this check's few degrees on purpose
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
