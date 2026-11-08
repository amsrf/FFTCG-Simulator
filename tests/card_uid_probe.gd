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
	# THE DESYNC CHECK MUST FIRE. Record this turn's hash, change one thing the rules track, and the comparison has
	# to fail and name exactly what differs.
	var snap_before: Dictionary = a.snapshot_by_seat()
	a.turn_hashes[a.turn_number] = a.state_hash()
	var recorded: String = a.turn_hashes[a.turn_number]
	_expect(a.compare_remote_hash(a.turn_number, recorded), "matching hashes compare equal")
	var fired := [false]
	a.desync_detected.connect(func(_t, _l, _r): fired[0] = true)
	var victim: Card = a.get("field").back_cards.front() if not a.get("field").back_cards.is_empty() else null
	_expect(victim != null, "a field card to change")
	if victim != null:
		victim.tapped = not victim.tapped
		var other_machine: String = a.state_hash()
		_expect(other_machine != recorded, "one tapped card changes the hash")
		_expect(not a.compare_remote_hash(a.turn_number, other_machine) and fired[0],
			"compare_remote_hash reports the mismatch and emits desync_detected")
		var report: Array = a.diff_snapshots(snap_before, a.snapshot_by_seat())
		_expect(report.size() == 1 and str(report[0]).begins_with("s1.back"),
			"the diff names exactly what differs (%s)" % (str(report[0]).get_slice("\n", 0) if not report.is_empty() else "nothing"))
		victim.tapped = not victim.tapped
	# A LOCAL SUMMON MOVES TO A SEPARATE STACK CARD; that stack card is the same card, so it keeps the uid and no
	# new number is consumed (the opponent's machine never makes that extra card, so a new number would desync).
	var stack = a.get("stack")
	var summon: Card = null
	for c in a.get("hand").cards + a.side_for(1).deck.deck_cards:
		if c.type == Card.SUMMON:
			summon = c
			break
	_expect(summon != null, "found a Summon to cast")
	if summon != null:
		var before_uid: int = summon.uid
		var counters_before: String = str(a._uid_counters)
		stack.cards.append(summon)
		summon.index = stack.cards.size() - 1
		stack._queue_local_summon(summon)
		var stack_card: Card = stack.cards.back()
		_expect(stack_card != summon and stack_card.uid == before_uid,
			"the Summon's stack card keeps its uid (#%d -> #%d)" % [before_uid, stack_card.uid])
		_expect(str(a._uid_counters) == counters_before, "and no new uid was consumed")
		_expect(a.card_by_uid(before_uid) == stack_card, "card_by_uid now finds the stack card")
		await Vfx.idle()
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
