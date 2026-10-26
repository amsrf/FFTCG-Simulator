extends Node
## EXDEATH 122 — "Any card put in the Damage Zone due to Exdeath cannot use its EX Burst."
##
## The suppression is per SOURCE, not global:
##   * damage from Exdeath -> the damage card lands but its ex_burst is skipped;
##   * damage from anything else -> the ex_burst still runs (the Ifrit on top of the deck opens its targeting).
##
## It also checks the integration path, not just the direct call: the attack-damage phase goes through
## cause_attacking_damage(), which is the same function the party-damage trigger uses.

const GAME_SCENE := preload("res://game.tscn")

const EXDEATH := 122
const SQUALL := 41
const IFRIT := 4
const WAIT := 2.4   # EX_BURST_DELAY is 2.0

var _checks: int = 0
var _fails: int = 0
var _game = null
var _field = null
var _stack = null
var _assistant = null
var _opponent = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Exdeath] ok   %s" % what)
	else:
		_fails += 1
		print("[Exdeath] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _zone_size() -> int:
	return _opponent.damage_zone.cards.size()


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": EXDEATH}],
		"opponent_field": [{"id": SQUALL}],
		"player_deck": range(101, 131),
		# Three Ifrits on top: every damage card in this probe is an EX BURST card.
		"opponent_deck": [IFRIT, IFRIT, IFRIT] + range(131, 160),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")
	_opponent = _game.get("opponent")

	var exdeath: Card = _card(EXDEATH)
	var squall: Card = _card(SQUALL)
	var other_source: Card = _game.call("create_card", SQUALL, "player")
	_expect(exdeath != null and exdeath.card_effects.has("ex_burst_disabler"),
		"Exdeath carries the ex_burst_disabler property")
	_expect(_opponent.deck.deck_cards[0].id == IFRIT, "the next damage card is the EX BURST Ifrit")

	# --- 1. damage FROM EXDEATH: the card still becomes damage, the burst is skipped ------------------------
	_opponent.take_damage(1, exdeath)
	await get_tree().create_timer(WAIT).timeout
	print("[Exdeath] after Exdeath's damage: zone=%d stack=%d mode=%s" % [
		_zone_size(), _stack.stack_length(), GlobalVariables.get_player_mode()])
	_expect(_zone_size() == 1, "the card is still put in the Damage Zone")
	_expect(_opponent.damage_zone.cards[0].current_zone == Card.Zone.DAMAGE,
		"and it really is a Damage Zone card")
	_expect(_stack.stack_length() == 0, "but no EX BURST effect is queued")
	_expect(GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET,
		"and no targeting session opens")

	# --- 2. damage from ANYTHING ELSE: the burst runs as usual --------------------------------------------
	_opponent.take_damage(1, other_source)
	await get_tree().create_timer(WAIT).timeout
	print("[Exdeath] after another source: zone=%d stack=%d mode=%s" % [
		_zone_size(), _stack.stack_length(), GlobalVariables.get_player_mode()])
	_expect(_zone_size() == 2, "the second damage card lands")
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"and its EX BURST opens targeting, exactly like a normal EX BURST")

	# clean the targeting session and the queued burst before the integration check
	_assistant.call("on_target_cancel")
	await get_tree().process_frame
	if _stack.stack_length() > 0:
		_stack.call("cancel_stack_card", _stack.cards.back())
	await get_tree().process_frame
	_expect(_stack.stack_length() == 0, "the queued burst is cleared for the next check")

	# --- 3. the real attack path: the phase function, Exdeath as the attacker -----------------------------
	_game.set("turn_owner", 1)
	_field.set_attacker(exdeath)
	_game.call("cause_attacking_damage")
	await get_tree().create_timer(WAIT).timeout
	print("[Exdeath] after the attack path: zone=%d stack=%d" % [_zone_size(), _stack.stack_length()])
	_expect(_zone_size() == 3, "an unblocked Exdeath deals damage through the attack path")
	_expect(_stack.stack_length() == 0, "and that damage's EX BURST is suppressed too")

	print("[Exdeath] %d checks | failures: %d" % [_checks, _fails])
	print("[Exdeath] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
