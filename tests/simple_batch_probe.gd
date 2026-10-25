extends Node
## Batch probe for the first simple JSON→code migrations.

const GAME_SCENE := preload("res://game.tscn")
const AI := preload("res://scripts/agents/ai_agent.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SimpleBatch] ok   %s" % what)
	else:
		_fails += 1
		print("[SimpleBatch] FAIL %s" % what)


func _boot() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var a = AI.new()
	a.bind(_game)
	var b = AI.new()
	b.bind(_game)
	_game.set("player_agent", a)
	_game.set("opponent_agent", b)


func _put(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.untap()
	return card


func _trigger(card: Card, event: String) -> void:
	_field.execute_card_effect(card, event)
	await _game.stack.resolve_top_effect()


func _ready() -> void:
	# 21 Firion: choose a Forward and deal 4000.
	await _boot()
	var firion: Card = _put(21, "player")
	var victim: Card = _put(1, "opponent")
	await _trigger(firion, "when_enter_field")
	_expect(victim.accumulated_damage == 4000, "21 deals 4000 to the chosen Forward")

	# 33: opponent discards one.
	await _boot()
	var discarder: Card = _put(33, "player")
	var opp_hand = _game.get("opponent_hand")
	var opp_card: Card = _game.call("create_card", 4, "opponent")
	_game.add_child(opp_card)
	opp_hand.draw(opp_card)
	var before: int = opp_hand.cards.size()
	await _trigger(discarder, "when_enter_field")
	_expect(opp_hand.cards.size() == before - 1, "33 makes the opponent discard one card")

	# 65: choose a player Backup and untap it.
	await _boot()
	var untapper: Card = _put(65, "player")
	# The printed wording allows choosing a Backup you control; with only one on the board the choice is unambiguous.
	untapper.tap()
	await _trigger(untapper, "when_enter_field")
	_expect(not untapper.tapped, "65 untaps the chosen Backup")

	# 69: opponent mills one.
	await _boot()
	var miller: Card = _put(69, "player")
	var opp_grave_before: int = _game.get("opponent_graveyard").graveyard_cards.size()
	var opp_deck_before: int = _game.get("opponent_deck").deck_cards.size()
	await _trigger(miller, "when_enter_field")
	_expect(_game.get("opponent_deck").deck_cards.size() == opp_deck_before - 1
		and _game.get("opponent_graveyard").graveyard_cards.size() == opp_grave_before + 1,
		"69 mills the opponent's top card")

	# 115: choose a Forward and grant Brave.
	await _boot()
	var brave_giver: Card = _put(115, "player")
	var brave_target: Card = _put(1, "player")
	await _trigger(brave_giver, "when_enter_field")
	_expect(brave_target.status_effects.has("brave"), "115 grants Brave to the chosen Forward")

	# 167: draw one.
	await _boot()
	var drawer: Card = _put(167, "player")
	var hand_before: int = _game.get("hand").cards.size()
	await _trigger(drawer, "when_enter_field")
	_expect(_game.get("hand").cards.size() == hand_before + 1, "167 draws one card")

	# 125: choose a damaged Forward and deal 5000.
	await _boot()
	var damaged_hitter: Card = _put(125, "player")
	var damaged: Card = _put(1, "opponent")
	damaged.suffer_damage(1000)
	await _trigger(damaged_hitter, "when_enter_field")
	_expect(damaged.accumulated_damage == 6000, "125 deals 5000 to the damaged Forward")

	print("[SimpleBatch] %d checks | failures: %d" % [_checks, _fails])
	print("[SimpleBatch] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
