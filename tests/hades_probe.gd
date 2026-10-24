extends Node
## HADES 52 probe — two target STAGES with different criteria.
##
## "Choose 1 Forward and 1 Backup opponent controls. Dull the Forward and return the Backup to its owner's hand.
##  Your opponent discards 1 card from his/her hand."
##
##   stage 1 asks for a Forward, stage 2 asks for a Backup, and Confirm only appears once both are chosen.
##   Both must be legal to CAST: a board with no Backup makes the Summon illegal (mandatory targets).
##   Each instruction applies to a specific pick: dull_targets(0), return_targets_to_hand(1).

const GAME_SCENE := preload("res://game.tscn")

const HADES := 52
const SQUALL := 41
const CHEMIST := 31
const AURON := 18   # Bahamut (cost 9) — deliberately NOT the cheapest card
const SEPHIROTH := 44   # cost 4, so the discard takes this one and the returned Backup stays

## Discards the FIRST card instead of the cheapest, so the test can keep the returned Backup in hand.
class FirstCardAgent extends Agent:
	func choose_discard(_player_id: int, cards: Array) -> Card:
		await _settle()
		return cards[0] if not cards.is_empty() else null

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Hades] ok   %s" % what)
	else:
		_fails += 1
		print("[Hades] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [],
		"player_hand": [HADES],
		"opponent_field": [{"id": SQUALL}, {"id": CHEMIST}],
		"opponent_hand": [AURON, SEPHIROTH],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")
	var hand = _game.get("hand")
	var opp_hand = _game.get("opponent_hand")

	# The opponent must actually be able to discard, and the discard must not take the Backup we are checking.
	var ai = FirstCardAgent.new()
	ai.bind(_game)
	_game.set("opponent_agent", ai)
	_game.set("_priority_lock", true)

	var squall: Card = _card(SQUALL)
	var chemist: Card = _card(CHEMIST)
	_expect(squall != null and chemist != null, "the opponent has a Forward and a Backup")
	var hades: Card = hand.cards[0]

	# --- both targets are mandatory at cast time ------------------------------------------------------------
	var criteria: Array = hades.get_cast_target_criteria()
	_expect(criteria is Array and criteria.size() == 2, "Hades declares two targeting stages")
	_expect(_field.has_viable_target(criteria, hades, "Summon"), "with both present, the Summon is legal")

	# --- cast it ---------------------------------------------------------------------------------------------
	var ok: bool = await _game.call("play_card_for", 1, hades)
	_expect(ok, "the Summon leaves the hand")
	_assistant.call("charge", 5, "氷")
	_expect(_assistant.call("can_pay_cost"), "the five ice are paid")
	_assistant.call("on_charge_complete")
	for _i in range(8):
		await get_tree().process_frame

	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"stage 1 asks for a target")
	_expect(_field.get("targeting_block_index") == 0, "and it is stage 1 (a Forward)")
	_expect(squall.is_valid_target, "the Forward is legal")
	_expect(not chemist.is_valid_target, "the Backup is NOT a stage-1 target")

	# --- stage 1: the Forward --------------------------------------------------------------------------------
	_field.set_target_card(squall)
	await get_tree().process_frame
	_expect(_field.get("targeting_block_index") == 1, "picking the Forward advances to stage 2")
	_expect(_field.get("targeting_picked").size() == 1, "with one pick recorded")
	_expect(squall.ring_selected(), "and the Forward keeps its ring")
	_expect(chemist.is_valid_target, "now the Backup is legal")
	_expect(not squall.is_valid_target, "and the Forward no longer is")
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"the session stays open across the stage change")

	# --- stage 2: the Backup ---------------------------------------------------------------------------------
	_field.set_target_card(chemist)
	await get_tree().process_frame
	_expect(_field.get("targeting_picked").size() == 2, "two picks recorded")

	# --- resolve ---------------------------------------------------------------------------------------------
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	for _i in range(10):
		await get_tree().process_frame

	print("[Hades] Squall tapped=%s | Chemist on field=%s in opponent hand=%s | opponent hand=%d" % [
		str(squall.tapped), str(chemist.is_on_field()), str(opp_hand.cards.has(chemist)),
		opp_hand.cards.size()])
	_expect(squall.tapped, "the chosen Forward is dulled")
	_expect(not chemist.is_on_field(), "the chosen Backup has left the field")
	var names: Array = []
	for c in opp_hand.cards:
		names.append(c.card_name)
	print("[Hades] opponent hand now: %s | chemist parent=%s zone=%s" % [str(names), str(chemist.get_parent()), str(chemist.current_zone)])
	_expect(opp_hand.cards.has(chemist), "and returned to its owner's hand")
	_expect(opp_hand.cards.size() == 2, "one card was discarded and the Backup came back (2 left)")

	# --- a missing Backup makes the card illegal --------------------------------------------------------------
	var spare: Card = _game.call("create_card", HADES, "player")
	_game.add_child(spare)
	var no_backup: bool = _field.has_viable_target(criteria, spare, "Summon")
	print("[Hades] with no Backup on the opponent's board, legal=%s" % str(no_backup))
	_expect(not no_backup, "without a legal Backup the Summon cannot be cast at all")

	print("[Hades] %d checks | failures: %d" % [_checks, _fails])
	print("[Hades] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
