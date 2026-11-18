extends Node
## A CARD STILL FLYING ONTO THE STACK MUST NOT RESOLVE. Reported: with the pass mode on React, a Summon cast by the
## local player resolved mid-flight. React auto-passes the caster's own window (their object on top), the mock/AI
## opponent passes after its think time, and neither waits for the presentation, so both passes were in before the
## card had landed. Stack.resolve_top_effect() now waits for every entry (Stack.cards_still_entering()).
##
## Real path: a Summon cast from hand in React mode against a passing opponent; every frame we note whether the stack
## is resolving while something is still entering it.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const VALEFOR := 62   # wind Summon, cost 5, no target

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[StackEntry] %s %s" % ["ok  " if ok else "FAIL", what])

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [VALEFOR],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
		"pass_mode": "react",
	})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for i in 30:
		await get_tree().process_frame
	var stack = game.get("stack")
	var hand = game.get("hand")
	var assistant = game.get("assistant")
	_expect(game.get("pass_mode") == "react", "the pass mode is React")
	var summon: Card = null
	for c in hand.cards:
		if c.id == VALEFOR:
			summon = c
	_expect(summon != null, "Valefor is in hand")
	if summon == null:
		return _finish(game)
	# Cast it as the player would: charge it, pay, confirm.
	_expect(hand.charge(summon), "the Summon can be cast")
	await get_tree().process_frame
	assistant.call("charge", 5, "風")
	assistant.call("on_charge_complete")

	# Watch until it has resolved (it leaves the stack) or 8 s pass.
	var resolved_in_flight := false
	var saw_entering := false
	var saw_resolving := false
	var t := 0.0
	while t < 8.0:
		var entering: bool = stack.cards_still_entering()
		saw_entering = saw_entering or entering
		var resolving = stack.get("resolving_card")
		if resolving != null:
			saw_resolving = true
			if entering:
				resolved_in_flight = true
		if saw_resolving and resolving == null and stack.stack_length() == 0:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	_expect(saw_entering, "the Summon flew onto the stack (it was seen entering)")
	_expect(saw_resolving, "and it resolved (React passed for the player, the opponent passed) within %.1f s" % t)
	_expect(not resolved_in_flight, "it did NOT start resolving while a card was still entering the stack")
	_finish(game)

func _finish(game: Node) -> void:
	print("[StackEntry] %d checks | failures: %d" % [_checks, _fails])
	print("[StackEntry] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
