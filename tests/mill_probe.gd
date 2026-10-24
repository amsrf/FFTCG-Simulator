extends Node
## MILL probe — the animation, the sequencing, and the three cards that use it.
##
## The animation itself is checked by its EFFECTS rather than by pixels: the card leaves the top of the deck, ends in
## the Break Zone, and a mill 3 takes about three animation-lengths because the calls are awaited one at a time.

const GAME_SCENE := preload("res://game.tscn")

const THIEF := 69           # Forward: ETB -> opponent mills 1

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Mill] ok   %s" % what)
	else:
		_fails += 1
		print("[Mill] FAIL %s" % what)


func _ready() -> void:
	# A short deck with known ids so the milled order is checkable.
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_deck": range(101, 111),
		"opponent_deck": range(201, 211),
		"player_hand": [10, 11],
		"opponent_hand": [1, 2],
		"opponent_type": "ai",
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var opp_deck = _game.get("opponent_deck")
	var opp_side: PlayerSide = _game.get("opponent")
	var pile: Node = opp_side.graveyard

	var deck_before: int = opp_deck.deck_cards.size()
	var expected_order: Array = []
	for i in range(3):
		expected_order.append(opp_deck.deck_cards[i].card_name)

	# --- the animation itself: three cards, one after another, 0.5 s each -----------------------------------
	var started: int = Time.get_ticks_msec()
	await _game.call("mill_player", 2, 3)
	var elapsed: int = Time.get_ticks_msec() - started
	print("[Mill] milled 3 in %d ms (deck %d -> %d, pile -> %d)" % [
		elapsed, deck_before, opp_deck.deck_cards.size(), pile.graveyard_cards.size()])
	_expect(opp_deck.deck_cards.size() == deck_before - 3, "mill_player(3) takes three cards off the deck")
	_expect(pile.graveyard_cards.size() == 3, "and puts three cards into the Break Zone")
	# Sequential, not simultaneous: three 0.5 s animations cannot finish faster than one and a half seconds.
	_expect(elapsed >= 1400, "the three mills run one AFTER another (took %d ms for 3 x 0.5 s)" % elapsed)

	var landed: Array = []
	for c in pile.graveyard_cards:
		landed.append(c.card_name)
		_expect(c.current_zone == Card.Zone.GRAVEYARD, "%s reports the Break Zone" % c.card_name)
	print("[Mill] order milled: %s" % str(landed))
	_expect(landed == expected_order, "the cards arrive in deck order (top card first)")

	# --- 69 Thief: its ETB makes the OPPONENT mill ----------------------------------------------------------
	var opp_deck_before: int = opp_deck.deck_cards.size()
	var opp_pile_before: int = pile.graveyard_cards.size()
	var thief: Card = _game.call("create_card", THIEF, "player")
	_game.add_child(thief)
	_field.play_card(thief, false, false, false)
	# The setup path does not fire ETB; the probe triggers it as a real play would.
	_field.execute_card_effect(thief, "when_enter_field")
	await _game.get("stack").resolve_top_effect()
	await get_tree().create_timer(1.4).timeout      # one mill animation (mill_seconds is 1.0)
	print("[Mill] Thief ETB: opponent deck %d -> %d, pile %d -> %d" % [
		opp_deck_before, opp_deck.deck_cards.size(), opp_pile_before, pile.graveyard_cards.size()])
	_expect(opp_deck.deck_cards.size() == opp_deck_before - 1, "Thief (69): the opponent mills 1")
	_expect(pile.graveyard_cards.size() == opp_pile_before + 1, "Thief (69): and it lands in the Break Zone")

	# --- data shape for 70 and 89 ---------------------------------------------------------------------------
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	_expect(effects.get("70", {}).has("when_enter_field"), "Thief (70) has an ETB entry")
	var rikku_skills: Array = effects.get("89", {}).get("skill", [])
	_expect(rikku_skills.size() == 2, "Rikku (89) has two abilities")
	var s_skill: Dictionary = rikku_skills[1] if rikku_skills.size() > 1 else {}
	var s_instructions: Array = s_skill.get("instructions", [])
	_expect(bool(s_skill.get("s_cost", false)) and not s_instructions.is_empty()
			and str(s_instructions[0].get("name", "")) == "opponent_mills",
		"Rikku's S ability is the mill-2 one")

	print("[Mill] %d checks | failures: %d" % [_checks, _fails])
	print("[Mill] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
