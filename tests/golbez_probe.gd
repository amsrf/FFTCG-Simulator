extends Node
## Golbez 135 end-to-end: leaving the field to the Break Zone searches the deck for up to four cost-2
## Forwards with different Elements, plays them, and suppresses their enter-the-field auto-abilities.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")

const GOLBEZ := 135
const FIRE := 5
const ICE := 33
const WIND := 69   # Thief: has an ETB that would mill the opponent if it were not suppressed
const EARTH := 92
const WATER := 160

var _checks: int = 0
var _fails: int = 0
var _game: Node
var _field


func _ready() -> void:
	await get_tree().process_frame
	var cfg: Dictionary = TEST_GROUNDS.config("clean")
	cfg["player_deck"] = [FIRE, ICE, WIND, EARTH, WATER, 7, 9, 16, 25, 29]
	cfg["player_field"] = []
	MatchSetup.config = cfg
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	_game.player_agent = MockAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field

	var golbez: Card = _game.create_card(GOLBEZ, "player")
	_game.add_child(golbez)
	_field.play_card(golbez, false, false)
	var opponent_deck_before: int = _game.opponent_deck.deck_cards.size()

	_game.put_card_into_graveyard(golbez)
	await get_tree().process_frame
	_expect(_game.stack.stack_length() == 1, "Golbez puts his search trigger on the stack")
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	await get_tree().process_frame
	await get_tree().process_frame

	var fronts: Array = _field.get_front_cards_for("player")
	_expect(fronts.size() == 4, "Golbez plays four cost-2 Forwards (got %d)" % fronts.size())
	var elements: Dictionary = {}
	for card in fronts:
		for value in card.current_elements():
			elements[value] = true
	_expect(elements.size() == 4, "and all four have different Elements (%s)" % str(elements.keys()))
	_expect(not fronts.has(golbez), "Golbez himself is no longer on the field")
	_expect(_game.opponent_deck.deck_cards.size() == opponent_deck_before,
		"Thief's enter-the-field mill did not trigger")
	_expect(_game.stack.stack_length() == 0, "the search does not leave an ability on the stack")

	print("[Golbez] %d checks | failures: %d" % [_checks, _fails])
	print("[Golbez] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Golbez] ok   %s" % what)
	else:
		_fails += 1
		print("[Golbez] FAIL %s" % what)
