extends Node
## DEVOUT 48 / 77 probe — "choose 1 Forward of cost N or less from your Break Zone and play it onto the field".
##
## Both use the DECK SEARCH window over the Break Zone: same fan, same hover preview, same look. What is checked here
## is the zone machinery rather than the window's geometry (deck_search_probe already covers that):
##
##   * only cards in the pile that satisfy the criteria are offered;
##   * the chosen card leaves the pile and reaches the field;
##   * it arrives as a NEW permanent — damage, statuses and buffs do not ride back with it, and it is summoning-sick;
##   * with nothing legal in the pile, no window opens at all;
##   * Devout 48's ability is closed on the opponent's turn.

const GAME_SCENE := preload("res://game.tscn")

const DEVOUT_ICE := 48
const DEVOUT_WIND := 77
const SQUALL := 41
const TERRA := 47
const CID := 73   # cost 2, Forward — the only legal target for the cost-2 search

var _checks: int = 0
var _fails: int = 0
var _game = null   # untyped: the probe calls coroutines directly, and call() cannot await them
var _field = null
var _stack = null
var _pile = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Devout] ok   %s" % what)
	else:
		_fails += 1
		print("[Devout] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _pile_card(id: int) -> Card:
	for c in _pile.graveyard_cards:
		if c.id == id:
			return c
	return null


func _search_window() -> Node:
	for child in _game.get_children():
		if child.has_method("open") and child.has_method("_finish"):
			return child
	return null


func _wait_for_field(card: Card, timeout_frames: int = 300) -> void:
	for _i in range(timeout_frames):
		await get_tree().process_frame
		if card != null and is_instance_valid(card) and card.is_on_field():
			return


func _await_window(timeout_frames: int = 120) -> Node:
	for _i in range(timeout_frames):
		await get_tree().process_frame
		var w: Node = _search_window()
		if w != null:
			return w
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": DEVOUT_ICE}, {"id": DEVOUT_WIND}],
		"player_graveyard": [SQUALL, TERRA, CID],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_pile = _game.get("player_graveyard")
	_game.set("_priority_lock", true)

	var devout_ice: Card = _card(DEVOUT_ICE)
	var devout_wind: Card = _card(DEVOUT_WIND)
	var squall: Card = _pile_card(SQUALL)
	var terra: Card = _pile_card(TERRA)
	var cid: Card = _pile_card(CID)
	print("[Devout] pile before: %s" % str(_pile.graveyard_cards.map(func(c): return c.card_name)))
	_expect(squall != null and terra != null and cid != null, "the Break Zone holds three Forwards")

	# The returning permanent must be NEW, so dirty the card before it comes back.
	cid.accumulated_damage = 3000
	cid.status_effects["test_marker"] = 1

	# --- 77: enter the field -> cost 2 or less -------------------------------------------------------------
	_game.set("_current_source_card", devout_wind)
	_field.execute_card_effect(devout_wind, "when_enter_field")
	# A coroutine call as a STATEMENT is fine; only using its return value requires await, and we cannot await here
	# because driving the window is what lets it finish.
	_stack.resolve_top_effect()
	var window: Node = await _await_window()
	_expect(window != null, "the Break Zone search opens")
	if window != null:
		var shown: Array = window.get("_matching")
		print("[Devout] 77 offered %s" % str(shown))
		_expect(shown.size() == 1 and int(shown[0]) == CID, "only the cost-2 Forward is offered")
		var subtitle = window.get("_subtitle")
		_expect(subtitle != null and "Break Zone" in subtitle.text, "and it says it is the Break Zone")
		window.call("_finish", CID)
	await _wait_for_field(cid)
	print("[Devout] Cid on field=%s damage=%d statuses=%s" % [
		str(cid.is_on_field()), cid.accumulated_damage, str(cid.status_effects.keys())])
	_expect(cid.is_on_field(), "the chosen Forward reaches the field")
	_expect(not _pile.graveyard_cards.has(cid), "and leaves the Break Zone")
	_expect(cid.accumulated_damage == 0, "its damage is reset (a permanent coming back is a new object)")
	_expect(not cid.status_effects.has("test_marker"), "and its old statuses are gone")
	_expect(cid.status_effects.has("summoning_sickness"), "it arrives summoning-sick, like any just-played card")

	# --- 48: activated, cost 4 or less --------------------------------------------------------------------
	_game.set("_current_source_card", devout_ice)
	_game.set("_current_controller", "player")
	_game.play_from_break_zone({"is_type": "Forward", "is_cost_lower_than": 5})
	var window2: Node = await _await_window()
	_expect(window2 != null, "the ability opens the same search")
	if window2 != null:
		var shown2: Array = window2.get("_matching")
		print("[Devout] 48 offered %s" % str(shown2))
		_expect(shown2.size() == 2, "both remaining Forwards qualify for cost 4 or less")
		_expect(not (CID in shown2), "the one already played is no longer in the pile")
		window2.call("_finish", SQUALL)
	await _wait_for_field(squall)
	_expect(squall.is_on_field(), "the chosen Forward is played")
	_expect(_pile.graveyard_cards.size() == 1, "the pile shrank by one")

	# --- nothing legal: no window at all -------------------------------------------------------------------
	_expect(_pile_card(TERRA) != null and terra.cost > 2, "Terra costs more than 2")
	var spare_window_before: bool = _search_window() != null
	_game.play_from_break_zone({"is_type": "Forward", "is_cost_lower_than": 3})
	for _i in range(20):
		await get_tree().process_frame
	_expect(not spare_window_before and _search_window() == null, "with no legal card, no window opens")
	_expect(_pile_card(TERRA) != null, "and nothing moves")

	# --- 48 is closed on the opponent's turn ----------------------------------------------------------------
	GlobalVariables.set_base_mode(GlobalVariables.Player_Mode.FREE)
	_game.set("priority_holder", 1)
	_game.set("turn_owner", 1)
	_expect(_field.can_activate_now(devout_ice), "Devout 48 is available on your own turn")
	_game.set("turn_owner", 2)
	_expect(not _field.can_activate_now(devout_ice), "and closed on the opponent's turn")

	print("[Devout] %d checks | failures: %d" % [_checks, _fails])
	print("[Devout] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
