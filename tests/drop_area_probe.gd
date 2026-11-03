extends Node
## Drop-area checks.
##
## The hand used to test a hard-coded 3 x 1.25 m rectangle in world space, so
## most of the visible 8 x 4 m playmat rejected a dragged card. The Field now
## owns the bounds and the hand asks it.

const GAME_SCENE := preload("res://game.tscn")
const HAND_CARD := 25  # Squire, cost 2

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _hand = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DropArea] ok   %s" % what)
	else:
		_fails += 1
		print("[DropArea] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [HAND_CARD, 29, 12, 31, 32],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_hand = _game.get("hand")
	_assistant = _game.get("assistant")

	var bounds: AABB = _field.play_area_bounds()
	print("[DropArea] bounds position=%s end=%s" % [bounds.position, bounds.end])
	_expect(bounds.size.x > 7.9 and bounds.size.z > 3.9,
		"the playmat is about 8 x 4 m")
	_expect(_field.is_in_play_area(Vector3(0.0, 0.5, 0.0)),
		"the centre is inside the drop area")
	_expect(_field.is_in_play_area(Vector3(3.2, 0.5, -1.5)),
		"a front-right point is inside, even though the old tiny rectangle rejected it")
	_expect(_field.is_in_play_area(Vector3(-3.2, 0.5, 1.5)),
		"a back-left point is inside too")
	_expect(not _field.is_in_play_area(Vector3(5.0, 0.5, 0.0)),
		"a point beyond the right edge is outside")

	var card: Card = _hand.cards[0]
	_expect(card != null, "the test card is in hand")
	# Real players hover the card before dragging it. Keep that state active:
	# it used to survive the cast and lay the returned card out at the hover
	# offset instead of in the fan.
	_hand.set_hovered(card, true)
	_expect(_hand.hovered_card == card, "the card is hovered before the drag")
	card.is_dragging = true
	card.global_position = Vector3(3.2, 0.5, -1.5)
	card.current_state.handle_released()
	await get_tree().process_frame
	_expect(_hand.charging_card == card,
		"releasing over the front-right of the playmat starts the cast")
	_expect(card.get_parent() == _game.get("stack"),
		"and the card leaves the hand for the casting flow")
	_expect(_hand.hovered_card != card,
		"and leaving the hand clears the stale hover state")

	# Cancel the payment: the card must rejoin the hand's fan, not stay parked.
	# This also covers the old bug where a Stack layout tween kept writing
	# stack-local positions after the card was reparented back to the hand.
	_assistant.on_charge_cancelled()
	await get_tree().create_timer(0.35).timeout
	var target_position: Vector3 = _hand.calculate_card_position(card.index)
	_expect(card.get_parent() == _hand, "cancel returns the card to the hand")
	_expect(_hand.cards.has(card), "and the hand's card list includes it")
	_expect(not card.is_dragging, "and it is no longer marked as being dragged")
	_expect(card.position.distance_to(target_position) < 0.05,
		"and it settles into its fan slot without a manual reorder")

	print("[DropArea] %d checks | failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("[DropArea] RESULT: all checks passed")
	else:
		print("[DropArea] RESULT: %d FAILED" % _fails)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
