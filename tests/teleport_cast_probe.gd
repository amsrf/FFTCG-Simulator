extends Node
## Teleport cast presentation checks.
##
## A Character is paid for in the hand/cast stance, dissolves where it sits,
## and then materialises at its field slot. The card must never travel between
## the two, and it is never parked in the Stack.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const HAND_CARD := 25  # Squire, vanilla Forward

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _hand = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Teleport] ok   %s" % what)
	else:
		_fails += 1
		print("[Teleport] FAIL %s" % what)


func _param(card: Card, key: String) -> float:
	if card.mat == null:
		return -1.0
	return float(card.mat.get_shader_parameter(key))


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [HAND_CARD],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_hand = _game.get("hand")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")
	_field.teleport_shine_seconds = 0.25
	_field.teleport_fade_seconds = 0.20
	_field.teleport_materialize_seconds = 0.60
	_field.teleport_glow_seconds = 0.40
	_field.teleport_reveal_seconds = 0.50

	var card: Card = _hand.cards[0]
	_expect(card != null, "the test Character is in hand")
	_hand.charge(card)
	await get_tree().process_frame
	_expect(card.get_parent() == _hand and card.current_zone == Card.Zone.HAND,
		"the paying Character stays in hand instead of the fake Stack")
	_expect(card.ring_cast_pending(),
		"and is marked with the thin gold cast-pending aura")
	_hand.add_card_to_mana_conversion(card)
	_expect(not _hand.selected_cards_for_mana_conversion.has(card),
		"and cannot also be selected as a mana source")
	var source_position: Vector3 = card.global_position

	# Confirm the payment through the real signal path. This is what the player
	# does with the Confirm button: Hand pays the selected mana, Stack starts
	# the Character fade, and only then does the field teleport begin.
	_assistant.on_charge_complete()
	await get_tree().create_timer(0.10).timeout
	_expect(card.get_parent() == _hand,
		"during the shine the card is still in its hand-side stance")
	_expect(card.global_position.distance_to(source_position) < 0.02,
		"and it does not move while shining")
	_expect(_param(card, "teleport_glow") > 0.05,
		"the source glow is rising")
	_expect(_param(card, "teleport_reveal") <= 0.001,
		"the source card itself is turning into the white silhouette")
	var source_halo = card.teleport.halo
	_expect(source_halo == null or not source_halo.visible,
		"the source has no overflow halo")
	_expect(card.visible, "the source has not disappeared too early")

	await get_tree().create_timer(0.50).timeout
	_expect(card.get_parent() == _field,
		"after the source fade the card is reparented to the Field")
	_expect(card.current_zone == Card.Zone.FIELD,
		"and its zone is Field")
	_expect(card.visible, "the destination card is present while it resolves")
	_expect(_param(card, "teleport_progress") > 0.05,
		"the destination starts partially built")
	_expect(_param(card, "teleport_reveal") <= 0.001,
		"the texture is hidden while the silhouette is incomplete")
	_expect(card.teleport.chrome_hidden == true,
		"the border and power readout are hidden during the build")
	_expect(_param(card, "teleport_glow") > 0.05,
		"the destination silhouette is glowing")
	var destination_halo = card.teleport.halo
	_expect(destination_halo == null or not destination_halo.visible,
		"the destination does not draw a full-card halo during the build")

	await get_tree().create_timer(0.70).timeout
	_expect(_param(card, "teleport_progress") <= 0.001,
		"the scattered block build completes")
	_expect(_param(card, "teleport_reveal") <= 0.001,
		"the texture stays hidden through the build")
	_expect(_param(card, "teleport_glow") > 0.001,
		"the completed card is still in its glow beat")
	var glow_halo = card.teleport.halo
	_expect(glow_halo != null and glow_halo.visible,
		"the full-card halo appears only after the build is complete")

	await get_tree().create_timer(0.35).timeout
	_expect(_param(card, "teleport_reveal") > 0.001 and _param(card, "teleport_reveal") < 0.999,
		"the artwork begins revealing only after the build")
	_expect(_param(card, "teleport_glow") > 0.001,
		"the glow is still fading while the art arrives")

	await get_tree().create_timer(0.50).timeout
	_expect(_param(card, "teleport_reveal") >= 0.999,
		"the card texture is fully revealed at the end")
	_expect(card.teleport.chrome_hidden == false,
		"the border and power readout come back at the end")
	_expect(_param(card, "teleport_glow") <= 0.001,
		"the glow has faded away")
	var final_halo = card.teleport.halo
	_expect(final_halo == null or not final_halo.visible,
		"the halo is gone once the card is revealed")
	_expect(card.visible, "the fully materialised card is visible")
	_expect(_field.front_cards.has(card), "the card is in the Field row")
	_expect(not card.ring_cast_pending(), "and the thin gold cast-pending aura is gone")

	print("[Teleport] %d checks | failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("[Teleport] RESULT: all checks passed")
	else:
		print("[Teleport] RESULT: %d FAILED" % _fails)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
