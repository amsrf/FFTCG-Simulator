extends Node
## STABLE CARD IDENTITY (toward online play). Every card the rules can refer to has a uid that is unique, looks up
## back to the same card, and is identical across two boots of the same match — what lets "I block with #100017" mean
## the same card on both machines.

const GAME_SCENE := preload("res://game.tscn")

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CardUid] ok   %s" % what)
	else:
		_fails += 1
		print("[CardUid] FAIL %s" % what)

func _all_cards(game: Node) -> Array:
	var out: Array = []
	var stack_ := [game]
	while not stack_.is_empty():
		var n: Node = stack_.pop_back()
		if n is Card and (n as Card).uid != 0:
			out.append(n)
		for ch in n.get_children():
			stack_.append(ch)
	for id in [1, 2]:
		for c in game.side_for(id).deck.deck_cards:
			if not out.has(c):
				out.append(c)
	return out

func _boot() -> Node:
	MatchSetup.config = MatchSetup.build_config("ai", {"seed": 777})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	return game

func _ready() -> void:
	var a: Node = await _boot()
	var cards: Array = _all_cards(a)
	var uids: Dictionary = {}
	var dupes := 0
	for c in cards:
		if uids.has(c.uid):
			dupes += 1
		uids[c.uid] = "%d:%s:%s" % [c.id, c.controller, Card.Zone.keys()[c.current_zone]]
	_expect(cards.size() > 40, "the board has cards to number (%d)" % cards.size())
	_expect(dupes == 0, "every uid is unique (%d duplicates)" % dupes)
	_expect(cards.all(func(c): return a.card_by_uid(c.uid) == c), "card_by_uid() finds each card again")
	_expect(cards.all(func(c): return (c.uid / 100000) == (1 if c.controller == Card.PLAYER else 2)),
		"the uid's seat matches the card's side")
	a.queue_free()
	await get_tree().process_frame
	var b: Node = await _boot()
	var same := 0
	var other := 0
	for c in _all_cards(b):
		if uids.get(c.uid, "") == "%d:%s:%s" % [c.id, c.controller, Card.Zone.keys()[c.current_zone]]:
			same += 1
		else:
			other += 1
	_expect(other == 0 and same == uids.size(), "a second boot numbers every card identically (%d same, %d different)" % [same, other])
	print("[CardUid] %d checks | failures: %d" % [_checks, _fails])
	print("[CardUid] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
