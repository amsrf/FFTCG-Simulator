extends Node
## FROZEN STATUS VISUAL probe.
##
## The rules probe (freeze_probe.gd) covers the Active-Phase clock. This one
## covers the presentation: applying "frozen" should build a card-space additive
## quad from the original frost masks, and consuming the status should hide it.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[FrozenOverlay] ok   %s" % what)
	else:
		_fails += 1
		print("[FrozenOverlay] FAIL %s" % what)


func _spread(card: Card) -> float:
	var overlay: MeshInstance3D = card.overlays.frozen_overlay
	if overlay == null or overlay.material_override == null:
		return -1.0
	return float(overlay.material_override.get_shader_parameter("spread"))


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	_field.play_card(card, false, false)
	card.status_effects.clear()
	await get_tree().process_frame

	_expect(card.current_zone == Card.Zone.FIELD, "the test card is on the field")
	_expect(card.overlays.frozen_overlay == null,
		"an unfrozen card pays nothing for the overlay")

	card.add_status_effect("frozen", 1)
	await get_tree().process_frame
	var overlay: MeshInstance3D = card.overlays.frozen_overlay
	_expect(card.is_frozen() and overlay != null and overlay.visible,
		"freezing the card creates and shows the frost overlay")
	_expect(overlay != null and overlay.get_parent() == card.get_node("HandMesh"),
		"the overlay follows the visible card mesh")
	var material: ShaderMaterial = overlay.material_override if overlay != null else null
	_expect(material != null and material.shader != null,
		"the overlay has its additive frost shader")
	_expect(material != null
		and material.get_shader_parameter("frost_cracks") is Texture2D
		and material.get_shader_parameter("frost_outline") is Texture2D,
		"both original frost masks are bound")

	_expect(_spread(card) < 0.999,
		"the frost begins as a growing front, not the final mask")
	await get_tree().create_timer(1.85).timeout
	_expect(_spread(card) > 0.999,
		"and reaches the full mask after the spread animation")

	# Direct mutations elsewhere in the codebase use refresh_status_visuals().
	card.status_effects.erase("frozen")
	card.refresh_status_visuals()
	_expect(overlay != null and overlay.visible and _spread(card) > 0.001,
		"removing Freeze starts the frost receding")
	await get_tree().create_timer(1.85).timeout
	_expect(overlay != null and not overlay.visible and _spread(card) <= 0.001,
		"and the overlay hides once the recede finishes")

	card.add_status_effect("frozen", 1)
	await get_tree().create_timer(1.85).timeout
	_expect(overlay != null and overlay.visible and _spread(card) > 0.999,
		"re-freezing grows the same overlay again")

	# The Active Phase consumes Freeze; the visual must go with it.
	_field.untap_cards_for("player")
	await get_tree().create_timer(1.85).timeout
	_expect(not card.is_frozen(), "the Active Phase consumes the Freeze status")
	_expect(overlay != null and not overlay.visible,
		"and the Active Phase hides the frost overlay too")

	print("[FrozenOverlay] %d checks | failures: %d" % [_checks, _fails])
	print("[FrozenOverlay] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
