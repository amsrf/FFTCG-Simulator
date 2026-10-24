extends Node
## CHARACTER EX BURST — same fake-stack mechanism as Summons: the revealed card's ETB is copied onto the stack and
## resolved immediately. The card stays in the Damage Zone; it does not enter the field.

const GAME_SCENE := preload("res://game.tscn")
const SQUALL := 41
const SNOW := 43

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ExChar] ok   %s" % what)
	else:
		_fails += 1
		print("[ExChar] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _to_damage(card_id: int) -> Card:
	var card: Card = _game.call("create_card", card_id, "player")
	_game.add_child(card)
	_game.get("deck").deck_cards.push_front(card)
	_game.get("player").take_damage(1)
	await get_tree().create_timer(2.3).timeout          # EX_BURST_DELAY is 2.0
	await get_tree().process_frame
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")

	# --- Gippal 101: no target, mass buff -------------------------------------------------------------
	var mine: Card = _make(SQUALL, "player")
	var before: int = mine.power
	var gippal: Card = await _to_damage(101)
	print("[ExChar] Gippal: zone=%s on_field=%s power %d->%d" % [
		gippal.current_zone, gippal.is_on_field(), before, mine.power])
	_expect(mine.power == before + 4000, "Gippal 101's EX BURST resolves its ETB (+4000 to your Forwards)")
	_expect(not gippal.is_on_field() and gippal.current_zone == Card.Zone.DAMAGE,
		"and Gippal itself stays in the Damage Zone, not on the field")

	# --- Valefor 198: no target, mass damage (Summon, same path) --------------------------------------
	var v1: Card = _make(SQUALL, "opponent")
	var v2: Card = _make(SNOW, "opponent")
	var valefor: Card = await _to_damage(198)
	print("[ExChar] Valefor: %s took %d, %s took %d" % [v1.card_name, v1.accumulated_damage,
		v2.card_name, v2.accumulated_damage])
	_expect(v1.accumulated_damage == 3000 and v2.accumulated_damage == 3000,
		"Valefor 198's EX BURST resolves without a target")
	_expect(not valefor.is_on_field() and valefor.current_zone == Card.Zone.DAMAGE,
		"and the Summon stays in the Damage Zone")

	# --- Mustadio 118: targeted burst ----------------------------------------------------------------
	var dull_one: Card = _make(SQUALL, "opponent")
	dull_one.tap()
	var mustadio: Card = await _to_damage(118)
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"Mustadio 118's EX BURST opens its targeting flow")
	_field.set_target_card(dull_one)
	_assistant.call("on_target_complete")
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	print("[ExChar] Mustadio: target on field=%s, stack=%d" % [dull_one.is_on_field(), _stack.stack_length()])
	_expect(not dull_one.is_on_field(), "and the chosen dull Forward is broken")
	_expect(not mustadio.is_on_field() and mustadio.current_zone == Card.Zone.DAMAGE,
		"while Mustadio stays in the Damage Zone")
	_expect(_stack.stack_length() == 0, "and the fake stack object is cleaned up")

	print("[ExChar] %d checks | failures: %d" % [_checks, _fails])
	print("[ExChar] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
