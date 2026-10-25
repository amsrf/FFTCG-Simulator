extends Node
## Pilot for the code-defined effect layer: Kimahri 103 and Shantotto 107.
##
## The point is not only these cards: it checks that a continuous element query and a triggered event both go through
## CardEffect/EffectContext instead of ambient instruction state.

const GAME_SCENE := preload("res://game.tscn")
const MOCK := preload("res://scripts/agents/mock_agent.gd")

const KIMAHRI := 103
const SHANTOTTO := 107
const MIME := 173


class ChoiceAgent extends MockAgent:
	var chosen: String = "雷"

	func choose_element(_owner_id: int, _options: Array, _prompt: String = "") -> String:
		return chosen


var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CodeEffect] ok   %s" % what)
	else:
		_fails += 1
		print("[CodeEffect] FAIL %s" % what)


func _boot() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var a = MOCK.new()
	a.bind(_game)
	var b = MOCK.new()
	b.bind(_game)
	_game.set("player_agent", a)
	_game.set("opponent_agent", b)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.untap()
	return card


func _ready() -> void:
	await _boot()

	# --- 103: continuous element grant ------------------------------------------------------------
	var kimahri: Card = _make(KIMAHRI, "player")
	_make(41, "opponent")   # ice
	_make(1, "opponent")    # fire
	_make(71, "opponent")   # wind
	_make(183, "opponent")  # light
	_make(184, "opponent")  # dark
	var elements: Array = kimahri.current_elements()
	_expect(kimahri.is_element("土"), "Kimahri keeps its printed Earth element")
	_expect(kimahri.is_element("氷") and kimahri.is_element("火") and kimahri.is_element("風"),
		"Kimahri gains the opponent Characters' Ice, Fire and Wind Elements")
	_expect(not kimahri.is_element("光") and not kimahri.is_element("闇"),
		"Kimahri does not gain Light or Dark")
	_expect(kimahri.is_element("Earth"), "the English element name resolves through the same query")
	_expect(elements.size() == 4, "the element set has no duplicates")

	# --- EffectContext: an element override replaces the whole set (Mime's primitive) --------------
	var ctx = kimahri.make_effect_context("test")
	ctx.set_element_until_end_of_turn(kimahri, "火")
	_expect(kimahri.current_elements() == ["火"], "an element override replaces the current Elements")
	_expect(kimahri.is_element("火") and not kimahri.is_element("土"),
		"the override is visible through is_element()")
	kimahri.status_effects.erase("element_override")
	_expect(kimahri.is_element("土"), "removing the override restores the printed/effect Elements")

	# --- 107: continuous six-element grant + ETB removal -----------------------------------------
	await _boot()
	var shantotto: Card = _make(SHANTOTTO, "player")
	var player_forward: Card = _make(41, "player")
	var opponent_forward: Card = _make(1, "opponent")
	_expect(shantotto.is_element("火") and shantotto.is_element("氷") and shantotto.is_element("風")
		and shantotto.is_element("土") and shantotto.is_element("雷") and shantotto.is_element("水"),
		"Shantotto has the six named Elements")
	_expect(shantotto.current_elements().size() == 6, "its element set is exactly those six")

	_field.execute_card_effect(shantotto, "when_enter_field")
	_expect(_game.stack.stack_length() == 1, "the ETB is a stack object, not an immediate action")
	_expect(_game.stack.cards.back().effect_event == "when_enter_field",
		"the stack copy names the code event")
	await _game.stack.resolve_top_effect()
	_expect(_game.stack.stack_length() == 0, "the ability resolves off the stack")
	_expect(not player_forward.is_on_field() and not opponent_forward.is_on_field(),
		"all Forwards left the field")
	_expect(shantotto.is_on_field(), "Shantotto, a Backup, remains")
	_expect(_game.player_removed.graveyard_cards.has(player_forward),
		"the player's Forward went to the removed zone")
	_expect(_game.opponent_removed.graveyard_cards.has(opponent_forward),
		"the opponent's Forward went to the removed zone")

	# --- 173: Attack Phase start, element choice, temporary override ---------------------------------
	await _boot()
	var mime: Card = _make(MIME, "player")
	var chooser := ChoiceAgent.new()
	chooser.bind(_game)
	_game.player_agent = chooser
	_field.trigger_event("attack_phase_start", {"player_id": 1})
	_expect(_game.stack.stack_length() == 1, "Mime's attack-phase trigger is a stack object")
	await _game.stack.resolve_top_effect()
	_expect(mime.is_element("雷") and not mime.is_element("水"),
		"the chosen Element replaces Mime's printed Water")
	_expect(mime.status_effects.has("element_override"), "the override is a temporary status")
	# The opponent's Attack Phase must not re-trigger the player's Mime.
	_field.trigger_event("attack_phase_start", {"player_id": 2})
	await _game.stack.resolve_top_effect()
	_expect(mime.is_element("雷"), "the opponent's Attack Phase leaves the current element alone")
	mime.turn_end()
	_expect(mime.is_element("水") and not mime.status_effects.has("element_override"),
		"the override expires with the turn")

	print("[CodeEffect] %d checks | failures: %d" % [_checks, _fails])
	print("[CodeEffect] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
