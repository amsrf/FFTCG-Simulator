extends Node
## AI PARTY probe (slice 3) — the AI declares a PARTY, which is what makes the human's distribution window reachable
## in normal play.
##
## Checks the agent's answer rather than the whole turn: decide_attackers() is the seam Game awaits, so a list of two
## same-element Forwards from it is exactly what gets applied to the field.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[AIParty] ok   %s" % what)
	else:
		_fails += 1
		print("[AIParty] FAIL %s" % what)


func _same_element(a: Card, b: Card) -> bool:
	var game = _game
	var field = game.get("field")
	return field.element_set(a) == field.element_set(b)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = _game.get("field")

	var forwards: Array = field.get_front_cards_for("opponent")
	print("[AIParty] AI Forwards: %s" % str(forwards.map(func(c): return "%s(%s)" % [c.card_name, str(field.element_set(c))])))
	_expect(forwards.size() >= 2, "the AI board has at least two Forwards (%d)" % forwards.size())

	# At least two of them must share an element, or no party is possible.
	var pair_found: bool = false
	for i in range(forwards.size()):
		for j in range(i + 1, forwards.size()):
			if _same_element(forwards[i], forwards[j]):
				pair_found = true
	_expect(pair_found, "and two of them share an element, so a party is legal")

	# Two untapped Forwards must be actionable even if one has summoning sickness on a fresh board.
	for f in forwards:
		f.status_effects.clear()
		f.untap()

	var ai = load("res://scripts/agents/ai_agent.gd").new()
	ai.bind(_game)
	var picked: Array = await ai.decide_attackers(2)

	print("[AIParty] AI declared %d attacker(s): %s" % [picked.size(), str(picked.map(func(c): return c.card_name))])
	_expect(picked.size() >= 2, "the AI declares a PARTY when it can (%d members)" % picked.size())
	if picked.size() >= 2:
		var all_same: bool = true
		var all_can_attack: bool = true
		for c in picked:
			if not _same_element(picked[0], c):
				all_same = false
			if not c.can_attack():
				all_can_attack = false
		_expect(all_same, "every member shares the same element")
		_expect(all_can_attack, "and every member can attack")

	# With the pair tapped, there is no party left to declare.
	for f in forwards:
		f.tap()
	var none: Array = await ai.decide_attackers(2)
	_expect(none.is_empty(), "with nothing untapped the AI declares no attackers (%d)" % none.size())

	print("[AIParty] %d checks | failures: %d" % [_checks, _fails])
	print("[AIParty] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
