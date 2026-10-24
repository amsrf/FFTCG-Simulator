extends Node
## KUJA 37 probe — "When Kuja is chosen by a Summon or an ability of your opponent, your opponent discards 1 card
## from his/her hand."
##
## "Chosen" is a TARGETING event, not damage and not a set effect:
##   * it fires once, when the targeting session is CONFIRMED;
##   * only when the CHOOSER is Kuja's opponent (its own controller picking it does nothing);
##   * only for Summon/Ability targeting — an "all the Backups" effect never chooses anything.

const GAME_SCENE := preload("res://game.tscn")

const KUJA := 37
const SQUALL := 41
const IFRIT := 4
const AURON := 1
const SEPHIROTH := 44

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null
var _hand = null


## Discards the first card, so the test does not depend on cost ordering.
class FirstCardAgent extends Agent:
	func choose_discard(_player_id: int, cards: Array) -> Card:
		await _settle()
		return cards[0] if not cards.is_empty() else null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Kuja] ok   %s" % what)
	else:
		_fails += 1
		print("[Kuja] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _choose(source: Card, target: Card, kind: String) -> void:
	_field.request_target({"is_type": "Forward"}, source, false, kind)
	await get_tree().process_frame
	_field.set_target_card(target)
	await get_tree().process_frame
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [AURON, SEPHIROTH, 18],
		"opponent_field": [{"id": KUJA}, {"id": SQUALL}],
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
	_hand = _game.get("hand")

	var agent = FirstCardAgent.new()
	agent.bind(_game)
	_game.set("player_agent", agent)
	_game.set("_priority_lock", true)

	var kuja: Card = _card(KUJA)
	var squall: Card = _card(SQUALL)
	var ifrit: Card = _game.call("create_card", IFRIT, "player")
	_game.add_child(ifrit)

	# --- chosen by the opponent's SUMMON ----------------------------------------------------------------
	var hand_before: int = _hand.cards.size()
	await _choose(ifrit, kuja, "Summon")
	print("[Kuja] after the Summon chose it: stack=%d hand=%d" % [_stack.stack_length(), _hand.cards.size()])
	_expect(_stack.stack_length() == 1, "being chosen by a Summon queues Kuja's ability")
	_expect(_hand.cards.size() == hand_before, "nothing is discarded until it resolves")
	await _stack.resolve_top_effect()
	await get_tree().process_frame
	print("[Kuja] after resolution: hand=%d" % _hand.cards.size())
	_expect(_hand.cards.size() == hand_before - 1, "then Kuja's controller's opponent discards 1")

	# --- picked by its OWN controller: no trigger --------------------------------------------------------
	await _choose(squall, kuja, "Ability")
	_expect(_stack.stack_length() == 0, "its own controller choosing it does NOT trigger")
	_expect(_hand.cards.size() == hand_before - 1, "and nothing else is discarded")

	# --- the opponent picks something else: no trigger ---------------------------------------------------
	var before_other: int = _hand.cards.size()
	await _choose(ifrit, squall, "Ability")
	_expect(_stack.stack_length() == 0, "choosing a different Forward does not trigger Kuja")

	# --- chosen by the opponent's ABILITY ----------------------------------------------------------------
	var before_ability: int = _hand.cards.size()
	await _choose(ifrit, kuja, "Ability")
	_expect(_stack.stack_length() == 1, "an opponent's ABILITY choosing it triggers too")
	await _stack.resolve_top_effect()
	await get_tree().process_frame
	print("[Kuja] after the ability: hand=%d (was %d)" % [_hand.cards.size(), before_ability])
	_expect(_hand.cards.size() == before_ability - 1, "and the discard happens again")

	print("[Kuja] %d checks | failures: %d" % [_checks, _fails])
	print("[Kuja] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
