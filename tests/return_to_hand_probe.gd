extends Node
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
## RETURN TO HAND probe — the zone change and the two-phase animation.
##
## The printed mesh must be in place at the source pose before the flight begins. At landing, the card must be in
## the owner's Hand scene and card list at hand scale.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const FIELD_CARD_FACE := preload("res://scripts/cards/field_card_face.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ReturnToHand] ok   %s" % what)
	else:
		_fails += 1
		print("[ReturnToHand] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var hand = _game.get("hand")
	var before: int = hand.cards.size()

	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame
	_expect(card.current_zone == Card.Zone.FIELD, "the card starts on the FIELD")
	_expect(card.hand_mesh.mesh != FIELD_CARD_FACE.PRINTED_MESH, "the source is drawn as a field tile")
	await Vfx.idle()
	card.tap()
	var field_pose := card.global_transform

	var ctx = EFFECT_CONTEXT.new(_game, card, "test")
	# RULES FIRST: the move is complete the moment return_to_hand() returns; only the flight is queued.
	await ctx.return_to_hand([card])
	_expect(hand.cards.has(card), "the card joined the hand's card list at once (%d -> %d)" % [before, hand.cards.size()])
	_expect(card.current_zone == Card.Zone.HAND, "its zone is HAND at once (got %d)" % card.current_zone)
	_expect(not card.is_on_field(), "and the rules no longer see it on the field")
	_expect(card.get_parent() == hand and card.global_transform.is_equal_approx(field_pose),
		"the presentation starts at the original field pose")
	_expect(card.hand_mesh.mesh == FIELD_CARD_FACE.PRINTED_MESH and not card.power_label.visible,
		"the printed paper card is visible at the source, before it moves")
	_expect(card.tween == null, "the field's tap tween releases the pose before the return flight")

	# THEN THE SCREEN: once the presentation queue has played, it is drawn in the hand.
	await Vfx.idle()
	_expect(card.get_parent() == hand, "after the flight it is a child of the Hand")
	var expected: float = hand.hand_scale
	_expect(absf(card.scale.x - expected) < 0.05,
		"it is at hand scale (%.3f vs %.3f)" % [card.scale.x, expected])

	# It must be usable as a hand card afterwards, not a painted impostor.
	var index: int = hand.cards.find(card)
	_expect(index == hand.cards.size() - 1, "it sits at the end of the row (index %d)" % index)
	var slot: Vector3 = hand.calculate_card_position(index)
	_expect(card.position.distance_to(slot) < 0.12,
		"and it is in its slot (%.3f m off)" % card.position.distance_to(slot))

	# --- the data capability is present ---------------------------------------------------------------
	_expect(ctx.has_method("return_to_hand"), "the context exposes the return action")

	print("[ReturnToHand] %d checks | failures: %d" % [_checks, _fails])
	print("[ReturnToHand] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
