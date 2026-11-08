extends Node
## Drop-area checks.
##
## The hand used to test a hard-coded 3 x 1.25 m rectangle in world space, so
## most of the visible 8 x 4 m playmat rejected a dragged card. The Field now
## owns the bounds and the hand asks it.

const GAME_SCENE := preload("res://game.tscn")
const HAND_CARD := 25  # Squire, cost 2
const SUMMON_CARD := 62  # Valefor, no target required

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


func _param(card: Card, key: String) -> float:
	if card.mat == null:
		return -1.0
	return float(card.mat.get_shader_parameter(key))


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
	# Character drops now check the POINTER (the preview stays in a bottom band), while
	# Summon drops still check the card itself. Use a no-target Summon for the board-drop
	# checks below, then the Character for the payment-fade checks.
	var summon: Card = _game.create_card(SUMMON_CARD, "player")
	_game.add_child(summon)
	_hand.add_card(summon)

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

	var card: Card = summon
	_expect(card != null, "the test Summon is in hand")
	# Real players hover the card before dragging it. Keep that state active:
	# it used to survive the cast and lay the returned card out at the hover
	# offset instead of in the fan.
	_hand.set_hovered(card, true)
	_expect(_hand.hovered_card == card, "the card is hovered before the drag")
	card.is_dragging = true
	card.global_position = Vector3(3.2, 0.5, -1.5)
	_hand.on_card_released(card)
	await get_tree().process_frame
	_expect(_hand.charging_card == card,
		"releasing over the front-right of the playmat starts the cast")
	_expect(card.get_parent() == _game.get("stack"),
		"and the card is parked in the fake Stack")
	_expect(not _hand.cards.has(card), "and the hand no longer owns it")
	_expect(not card.ring_cast_pending(), "and a Summon is parked without the Character pending aura")
	_expect(_hand.hovered_card != card,
		"and starting the cast clears the stale hover state")

	# Cancel the payment: the parked card must rejoin the hand's fan.
	_assistant.on_charge_cancelled()
	await get_tree().create_timer(0.35).timeout
	var target_position: Vector3 = _hand.calculate_card_position(card.index)
	_expect(card.get_parent() == _hand, "cancel returns the card to the hand")
	_expect(not card.ring_cast_pending(), "and clears the thin gold cast-pending aura")
	_expect(_hand.cards.has(card), "and the hand's card list includes it")
	_expect(not card.is_dragging, "and it is no longer marked as being dragged")
	_expect(card.position.distance_to(target_position) < 0.05,
		"and it settles into its fan slot without a manual reorder")

	# THE RELEASE SIGNAL CAN BE MISSED. It only fires while the pointer is over the
	# card's CardArea3D, so a fast release or a release just off the edge used to
	# leave the card parked wherever it was dropped until an unrelated re-layout.
	# Card.release_drag() is the fallback; calling it twice must only drop once.
	card.begin_drag()
	card.global_position = Vector3(5.0, 0.5, 0.0)
	card.release_drag()
	card.release_drag()
	await get_tree().create_timer(0.35).timeout
	var fallback_home: Vector3 = _hand.calculate_card_position(card.index)
	_expect(card.get_parent() == _hand and _hand.cards.has(card) and not card.is_dragging,
		"a missed release returns the card to the hand instead of leaving it on the board")
	_expect(card.position.distance_to(fallback_home) < 0.05,
		"and it lands in its fan slot")

	# The Summon was only for the drop path; the rest of the probe is about the
	# Character payment presentation.
	_hand.remove_card(card)
	card.queue_free()
	var character: Card = _hand.cards[0]
	_expect(character != null, "the Character is in hand")

	# CHARACTER CAST STANCE. Once the pointer leaves the hand band the card
	# latches in place; releasing it there starts payment without putting it on
	# the Stack. Cancelling returns it to the fan and clears the latch.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	character.begin_drag()
	_hand.begin_character_drag(character)
	_expect((_hand.update_character_drag(character, viewport_size * Vector2(0.5, 0.2))
			and _hand.character_drag_latched()), "a Character latches into the cast stance above the hand band")
	var stance_pose: Transform3D = character.global_transform
	character.release_drag()
	await get_tree().process_frame
	_expect(_hand.charging_card == character,
		"releasing the latched Character starts mana charging")
	_expect((character.global_transform.is_equal_approx(stance_pose)
			and character.get_parent() == _hand
			and not _game.get("stack").layout_cards().has(character)),
		"the paying Character keeps its cast stance and stays out of the Stack fan")
	_assistant.on_charge_cancelled()
	await get_tree().create_timer(0.35).timeout
	_expect((character.get_parent() == _hand and _hand.cards.has(character)
			and not _hand.character_drag_latched()),
		"cancelling a latched Character returns it to hand and clears the latch")

	# Confirm pays the mana cards FIRST; the marked Character must not start
	# fading until their discard flight has landed.
	_expect(_hand.charge(character), "the Character can be charged again")
	await get_tree().process_frame
	var mana_card: Card = null
	for c in _hand.cards:
		if c != character:
			mana_card = c
			break
	_expect(mana_card != null, "another hand card is available to pay")
	_hand.add_card_to_mana_conversion(mana_card)
	_expect(_hand.selected_cards_for_mana_conversion.has(mana_card),
		"the other card can be selected as mana")
	_assistant.on_charge_complete()
	await get_tree().create_timer(0.15).timeout
	_expect(mana_card.get_parent() == _hand.graveyard,
		"the payment card is already in the Break Zone")
	_expect(_param(character, "teleport_glow") <= 0.001,
		"the Character fade waits for the discard flight")
	await get_tree().create_timer(0.65).timeout
	_expect(_param(character, "teleport_glow") > 0.001,
		"the fade starts only after the discard flight")

	print("[DropArea] %d checks | failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("[DropArea] RESULT: all checks passed")
	else:
		print("[DropArea] RESULT: %d FAILED" % _fails)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
