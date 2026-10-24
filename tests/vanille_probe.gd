extends Node
## VANILLE 1-093H probe — search with a destination, "if you do so", and a return from the Break Zone.
##
## The deck-search window needs a click, which headless cannot do, so the probe drives the window's own `_finish()`
## (the same call its Confirm button makes). That keeps the test on the real code path instead of bypassing it.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Vanille] ok   %s" % what)
	else:
		_fails += 1
		print("[Vanille] FAIL %s" % what)


func _find_window() -> Node:
	for child in _game.get_children():
		if child.has_method("_finish"):
			return child
	return null


## Run a search and answer its window with `pick`.
func _search(destination: String, pick: int) -> void:
	_game.search_deck({}, destination)
	await get_tree().process_frame
	await get_tree().process_frame
	var w: Node = _find_window()
	if w == null:
		push_warning("[Vanille] no search window appeared")
		return
	w.call("_finish", pick)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var deck = _game.get_node("Player/Deck")
	var hand = _game.get("hand")
	var removed = _game.get("player_removed")
	var graveyard = _game.get("player_graveyard")
	var field = _game.get("field")

	# --- destination "removed": the Vanille search --------------------------------------------------------
	var pick_id: int = deck.deck_cards[0].id
	var removed_before: int = removed.graveyard_cards.size()
	await _search("removed", pick_id)
	_expect(removed.graveyard_cards.size() == removed_before + 1,
		"a search with destination 'removed' exiles the card (%d -> %d)" % [
			removed_before, removed.graveyard_cards.size()])

	# --- destination "hand" is still the default ----------------------------------------------------------
	var hand_before: int = hand.cards.size()
	var pick2: int = deck.deck_cards[0].id
	await _search("hand", pick2)
	_expect(hand.cards.size() == hand_before + 1,
		"'hand' still works, so existing search cards are unaffected (%d -> %d)" % [
			hand_before, hand.cards.size()])

	# --- return_from_break_zone + the "if you did so" guard -----------------------------------------------
	var card: Card = _game.create_card(47, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame
	_game.break_card(card)
	await get_tree().process_frame
	_expect(graveyard.graveyard_cards.has(card), "a broken card is in the Break Zone to begin with")
	_game.set("_current_source_card", card)

	# NOT succeeded: the guard must skip the return entirely.
	_game.set("_last_action_succeeded", false)
	var guarded: Array[Instruction] = [
		Instruction.new("return_from_break_zone", "game", [true], "if_last_succeeded"),
	]
	_game.set("_current_instructions", guarded)
	_game._process_next_instruction()
	await get_tree().process_frame
	_expect(graveyard.graveyard_cards.has(card) and not card.is_on_field(),
		"the guarded return is SKIPPED when the search did not happen")

	# Succeeded: now it comes back, dull. The source has to be set again because finishing the previous chain cleaned
	# the instruction stack, which is what a real chain does at its end.
	_game.set("_current_source_card", card)
	_game.set("_last_action_succeeded", true)
	var unguarded: Array[Instruction] = [
		Instruction.new("return_from_break_zone", "game", [true], "if_last_succeeded"),
	]
	_game.set("_current_instructions", unguarded)
	_game._process_next_instruction()
	await get_tree().process_frame
	_expect(card.is_on_field(), "with success it returns to the field")
	_expect(card.tapped, "and it arrives DULL, as the card says")
	_expect(not graveyard.graveyard_cards.has(card), "it has left the Break Zone")
	_expect(not card.broken, "and it is no longer marked as broken")

	# --- the data -----------------------------------------------------------------------------------------
	var entry: Dictionary = CardDatabase.card_effects.get("93", {})
	var instrs: Array = entry.get("when_enter_break_from_field", {}).get("instructions", [])
	_expect(instrs.size() == 2, "Vanille has two instructions")
	if instrs.size() == 2:
		_expect(str(instrs[0].get("name", "")) == "search_deck", "the first is the search")
		_expect(str(instrs[0].get("argument", []).back()) == "removed", "with destination 'removed'")
		_expect(str(instrs[1].get("condition", "")) == "if_last_succeeded",
			"and the return is conditional on it having worked")

	print("[Vanille] %d checks | failures: %d" % [_checks, _fails])
	print("[Vanille] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
