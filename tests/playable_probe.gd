extends Node
## WHAT CAN I PLAY RIGHT NOW? The CP rule (11.2), "can this hand card be cast" (the blue ring), and auto-pass.

const GAME_SCENE := preload("res://game.tscn")
const COST_CHECK := preload("res://scripts/cost_check.gd")

var _checks := 0
var _fails := 0
var _game: Node = null

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Playable] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _card(id: int, side: String = "player") -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	return card

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	for _i in range(4):
		await get_tree().process_frame
	var field = _game.get("field")
	var hand = _game.call("hand_for", 1)

	# ---- THE CP RULE ----
	var fire_a := _card(5)     # Warrior of Light, fire
	var fire_b := _card(7)     # Gadot, fire
	var water := _card(151)    # Agrias, water
	var light := _card(181)    # Onion Knight, light
	var red_mage := _card(3)   # fire Backup
	var four_fire := {"火": 1, "neutral": 3}
	_expect(COST_CHECK.can_pay(four_fire, [], [fire_a, fire_b]), "a 4-cost fire card: two OTHER fire cards in hand pay it (2 + 2)")
	_expect(not COST_CHECK.can_pay(four_fire, [], [fire_a]), "one fire card is only 2 CP: not enough")
	_expect(COST_CHECK.can_pay(four_fire, [], [fire_a, water]), "the rest of the cost can come from another element (2 fire + 2 water)")
	_expect(not COST_CHECK.can_pay({"火": 1, "neutral": 1}, [], [water]), "at least 1 CP must be the card's element: water alone cannot pay")
	_expect(COST_CHECK.can_pay({"火": 1}, [], [fire_a]), "a discard may overshoot by one: 1 fire paid with a 2 CP discard")
	_expect(COST_CHECK.can_pay({"火": 1, "neutral": 1}, [red_mage], [water]), "a Backup gives 1: Red Mage (fire) + a water discard")
	_expect(not COST_CHECK.can_pay({"火": 1, "neutral": 1}, [], [light]), "Light cards cannot be discarded for CP")
	_expect(COST_CHECK.can_pay({}, [], []), "a free cost is always payable")

	# ---- CAN THIS HAND CARD BE CAST NOW? ----
	_game.set("turn_owner", 1)
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	var ifrit := _card(4)            # Summon, 1 fire, choose a Forward
	hand.add_card(ifrit)
	await get_tree().process_frame
	var mode_ok: bool = ifrit.can_be_played()
	print("[Playable] mode=%s phase=%s can_be_played=%s" % [GlobalVariables.get_player_mode(), _game.get("phase"), mode_ok])
	_expect(not field.can_cast_from_hand(ifrit), "Ifrit alone in hand, no Backups: it cannot pay for itself")
	var squall := _card(41, "opponent")
	field.play_card(squall, true, false, false)
	var mage_on_field := _card(3)
	field.play_card(mage_on_field, false, false, false)
	mage_on_field.untap()
	await get_tree().process_frame
	if mode_ok:
		_expect(field.can_cast_from_hand(ifrit), "with a fire Backup and a Forward to target, Ifrit can be cast")
		_game.set("priority_holder", 2)
		_expect(not field.can_cast_from_hand(ifrit), "but not while the opponent holds priority")
		_game.set("priority_holder", 1)
		field.refresh_available_effects()
		_expect(ifrit._available_highlight_on, "and the castable hand card gets the ring")
		_expect(field.local_has_any_play(), "so there is something to do: no auto-pass")
	mage_on_field.tap()
	field.refresh_available_effects()
	_expect(not field.can_cast_from_hand(ifrit) and not ifrit._available_highlight_on,
		"with the Backup dulled there is no fire CP: not castable, no ring")

	# ---- AUTO-PASS ----
	_expect(not field.local_has_any_play(), "nothing castable and no ability: nothing to do")
	_game.set("auto_pass", true)
	var agent = _game.get("player_agent")
	var result := [null]
	var passer := func() -> void: result[0] = await agent.take_priority(1)
	passer.call()
	var waited := 0.0
	while result[0] == null and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("[Playable] auto-pass after %.1fs: %s" % [waited, str(result[0])])
	_expect(result[0] == false, "with nothing to do, the player is passed for automatically")
	_expect(waited >= 0.5, "after a short pause, not instantly (%.1fs)" % waited)

	print("[Playable] %d checks | failures: %d" % [_checks, _fails])
	print("[Playable] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
