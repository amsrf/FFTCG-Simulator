extends Node
## Clash outcomes through the real Game resolution path; First Strike shown as one exchange; a dulled card clashing
## straight and dulled again after; an unblocked attack charging the defending player off the screen's edge.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")
const CLASH_SCRIPT := preload("res://scripts/vfx/clash_cinematic.gd")

const SCENARIO_ATTACKER_WINS := 0
const SCENARIO_DEFENDER_WINS := 1
const SCENARIO_BOTH_SURVIVE := 2
const SCENARIO_BOTH_DIE := 3

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _attacker: Card = null
var _defender: Card = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Clash] ok   %s" % what)
	else:
		_fails += 1
		print("[Clash] FAIL %s" % what)


func _boot() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clash")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player_front: Array = _game.get("field").get_front_cards_for("player")
	var opponent_front: Array = _game.get("field").get_front_cards_for("opponent")
	_attacker = player_front[0] if not player_front.is_empty() else null
	_defender = opponent_front[0] if not opponent_front.is_empty() else null


func _cinematics() -> int:
	var count: int = 0
	for node in _game.find_children("*", "Node3D", true, false):
		# By SCRIPT, not name: a second cinematic added while the first is still queued for deletion is auto-renamed
		# to "@Node3D@N".
		if node.get_script() == CLASH_SCRIPT:
			count += 1
	return count


func _run(scenario: int) -> void:
	await _game.call("_debug_clash", scenario, false)
	# Let the cleanup frame run.
	await get_tree().process_frame
	await get_tree().process_frame


func _shards() -> int:
	var count: int = 0
	for node in _game.find_children("CardShards*", "Node3D", true, false):
		count += 1
	return count


func _ready() -> void:
	await _boot()
	_expect(_attacker != null and _defender != null, "the clash ground has both combatants")
	_check_power_choreography()

	await _run(SCENARIO_ATTACKER_WINS)
	_expect(_attacker.is_on_field(), "scenario 0 keeps the attacker")
	_expect(not _defender.is_on_field(), "scenario 0 removes the defender")
	_expect(_attacker.base_power == 8000 and _attacker.power == 8000,
		"scenario 0 does not change Dark Knight's printed power")
	_expect(_shards() > 0, "the defeated clash card shatters after its tumble")
	_expect(_cinematics() == 0, "the cinematic cleans up after itself")
	_expect((_game.get("_clash_suppressed_cards") as Dictionary).is_empty(),
		"break shatter suppression is released")

	# Rebuild the ground for each scenario: defeated cards are already in the Break Zone.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()

	await _run(SCENARIO_DEFENDER_WINS)
	_expect(not _attacker.is_on_field(), "scenario 1 removes the attacker")
	_expect(_defender.is_on_field(), "scenario 1 keeps the defender")

	_game.queue_free()
	await get_tree().process_frame
	await _boot()

	await _run(SCENARIO_BOTH_SURVIVE)
	_expect(_attacker.is_on_field() and _defender.is_on_field(),
		"scenario 2 keeps both combatants")

	_game.queue_free()
	await get_tree().process_frame
	await _boot()

	await _run(SCENARIO_BOTH_DIE)
	_expect(not _attacker.is_on_field() and not _defender.is_on_field(),
		"scenario 3 removes both combatants")

	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _run(4)
	_expect(_attacker.is_on_field() and _defender.is_on_field(),
		"scenario 4 keeps both combatants when they start in different columns")
	_expect(absf(_attacker.global_position.x - _defender.global_position.x) > 1.5,
		"scenario 4 really starts the two cards in different columns")

	# BREAK-ZONE TRIGGERS WAIT FOR THE ANIMATION. Dark Knight 55 (the attacker in scenario 1) has a
	# when_enter_break_from_field trigger. Start the coroutine, and inspect while the cinematic is still on screen.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	var running = _game.call("_debug_clash", 1, false)
	var saw_cinematic: bool = false
	for _i in range(600):
		await get_tree().process_frame
		if _cinematics() > 0:
			saw_cinematic = true
			break
	_expect(saw_cinematic, "scenario 1 actually starts its cinematic")
	_expect(_game.get("stack").stack_length() == 0,
		"no Break Zone effect is on the stack while the clash is animating")
	_expect((_game.get("_deferred_break_zone_triggers") as Array).size() > 0,
		"the defeated Dark Knight's Break Zone trigger is waiting outside the stack")
	for _i in range(1200):
		await get_tree().process_frame
		if _cinematics() == 0:
			break
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_game.get("stack").stack_length() > 0,
		"after the animation the Break Zone trigger is put on the stack")
	_expect((_game.get("_deferred_break_zone_triggers") as Array).is_empty(),
		"and the deferred queue is empty")

	# FIRST STRIKE, LETHAL: only the attacker has it and its first blow breaks the defender. Nobody can act between
	# the two damage steps (15.2.3.3), so it is presented as ONE ordinary exchange showing only who survived.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	var shown: int = await _watch_cinematics(5)
	_expect(_attacker.is_on_field() and not _defender.is_on_field(),
		"scenario 5 (lethal First Strike) keeps the attacker and breaks the defender")
	_expect(shown == 1, "scenario 5 plays ONE exchange (saw %d cinematics)" % shown)
	_expect(not _attacker.status_effects.has("first_strike"), "scenario 5 removes its debug First Strike")

	# FIRST STRIKE, NOT LETHAL: the attacker strikes first, the defender survives and answers.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	shown = await _watch_cinematics(6)
	_expect(not _attacker.is_on_field() and _defender.is_on_field(),
		"scenario 6 (First Strike survived) breaks the attacker on the reply")
	_expect(shown == 1, "scenario 6 plays ONE exchange, not a strike per damage step (saw %d)" % shown)
	_expect(_cinematics() == 0, "the clash cinematics clean up after themselves")
	_expect((_game.get("_clash_suppressed_cards") as Dictionary).is_empty(),
		"break shatter suppression is released after a First Strike clash")

	# A DULLED ATTACKER CLASHES STRAIGHT and is dulled again at the end.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_straighten_and_redull()

	# A REAL ATTACK: the attacker is dulled by execute_card_attack(), blocked, and resolved by the real clash path.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_real_attack_clashes_straight(false)
	# ...and the OPPONENT attacking, the local player blocking.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_real_attack_clashes_straight(true)

	# AN UNBLOCKED ATTACK charges the defending player: a point at the screen's horizontal centre, just off its edge.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_player_strike()

	# THE TOSS (death2 frames 56-109): a defeated card flips toward the camera, lands face up, and only then breaks.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_toss_defeat("toss")
	# THE POP (death frames 90-127): one flip, a hang at the top, dropped back beside its slot.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	await _check_toss_defeat("pop")
	_check_defeat_variety()

	print("[Clash] %d checks | failures: %d" % [_checks, _fails])
	print("[Clash] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


## Power drives the blow: a stronger card draws back further, charges faster, and pushes the meeting point.
func _check_power_choreography() -> void:
	var cinema = preload("res://scenes/game/clash_cinematic.tscn").instantiate()
	var weak: Card = _game.create_card(_defender.id, "opponent")
	var strong: Card = _game.create_card(_attacker.id, "player")
	weak.set_base_power(2000)
	strong.set_base_power(10000)
	var s_weak: float = cinema.strength_for(weak)
	var s_strong: float = cinema.strength_for(strong)
	_expect(s_weak < 0.05 and s_strong > 0.95, "clash strength spans weak_power..strong_power")
	_expect(cinema._windup_scale(s_strong) > cinema._windup_scale(s_weak) * 1.5,
		"a stronger card draws back further")
	_expect(cinema._charge_time(s_strong) < cinema._charge_time(s_weak) * 0.6,
		"a stronger card charges faster")
	weak.free()
	strong.free()
	cinema.free()



## Run a debug scenario and count the clash cinematics that play during it.
func _watch_cinematics(scenario: int) -> int:
	var seen: Dictionary = {}
	var done: Array = [false]
	var run := func() -> void:
		await _game.call("_debug_clash", scenario, false)
		done[0] = true
	run.call()
	for _i in range(3000):
		for node in _game.find_children("*", "Node3D", true, false):
			if node.get_script() == CLASH_SCRIPT and not node.is_queued_for_deletion():
				seen[node.get_instance_id()] = true
		if done[0]:
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return seen.size()


## How far a card leans ON SCREEN: the angle between its bottom-to-top line, projected, and the screen's vertical.
func _screen_tilt(card: Node3D) -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var top: Vector2 = camera.unproject_position(card.global_transform * Vector3(0, 0, -0.3))
	var bottom: Vector2 = camera.unproject_position(card.global_transform * Vector3(0, 0, 0.3))
	var up: Vector2 = top - bottom
	return rad_to_deg(absf(wrapf(atan2(up.x, -up.y), -PI, PI)))


## What the player SEES in a real attack: the attacker dulled by the attack, then straight for the whole clash (only a
## perspective lean of a degree or two), then dulled again once home.
func _check_real_attack_clashes_straight(opponent_attacks: bool) -> void:
	var field = _game.get("field")
	var side: String = "opponent attacks" if opponent_attacks else "player attacks"
	if opponent_attacks:
		var swap: Card = _attacker
		_attacker = _defender
		_defender = swap
	field.reset_attacker()
	field.reset_blocker()
	_attacker.add_status_effect("next_receiving_damage", 1, {"operation": "set", "value": 0})
	_defender.add_status_effect("next_receiving_damage", 1, {"operation": "set", "value": 0})
	field.set_attacker(_attacker)
	field.execute_card_attack()
	await get_tree().create_timer(0.5).timeout
	var dulled_tilt: float = _screen_tilt(_attacker)
	_expect(_attacker.tapped and dulled_tilt > 8.0, "[%s] the attack dulls the attacker (%.1f° on screen)" % [side, dulled_tilt])
	field.blocker_card = _defender
	var done: Array = [false]
	var run := func() -> void:
		await _game.resolve_blocked_clash()
		done[0] = true
	run.call()
	var cinema: Node = null
	for _i in range(600):
		cinema = _live_cinematic()
		if cinema != null and cinema.get("_proxy_a") != null:
			break
		await get_tree().process_frame
	_expect(cinema != null, "[%s] the real attack plays the clash cinematic" % side)
	if cinema == null:
		return
	var straighten_end: float = float(cinema.get("straighten_seconds")) + 0.05
	var started: int = Time.get_ticks_msec()
	var worst_in_clash := 0.0
	var last_tilt := 0.0
	while not done[0] and is_instance_valid(cinema):
		var proxy = cinema.get("_proxy_a")
		if proxy == null or not is_instance_valid(proxy):
			break
		var elapsed: float = (Time.get_ticks_msec() - started) / 1000.0
		last_tilt = _screen_tilt(proxy)
		# Lifted and moving: from the end of the straighten beat until it starts turning back home.
		if elapsed > straighten_end and proxy.global_position.y > _attacker.global_position.y + 0.2:
			worst_in_clash = maxf(worst_in_clash, last_tilt)
		await get_tree().process_frame
	while not done[0]:
		await get_tree().process_frame
	print("[Clash] %s: dulled" % side + " %.1f°, worst lean while clashing %.1f°, at the end %.1f°" % [
		dulled_tilt, worst_in_clash, last_tilt])
	_expect(worst_in_clash < 3.0, "[%s] while clashing the attacker is STRAIGHT on screen (worst %.1f°)" % [side, worst_in_clash])
	_expect(absf(last_tilt - dulled_tilt) < 1.5, "[%s] and dulled again at the end (%.1f° vs %.1f°)" % [side, last_tilt, dulled_tilt])


## The live cinematic, or null.
func half_height_for(card: Card) -> float:
	return 0.30 * card.global_transform.basis.get_scale().x


## From a traced strike: [frames near the player, seconds held there, seconds from first frame to last, seconds from
## first frame to the last one at the player, largest frame-to-frame move while held at the contact]. "At the
## player" = the proxy centre within half a card + 12 cm of it; "held" = within 2 cm of the closest point reached.
func _timed_trace_summary(frames: Array, target: Vector3, half_height: float) -> Array:
	if frames.is_empty():
		return [0, 0.0, 0.0, 0.0, 0.0]
	var closest: float = INF
	for f in frames:
		var d: Vector3 = f[2] - target
		d.y = 0.0
		closest = minf(closest, d.length())
	var still: float = 0.0
	var prev = null
	for f in frames:
		var d2: Vector3 = f[2] - target
		d2.y = 0.0
		if d2.length() < closest + 0.02:
			if prev != null:
				still = maxf(still, (f[2] - prev).length())
			prev = f[2]
		else:
			prev = null
	var first_ms: int = frames[0][3]
	var near_first: int = -1
	var near_last: int = -1
	var near: int = 0
	for f in frames:
		var flat: Vector3 = f[2] - target
		flat.y = 0.0
		if flat.length() < half_height + 0.12:
			near += 1
			if near_first < 0:
				near_first = f[3]
			near_last = f[3]
	var held: float = (near_last - near_first) / 1000.0 if near_first >= 0 else 0.0
	return [near, held, (frames[-1][3] - first_ms) / 1000.0, (maxi(near_last, first_ms) - first_ms) / 1000.0, still]


func _live_cinematic() -> Node:
	for node in _game.find_children("*", "Node3D", true, false):
		if node.get_script() == CLASH_SCRIPT and not node.is_queued_for_deletion():
			return node
	return null


## Every frame of a running cinematic's attacker proxy: [global yaw, height above its start, position].
func _trace_proxy(cinema: Node, proxy_of: Callable, done: Array) -> Array:
	var frames: Array = []
	var start_y: float = NAN
	for _i in range(3000):
		if done[0] or not is_instance_valid(cinema):
			break
		var proxy = proxy_of.call(cinema)
		if proxy != null and is_instance_valid(proxy):
			if is_nan(start_y):
				start_y = proxy.global_position.y
			frames.append([proxy.global_rotation.y, proxy.global_position.y - start_y, proxy.global_position,
				Time.get_ticks_msec()])
		await get_tree().process_frame
	return frames


func _proxy_a_of(cinema: Node) -> Variant:
	return cinema.get("_proxy_a")


func _first_striker(cinema: Node) -> Variant:
	var list: Array = cinema.get("_strikers")
	return list[0].proxy if not list.is_empty() else null


## The largest turn about the board's up axis away from `straight` over a trace (the wind-up lean is about the card's
## own right axis, so it does not count).
func _max_turn(frames: Array, straight: float) -> float:
	var most := 0.0
	for f in frames:
		most = maxf(most, _yaw_gap(f[0], straight))
	return most


func _yaw_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## The tapped attacker (scenario 2: both survive) turns straight BEFORE it rises, and is dull again at the end.
func _check_straighten_and_redull() -> void:
	_attacker.tap()
	await get_tree().create_timer(0.4).timeout
	var dull_yaw: float = _attacker.global_rotation.y
	var straight_yaw: float = dull_yaw - deg_to_rad(_attacker.tap_angle)
	var dull_transform: Transform3D = _attacker.global_transform
	var done: Array = [false]
	var run := func() -> void:
		await _game.call("_debug_clash", SCENARIO_BOTH_SURVIVE, false)
		done[0] = true
	run.call()
	var cinema: Node = null
	for _i in range(600):
		cinema = _live_cinematic()
		if cinema != null and cinema.get("_proxy_a") != null:
			break
		await get_tree().process_frame
	_expect(cinema != null, "the dulled clash starts its cinematic")
	if cinema == null:
		return
	var frames: Array = await _trace_proxy(cinema, _proxy_a_of, done)
	while not done[0]:
		await get_tree().process_frame
	var straight_on_ground: bool = false
	for f in frames:
		if f[1] < 0.01 and _yaw_gap(f[0], straight_yaw) < deg_to_rad(1.0):
			straight_on_ground = true
			break
	_expect(straight_on_ground, "the dulled attacker turns straight before it rises (%d frames)" % frames.size())
	_expect(_max_turn(frames, straight_yaw) <= absf(deg_to_rad(_attacker.tap_angle)) + deg_to_rad(1.0),
		"it clashes STRAIGHT: never turned further than its own dull tilt (%.1f° at most)" % rad_to_deg(_max_turn(frames, straight_yaw)))
	_expect(not frames.is_empty() and _yaw_gap(frames[-1][0], dull_yaw) < deg_to_rad(1.0),
		"and it is dulled again when the cinematic ends (%.1f° off)" % (
			rad_to_deg(_yaw_gap(frames[-1][0], dull_yaw)) if not frames.is_empty() else 999.0))
	await get_tree().process_frame
	_expect(_attacker.visible and _attacker.global_transform.is_equal_approx(dull_transform),
		"the real card is shown again exactly where it rested, dulled")


## Unblocked: the attacker's top edge meets a point at the screen's horizontal centre a few pixels above its top edge
## (the opponent), then the card goes home, dulled, and the proxy is gone.
func _check_player_strike() -> void:
	var field = _game.get("field")
	field.reset_attacker()
	field.reset_blocker()
	_attacker.tap()
	await get_tree().create_timer(0.4).timeout
	var dull_transform: Transform3D = _attacker.global_transform
	var dull_yaw: float = _attacker.global_rotation.y
	field.attacker_card = _attacker
	var camera: Camera3D = get_viewport().get_camera_3d()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var done: Array = [false]
	var handed: Array = [-1]
	var run := func() -> void:
		var t0: int = Time.get_ticks_msec()
		await _game.call("_present_unblocked_attack")
		handed[0] = Time.get_ticks_msec() - t0
		# The call returns at the HAND-OFF (the glide home has begun); the strike itself ends when its node is gone.
		while _live_cinematic() != null:
			await get_tree().process_frame
		done[0] = true
	run.call()
	var cinema: Node = null
	for _i in range(600):
		cinema = _live_cinematic()
		if cinema != null and not (cinema.get("_strikers") as Array).is_empty():
			break
		await get_tree().process_frame
	_expect(cinema != null, "an unblocked attack plays a strike cinematic")
	if cinema == null:
		return
	var top: Vector3 = cinema.player_point(false, 1.0)
	var bottom: Vector3 = cinema.player_point(true, 1.0)
	var top_px: Vector2 = camera.unproject_position(top)
	var bottom_px: Vector2 = camera.unproject_position(bottom)
	var off: float = float(cinema.get("player_offscreen_pixels"))
	_expect(absf(top_px.x - view.x * 0.5) < 1.0 and absf(top_px.y + off) < 1.0,
		"the opponent is at the horizontal centre, %d px above the screen (%s of %s)" % [int(off), str(top_px), str(view)])
	_expect(absf(bottom_px.x - view.x * 0.5) < 1.0 and absf(bottom_px.y - view.y - off) < 1.0,
		"the local player is at the horizontal centre, %d px below the screen (%s)" % [int(off), str(bottom_px)])
	var target: Vector3 = cinema.player_point(false, _attacker.global_position.y + float(cinema.get("lift_height")))
	var straight_yaw: float = dull_yaw - deg_to_rad(_attacker.tap_angle)
	var stun_cfg: float = float(cinema.get("hitstun_seconds"))
	var glide_cfg: float = float(cinema.get("glide_seconds"))
	var waves: Array = [0]
	var wave_watch := func() -> void:
		while not done[0] and is_instance_valid(cinema):
			for child in cinema.get_children():
				if child is MeshInstance3D and child.material_override is ShaderMaterial \
						and (child.material_override as ShaderMaterial).shader == cinema.EDGE_WAVE_SHADER:
					waves[0] = maxi(waves[0], 1)
			await get_tree().process_frame
	wave_watch.call()
	var frames: Array = await _trace_proxy(cinema, _first_striker, done)
	while not done[0]:
		await get_tree().process_frame
	# HIT STUN: frames from the first one within 6 cm of the contact point to the last one within 12 cm (it shudders).
	var t_frames: Array = _timed_trace_summary(frames, target, half_height_for(_attacker))
	_expect(waves[0] > 0, "the hit spreads a wide shockwave along the player's edge")
	_expect(t_frames[4] < 0.005,
		"the striker holds STILL in hit stun, no tremble (moved %.4f m frame to frame at most)" % t_frames[4])
	_expect(t_frames[1] >= stun_cfg * 0.8,
		"the striker is held at the player in hit stun (%.2f s, configured %.2f s × strength)" % [t_frames[1], stun_cfg])
	_expect(handed[0] >= 0 and handed[0] < t_frames[2] * 1000.0,
		"the damage is handed off while the card is still gliding home (%d ms of %d ms)" % [handed[0], int(t_frames[2] * 1000.0)])
	_expect(t_frames[2] - t_frames[3] >= glide_cfg * 0.8,
		"the return from the player is slow (%.2f s after leaving it, glide %.2f s)" % [t_frames[2] - t_frames[3], glide_cfg])
	var closest: float = INF
	for f in frames:
		var flat: Vector3 = f[2] - target
		flat.y = 0.0
		closest = minf(closest, flat.length())
	var half_height: float = 0.30 * _attacker.global_transform.basis.get_scale().x
	# The bug this guards: tweening Euler angles across ±180° spun the card a whole turn on its way to the player.
	_expect(_max_turn(frames, straight_yaw) <= absf(deg_to_rad(_attacker.tap_angle)) + deg_to_rad(1.0),
		"the striker stays STRAIGHT and never spins (%.1f° from straight at most)" % rad_to_deg(_max_turn(frames, straight_yaw)))
	_expect(absf(closest - half_height) < 0.10,
		"the attacker's top edge reaches the player (centre %.2f m from it, half a card is %.2f)" % [closest, half_height])
	_expect(not frames.is_empty() and _yaw_gap(frames[-1][0], dull_yaw) < deg_to_rad(1.0),
		"the striker is dulled again at the end")
	await get_tree().process_frame
	_expect(_attacker.visible and _attacker.global_transform.is_equal_approx(dull_transform),
		"the real attacker is shown again, home and dulled")
	_expect(_cinematics() == 0, "the player strike cleans up after itself")


## The toss defeat, forced: the loser climbs toward the camera (bigger on screen), shows its BACK on the way, lands on
## the wood FACE UP near its slot, and its burst starts only after it has landed. The winner's return home never dips
## under the wood (a back-ease overshoot once sank it there for a few frames: black slab, no art).
func _check_toss_defeat(style: String) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var home: Vector3 = _defender.global_position
	var winner_home_y: float = _attacker.global_position.y
	CLASH_SCRIPT.next_defeat_style = style
	var done: Array = [false]
	var run := func() -> void:
		await _game.call("_debug_clash", SCENARIO_ATTACKER_WINS, false)
		done[0] = true
	run.call()
	var cinema: Node = null
	for _i in range(600):
		cinema = _live_cinematic()
		if cinema != null and cinema.get("_proxy_b") != null:
			break
		await get_tree().process_frame
	_expect(cinema != null, "the %s clash starts its cinematic" % style)
	if cinema == null:
		return
	var loser: Card = cinema.get("_proxy_b")
	var winner: Card = cinema.get("_proxy_a")
	var size_at := func(card: Card) -> float:
		var depth: float = (card.global_position - camera.global_position).dot(-camera.global_basis.z)
		return card.global_basis.get_scale().x / maxf(depth, 0.01)
	var rest_size: float = size_at.call(loser)
	var biggest: float = rest_size
	var showed_back := false
	var winner_low: float = INF
	var landed_at: Variant = null
	var landed_up: float = -2.0
	var burst_before_landing := false
	var tossed := false
	# THE LOSER STAYS OVER ITS OWN SIDE (death2: thrown up and back, it lands by its own slot). Every loser was once
	# thrown "toward the camera", which sent the OPPONENT's card flying over the player's board.
	var mid_ground: Vector3 = (home + _attacker.global_position) * 0.5
	var own_side: Vector3 = Vector3(home.x - mid_ground.x, 0.0, home.z - mid_ground.z).normalized()
	var deepest_cross: float = 0.0
	for _i in range(900):
		if done[0]:
			break
		if is_instance_valid(winner):
			winner_low = minf(winner_low, winner.global_position.y)
		if is_instance_valid(loser) and loser.visible:
			var state: Dictionary = cinema.get("_defeated").get(loser, {})
			if state.get("style", "") == style:
				tossed = true
				biggest = maxf(biggest, size_at.call(loser))
				var off: Vector3 = loser.global_position - mid_ground
				deepest_cross = maxf(deepest_cross, -Vector3(off.x, 0.0, off.z).dot(own_side))
				var to_cam: Vector3 = (camera.global_position - loser.global_position).normalized()
				if loser.global_basis.y.normalized().dot(to_cam) < -0.3:
					showed_back = true
				if bool(state.get("landed", false)) and landed_at == null:
					landed_at = loser.global_position
					landed_up = loser.global_basis.y.normalized().dot(Vector3.UP)
				if landed_at == null and _shards() > 0:
					burst_before_landing = true
		await get_tree().process_frame
	_expect(tossed, "the forced defeat is the %s" % style)
	_expect(biggest > rest_size * 1.4, "%s: it climbs toward the camera: %.2fx its resting size on screen" % [style, biggest / rest_size])
	_expect(showed_back, "it flips over: its BACK faces the camera on the way")
	_expect(deepest_cross < 0.05, "%s: it never crosses to the WINNER's side of the board (%.2f m past the middle)" % [
		style, deepest_cross])
	_expect(landed_at != null and landed_up > 0.95, "it lands FACE UP (up . normal %.2f)" % landed_up)
	_expect(landed_at != null and absf((landed_at as Vector3).y - home.y) < 0.01
		and Vector2(landed_at.x - home.x, landed_at.z - home.z).length() < 1.0,
		"on the wood near its slot (%s vs slot %s)" % [str(landed_at), str(home)])
	if style == "pop":
		_expect(landed_at != null and Vector2(landed_at.x - home.x, landed_at.z - home.z).length() < 0.35,
			"the pop drops back BESIDE its slot (%.2f m off)" % (Vector2(landed_at.x - home.x, landed_at.z - home.z).length()
				if landed_at != null else 99.0))
	_expect(not burst_before_landing and _shards() > 0, "and breaks only once it has landed")
	_expect(winner_low >= winner_home_y - 0.002,
		"the winner never dips under the wood on its way home (lowest %.3f, slot %.3f)" % [winner_low, winner_home_y])


## A death is never the same one twice in a row, and every style in the list comes up.
func _check_defeat_variety() -> void:
	var cinema = CLASH_SCRIPT.new()
	cinema.set("random_seed", 7)
	var seen: Dictionary = {}
	var repeats: int = 0
	var last: String = ""
	cinema.get("_rng").seed = 7
	for _i in range(60):
		var style: String = cinema.call("_pick_defeat_style")
		if style == last:
			repeats += 1
		CLASH_SCRIPT._last_defeat_style = style
		last = style
		seen[style] = true
	cinema.free()
	CLASH_SCRIPT._last_defeat_style = ""
	_expect(repeats == 0 and seen.size() == 3,
		"deaths vary: %d styles over 60 picks, %d back-to-back repeats" % [seen.size(), repeats])
