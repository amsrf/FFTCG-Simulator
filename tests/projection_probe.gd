extends Node
## What switching the board camera from ORTHOGRAPHIC to PERSPECTIVE would actually do, measured.
##
## Under orthographic projection apparent size is independent of distance, so every zone is drawn at whatever size its
## scale says — which is why the zone table can put the hand at 1.1 and the field at 1.2 and both look deliberate.
## Under perspective it goes as 1/distance, so the real question is not "would it look more 3D" but "how far apart are
## the zones", because that distance ratio IS the size difference it would introduce.

const GAME_SCENE := preload("res://game.tscn")

var _cam: Camera3D = null
var _reference: float = 1.0

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	await get_tree().process_frame
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	_cam = game.get_node_or_null("Camera3D") as Camera3D
	if _cam == null:
		print("[Projection] no board camera found")
		get_tree().quit()
		return
	print("[Projection] board camera at %s | projection %d (0 = perspective, 1 = orthographic) | size %.3f" % [
		_cam.global_position, _cam.projection, _cam.size])

	var reference_card: Card = _first_of(game, "field", "front_cards")
	if reference_card == null:
		print("[Projection] nothing in the player's front row to measure against")
		get_tree().quit()
		return
	_reference = _cam.global_position.distance_to(reference_card.global_position)
	print("[Projection] reference = the player's front row, %.2f m away" % _reference)
	print("[Projection] --- if projection were switched to PERSPECTIVE, keeping the same framing at the reference: ---")

	_report("the player's hand", _first_of(game, "hand", "cards"))
	_report("the player's front row", _first_of(game, "field", "front_cards"))
	_report("the player's back row", _first_of(game, "field", "back_cards"))
	_report("the opponent's front row", _first_of(game, "field", "opponent_front_cards"))
	_report("the opponent's hand", _first_of(game, "opponent_hand", "cards"))
	_report("the deck", _first_of(game, "deck", "deck_cards"))
	_report("the stack", _first_of(game, "stack", "cards"))
	print("[Projection] RESULT: measured")
	get_tree().quit()

## First card in `owner_name`.`array_name`, or null. Untyped lookups: several of these nodes have no class_name.
func _first_of(game: Node, owner_name: String, array_name: String) -> Card:
	var holder: Variant = game.get(owner_name)
	if holder == null:
		return null
	var list: Variant = holder.get(array_name)
	if list == null or not (list is Array) or (list as Array).is_empty():
		return null
	return (list as Array)[0] as Card

func _report(label: String, card: Card) -> void:
	if card == null or not is_instance_valid(card):
		print("[Projection]   %-24s (nothing there)" % label)
		return
	var d: float = _cam.global_position.distance_to(card.global_position)
	# Apparent height under perspective is proportional to 1 / distance, so relative to the reference zone this IS the
	# size every card in that zone would change by.
	var factor: float = _reference / maxf(d, 0.001)
	var verdict: String = "no change"
	if factor > 1.02:
		verdict = "%.0f%% BIGGER" % ((factor - 1.0) * 100.0)
	elif factor < 0.98:
		verdict = "%.0f%% smaller" % ((1.0 - factor) * 100.0)
	print("[Projection]   %-24s %.2f m away  ->  %s" % [label, d, verdict])
