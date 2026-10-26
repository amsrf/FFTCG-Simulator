extends Node
## DIVIDE DAMAGE probe — Yuffie 85's Bloodfest: choose up to 3 Forwards, confirm, then split 6000 damage between them.
##
## The split happens BEFORE the ability commits, which is what makes Cancel able to step back to target selection.
## That round trip is the main thing this asserts.

const GAME_SCENE := preload("res://game.tscn")
const PARTY_SPLIT := preload("res://party_split.tscn")

const YUFFIE := 85
const SQUALL := 41
const SNOW := 43
const DARK_KNIGHT := 55

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _cards: Dictionary = {}


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Divide] ok   %s" % what)
	else:
		_fails += 1
		print("[Divide] FAIL %s" % what)


func _find_split_window() -> Node:
	for child in _game.get_children():
		if is_instance_valid(child) and child.has_method("bump") and child.has_method("can_confirm"):
			return child
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": YUFFIE}],
		"player_hand": [YUFFIE],
		"opponent_field": [{"id": SQUALL}, {"id": SNOW}, {"id": DARK_KNIGHT}],
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

	var yuffie: Card = _cards[YUFFIE]
	var specs: Array = yuffie.effect().activated_abilities()
	_expect(specs.size() == 1, "Yuffie 85 has her Bloodfest ability")
	_expect(specs.size() == 1 and str(specs[0].text).begins_with("《S》") and specs[0].divide_total == 6000,
		"and it is the S ability, with display text and a divide pool")

	# --- the window on its own ------------------------------------------------------------------------------
	var window = PARTY_SPLIT.instantiate()
	_game.add_child(window)
	window.allow_cancel = true
	window.open([_cards[SQUALL], _cards[SNOW], _cards[DARK_KNIGHT]], 6000)
	_expect(window.call("assigned") == 0, "the split starts at zero")
	_expect(not window.call("can_confirm"), "Confirm is closed until the whole pool is assigned")
	window.call("bump", 0, 2)
	window.call("bump", 1, 1)
	_expect(not window.call("can_confirm"), "2000 + 1000 is still short of 6000")
	window.call("bump", 2, 3)
	_expect(window.call("assigned") == 6000, "2000 + 1000 + 3000 assigns the whole pool")
	_expect(window.call("can_confirm"), "which opens Confirm")
	var got: Array = []
	window.finished.connect(func(split: Array) -> void: got.append(split))
	window.call("confirm")
	await get_tree().process_frame
	_expect(not got.is_empty() and got[0] == [2000, 1000, 3000], "the split is reported in target order (%s)" % str(got))

	# --- cancel ----------------------------------------------------------------------------------------------
	var no_cancel = PARTY_SPLIT.instantiate()
	_game.add_child(no_cancel)
	no_cancel.allow_cancel = false
	no_cancel.open([_cards[SQUALL]], 1000)
	no_cancel.call("cancel")
	_expect(is_instance_valid(no_cancel), "a blocker's split has no Cancel at all")
	no_cancel.queue_free()

	var cancellable = PARTY_SPLIT.instantiate()
	_game.add_child(cancellable)
	cancellable.allow_cancel = true
	cancellable.open([_cards[SQUALL]], 1000)
	var cancelled: Array = []
	cancellable.finished.connect(func(split: Array) -> void: cancelled.append(split))
	cancellable.call("cancel")
	await get_tree().process_frame
	_expect(cancelled == [[]], "Cancel reports an empty split (%s)" % str(cancelled))

	# --- the real flow: targets -> split -> Cancel -> targets -> split -> damage -----------------------------
	var stack = _game.get("stack")
	# Absorb the request_priority that committing the ability emits, so the probe owns the sequencing.
	_game.set("_priority_lock", true)
	_expect(stack.call("add_skill_activation_proxy", yuffie, 0), "the ability proxy is on the stack")
	var proxy: Card = stack.get("skill_activation_proxy")
	_field.request_target({"is_type": "Forward", "count": 3}, proxy, true, "Ability")
	for id in [SQUALL, SNOW, DARK_KNIGHT]:
		_field.set_target_card(_cards[id])
	_expect(_field.targeting_picked.size() == 3, "three targets are picked")

	_game.get("assistant").call("on_target_complete")     # confirm targets -> distribution
	await get_tree().process_frame
	await get_tree().process_frame
	var split_window: Node = _find_split_window()
	_expect(split_window != null, "confirming the targets opens the distribution window")
	if split_window != null:
		split_window.call("cancel")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[Divide] after Cancel: mode=%s, picks=%d, stack=%d, damage=%s" % [
		GlobalVariables.get_player_mode(), _field.targeting_picked.size(),
		stack.stack_length(), str(_cards[SQUALL].accumulated_damage)])
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"cancelling the distribution returns to TARGET mode")
	_expect(_find_split_window() == null, "and the distribution window is gone")
	_expect(_field.targeting_picked.size() == 3, "with the three picks still selected")
	_expect(stack.stack_length() == 1, "and the ability still on the stack, uncommitted")
	_expect(_game.get("_damage_division").is_empty(), "no split was stored")
	_expect(_cards[SQUALL].accumulated_damage == 0, "and no damage was dealt")

	_game.get("assistant").call("on_target_complete")     # confirm again
	await get_tree().process_frame
	await get_tree().process_frame
	var second: Node = _find_split_window()
	_expect(second != null, "confirming again re-opens the distribution")
	if second != null:
		second.call("bump", 0, 2)   # 2000 to Squall
		second.call("bump", 1, 1)   # 1000 to Snow
		second.call("bump", 2, 3)   # 3000 to Dark Knight
		second.call("confirm")
	await get_tree().process_frame
	_expect(_game.get("_damage_division") == [2000, 1000, 3000],
		"the chosen split is stored for the ability (%s)" % str(_game.get("_damage_division")))

	await stack.resolve_top_effect()
	await get_tree().process_frame
	print("[Divide] damage: %s=%d, %s=%d, %s=%d" % [
		_cards[SQUALL].card_name, _cards[SQUALL].accumulated_damage,
		_cards[SNOW].card_name, _cards[SNOW].accumulated_damage,
		_cards[DARK_KNIGHT].card_name, _cards[DARK_KNIGHT].accumulated_damage])
	_expect(_cards[SQUALL].accumulated_damage == 2000, "Squall takes its 2000")
	_expect(_cards[SNOW].accumulated_damage == 1000, "Snow takes its 1000")
	_expect(_cards[DARK_KNIGHT].accumulated_damage == 3000, "Dark Knight takes its 3000")
	_expect(_game.get("_damage_division").is_empty(), "and the stored split is consumed")

	print("[Divide] %d checks | failures: %d" % [_checks, _fails])
	print("[Divide] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
