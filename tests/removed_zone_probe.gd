extends Node
## REMOVED-FROM-THE-GAME probe: a second pile that is NOT the Break Zone.
##
## The distinction matters mechanically — nothing that looks in the Break Zone may find a card here — so the checks
## are about the two zones staying separate, not just about a node existing.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Removed] ok   %s" % what)
	else:
		_fails += 1
		print("[Removed] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var grave = _game.get("player_graveyard")
	var removed = _game.get("player_removed")
	var opp_removed = _game.get("opponent_removed")

	_expect(removed != null and opp_removed != null, "both sides have a Removed pile")
	_expect(removed != null and int(removed.get("zone")) == Card.Zone.REMOVED,
		"the Removed pile is in the REMOVED zone (%s)" % str(removed.get("zone")))
	_expect(grave != null and int(grave.get("zone")) == Card.Zone.GRAVEYARD,
		"and the Graveyard is still the GRAVEYARD zone (%s)" % str(grave.get("zone")))

	# --- a card removed from the game goes to the right pile, and only there ----------------------------
	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame
	var grave_before: int = grave.graveyard_cards.size()

	_game.set("_targets", [card])
	_game.remove_targets_from_game()

	_expect(removed.graveyard_cards.has(card), "the card is in the Removed pile")
	_expect(card.current_zone == Card.Zone.REMOVED,
		"its zone is REMOVED (got %d)" % card.current_zone)
	_expect(grave.graveyard_cards.size() == grave_before,
		"and the Break Zone did NOT gain it (%d -> %d)" % [grave_before, grave.graveyard_cards.size()])

	# --- the two piles are physically apart -------------------------------------------------------------
	var gap: float = removed.global_position.distance_to(grave.global_position)
	_expect(gap > 1.0, "the two piles are in different places on the board (%.2f m apart)" % gap)

	# --- SAME APPARENT SIZE AS A DECK CARD ---------------------------------------------------------------
	# The camera is orthographic, so distance from it changes NOTHING about apparent size: the only thing that makes
	# a pile look small is its container's scale. The Graveyard used to sit at 1.2 while the Deck sits at 1.4, which
	# is exactly the ~14% the user noticed.
	var deck = _game.get_node("Player/Deck")
	var deck_scale: float = deck.global_transform.basis.get_scale().x
	var grave_scale: float = grave.global_transform.basis.get_scale().x
	var removed_scale: float = removed.global_transform.basis.get_scale().x
	print("[Removed] deck %.2f · graveyard %.2f · removed %.2f" % [deck_scale, grave_scale, removed_scale])
	_expect(absf(grave_scale - deck_scale) < 0.01,
		"graveyard cards are the same size as deck cards (%.2f vs %.2f)" % [grave_scale, deck_scale])
	_expect(absf(removed_scale - deck_scale) < 0.01,
		"and so are removed cards (%.2f vs %.2f)" % [removed_scale, deck_scale])
	print("[Removed] graveyard at %s · removed at %s" % [
		str(grave.global_position), str(removed.global_position)])

	print("[Removed] %d checks | failures: %d" % [_checks, _fails])
	print("[Removed] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
