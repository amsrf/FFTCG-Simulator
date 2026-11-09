extends Node

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _game: Node
var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Shadow] ok   %s" % what)
	else:
		_fails += 1
		print("[Shadow] FAIL %s" % what)

func _strength(card: Card) -> float:
	return float(card.mat.get_shader_parameter("shadow_strength"))

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var hand = _game.get("hand")
	hand.update_card_positions()
	await get_tree().process_frame

	var cards: Array = hand.cards
	print("[Shadow] hand has %d cards" % cards.size())
	var shadowed: int = 0
	var silhouettes: int = 0
	for card in cards:
		var s: float = _strength(card)
		if s > 0.0:
			shadowed += 1
		_expect(s >= 0.0 and s <= 1.0, "%s shadow strength in range (%.2f)" % [card.card_name, s])
		if s > 0.0:
			var shape: Vector3 = card.mat.get_shader_parameter("shadow_shape")
			var inverse: Transform3D = card.mat.get_shader_parameter("shadow_inverse")
			_expect(shape.x > 0.0 and shape.y > 0.0 and shape.z >= 0.0,
				"%s has a complete rounded silhouette" % card.card_name)
			_expect(is_finite(inverse.basis.determinant()) and absf(inverse.basis.determinant()) > 0.00001,
				"%s caster projection is invertible" % card.card_name)
			silhouettes += 1
	_expect(shadowed >= cards.size() - 1, "every covered card has a shadow (%d of %d)" % [shadowed, cards.size()])
	_expect(silhouettes > 0, "shadows use current caster transforms and full silhouettes")
	_expect(shadowed < cards.size(), "the topmost card has no shadow")

	# Hover the middle card: it rises above both neighbours, so they must be shadowed and it must not.
	var middle: Card = cards[cards.size() / 2]
	hand.set_hovered(middle, true)
	_expect(float(hand.get("_shadow_track_seconds")) > 0.0,
		"a layout/hover change starts a short shadow-tracking window")
	await get_tree().create_timer(0.35).timeout
	_expect(_strength(middle) == 0.0, "the hovered top card has no overlap shadow")
	var neighbours: int = 0
	for card in cards:
		if card != middle and _strength(card) > 0.0:
			neighbours += 1
	_expect(neighbours >= 2, "the hovered card shadows its neighbours (%d)" % neighbours)
	hand.set_hovered(middle, false)

	# Leaving the hand clears the shadow surface for the field.
	middle.clear_edge_shadow()
	_expect(_strength(middle) == 0.0, "clear_edge_shadow removes the effect")

	print("[Shadow] %d checks | failures: %d" % [_checks, _fails])
	print("[Shadow] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
