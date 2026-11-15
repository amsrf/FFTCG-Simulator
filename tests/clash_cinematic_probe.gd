extends Node
## Four clash outcomes through the real Game resolution path.

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

	# FIRST STRIKE, LETHAL: only the attacker has it and its first blow breaks the defender. One one-sided strike,
	# by the attacker, and no reply.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	var strikes: Array = await _watch_strikes(5)
	_expect(_attacker.is_on_field() and not _defender.is_on_field(),
		"scenario 5 (lethal First Strike) keeps the attacker and breaks the defender")
	_expect(strikes == [1], "scenario 5 plays ONE strike, by the attacker (saw %s)" % str(strikes))
	_expect(not _attacker.status_effects.has("first_strike"), "scenario 5 removes its debug First Strike")

	# FIRST STRIKE, NOT LETHAL: the attacker strikes first, the defender survives and answers.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	strikes = await _watch_strikes(6)
	_expect(not _attacker.is_on_field() and _defender.is_on_field(),
		"scenario 6 (First Strike survived) breaks the attacker on the reply")
	_expect(strikes == [1, 2], "scenario 6 plays the attacker's strike, THEN the defender's (saw %s)" % str(strikes))
	_expect(_cinematics() == 0, "the strike cinematics clean up after themselves")
	_expect((_game.get("_clash_suppressed_cards") as Dictionary).is_empty(),
		"break shatter suppression is released after a First Strike clash")

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



## Run a debug scenario and record, in order, the `_strike_by` of every cinematic that plays (0 = exchange,
## 1 = the attacker strikes, 2 = the defender strikes).
func _watch_strikes(scenario: int) -> Array:
	var seen: Dictionary = {}
	var order: Array = []
	var done: Array = [false]
	var run := func() -> void:
		await _game.call("_debug_clash", scenario, false)
		done[0] = true
	run.call()
	for _i in range(3000):
		for node in _game.find_children("*", "Node3D", true, false):
			if node.get_script() != CLASH_SCRIPT:
				continue
			var key: int = node.get_instance_id()
			if not seen.has(key) and not node.is_queued_for_deletion():
				seen[key] = true
				order.append(int(node.get("_strike_by")))
		if done[0]:
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return order
