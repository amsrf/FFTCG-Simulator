extends Node
## Batch 2: event-spec migration for 202, 523, 549, 583 and 719.

const GAME_SCENE := preload("res://game.tscn")
const AI := preload("res://scripts/agents/ai_agent.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Batch2] ok   %s" % what)
	else:
		_fails += 1
		print("[Batch2] FAIL %s" % what)


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


func _fire(card: Card, event: String) -> void:
	_field.execute_card_effect(card, event)
	await _game.get("stack").resolve_top_effect()


func _ready() -> void:
	# 202: when it attacks, it gains First Strike.
	await _boot()
	var first_striker: Card = _put(202, "player")
	await _fire(first_striker, "when_attack")
	_expect(first_striker.status_effects.has("first_strike"), "202 grants itself First Strike on attack")

	# 523: when this card forms a party and attacks, the opponent discards.
	await _boot()
	var party_card: Card = _put(523, "player")
	var opp_hand = _game.get("opponent_hand")
	var opp_card: Card = _game.call("create_card", 4, "opponent")
	_game.add_child(opp_card)
	opp_hand.draw(opp_card)
	var before: int = opp_hand.cards.size()
	await _fire(party_card, "when_party_attack")
	_expect(opp_hand.cards.size() == before - 1, "523 makes the opponent discard on a party attack")

	# 549: when a party you control deals damage, draw one.
	await _boot()
	var watcher: Card = _put(549, "player")
	var hand_before: int = _game.get("hand").cards.size()
	await _fire(watcher, "when_party_deals_damage")
	_expect(_game.get("hand").cards.size() == hand_before + 1, "549 draws when a party deals damage")

	# 583: when a party attacks, damage an active opponent Forward.
	await _boot()
	var hitter: Card = _put(583, "player")
	var victim: Card = _put(1, "opponent")
	await _fire(hitter, "when_party_attacks")
	_expect(victim.accumulated_damage == 8000, "583 deals 8000 to the active opponent Forward")

	# 719: when this card forms a party and attacks, return a Forward to hand.
	await _boot()
	var bouncer: Card = _put(719, "player")
	var bounced: Card = _put(1, "opponent")
	await _fire(bouncer, "when_party_attack")
	await get_tree().create_timer(1.2).timeout
	_expect(bounced.current_zone == Card.Zone.HAND, "719 returns the chosen Forward to its owner's hand")

	print("[Batch2] %d checks | failures: %d" % [_checks, _fails])
	print("[Batch2] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
