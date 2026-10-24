extends Node
## BLOCKING RESTRICTIONS probe — "cannot be blocked by ..." (Yuffie 85/86) and Lann's power rule (27),
## including Advanced Rules 15.1.1.9.6: a party is blocked if the blocker can legally block AT LEAST ONE member.

const GAME_SCENE := preload("res://game.tscn")

const LANN := 27            # 7000 power, cannot be blocked by / cannot block a GREATER power Forward
const YUFFIE_85 := 85       # cost 3, cannot be blocked by a Forward of cost 4+
const YUFFIE_86 := 86       # cost 1, cannot be blocked by a Forward of cost 3+
const SQUALL := 41          # cost 3, 6000
const SNOW := 43            # cost 1, 3000
const TERRA_47 := 47        # cost 4, 7000
const DARK_KNIGHT := 55     # cost 3, 8000

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _cards: Dictionary = {}


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[BlockRule] ok   %s" % what)
	else:
		_fails += 1
		print("[BlockRule] FAIL %s" % what)


func _attack_with(card: Card) -> void:
	_field.reset_attacker()
	_field.set_attacker(card)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": YUFFIE_86}, {"id": YUFFIE_85}, {"id": LANN}],
		"opponent_field": [{"id": SQUALL}, {"id": SNOW}, {"id": TERRA_47}, {"id": DARK_KNIGHT}],
		"player_deck": range(101, 121),
		"opponent_deck": range(141, 161),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	for c in _field.get_all_cards():
		_cards[c.id] = c

	# --- 86 Yuffie: cannot be blocked by cost 3 or more -----------------------------------------------------
	_attack_with(_cards[YUFFIE_86])
	_expect(not _field.can_block(_cards[SQUALL]), "Yuffie 86 cannot be blocked by a cost-3 Forward")
	_expect(_field.can_block(_cards[SNOW]), "but a cost-1 Forward can block her")

	# --- 85 Yuffie: cannot be blocked by cost 4 or more ------------------------------------------------------
	_attack_with(_cards[YUFFIE_85])
	_expect(_field.can_block(_cards[SQUALL]), "Yuffie 85 CAN be blocked by a cost-3 Forward")
	_expect(not _field.can_block(_cards[TERRA_47]), "and cannot be blocked by a cost-4 Forward")

	# --- 27 Lann as the attacker: no blocker with GREATER power ----------------------------------------------
	_attack_with(_cards[LANN])
	_expect(_field.can_block(_cards[SQUALL]), "Lann can be blocked by a weaker Forward (6000 vs 7000)")
	_expect(not _field.can_block(_cards[DARK_KNIGHT]), "and not by a stronger one (8000)")

	# --- 27 Lann as the BLOCKER: the mirror rule -------------------------------------------------------------
	_attack_with(_cards[DARK_KNIGHT])
	_expect(not _field.can_block(_cards[LANN]), "Lann (7000) cannot block a stronger Forward (8000)")
	_attack_with(_cards[SNOW])
	_expect(_field.can_block(_cards[LANN]), "but he can block a weaker one (3000)")

	# --- Advanced Rules 15.1.1.9.6 — the pair from the rulebook ----------------------------------------------
	_field.reset_attacker()
	_field.set_attacker(_cards[YUFFIE_86])
	_expect(_field.add_party_member(_cards[YUFFIE_85]), "the two Yuffies form a party (both wind)")
	var members: Array = _field.party_members()
	_expect(members.size() == 2, "the party has two members (%d)" % members.size())
	# The cost-3 Squall cannot block 86 (cost 3+), but CAN block 85 (cost 4+), so the WHOLE party is blockable.
	_expect(_field.can_block(_cards[SQUALL]),
		"a cost-3 Forward blocks the party by legally blocking ONE member — the rulebook example")
	_expect(not _field.can_block(_cards[TERRA_47]),
		"a cost-4 Forward can block neither member, so the party is unblockable for it")

	print("[BlockRule] %d checks | failures: %d" % [_checks, _fails])
	print("[BlockRule] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
