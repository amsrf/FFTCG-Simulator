extends Node
## REMOVED-FROM-THE-GAME probe: a second pile that is NOT the Break Zone.
##
## The distinction matters mechanically — nothing that looks in the Break Zone may find a card here — so the checks
## are about the two zones staying separate, not just about a node existing.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

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
	# They are PITS on a diagonal beside the deck: apart by more than their two radii, so the two never overlap.
	var radii: float = float(grave.get("pit_radius")) + float(removed.get("pit_radius"))
	_expect(gap > radii, "the two pits are in different places on the board (%.2f m apart, radii %.2f)" % [gap, radii])

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

	# --- INSPECTABLE WITH EITHER BUTTON ------------------------------------------------------------------
	# The pile window is a new child of Game, so "did it open" is a child count. Both buttons must do it: left is the
	# normal click, and right-click on a PILE card is special-cased in card_area_3d.gd because right-click elsewhere
	# means "focus", not "open".
	var area = card.get_node("CardArea3D")

	var before_left: int = _game.get_child_count()
	card._on_card_area_3d_card_grabbed(null)
	await get_tree().process_frame
	_expect(_game.get_child_count() > before_left, "LEFT click on a removed card opens the zone window")
	for child in _game.get_children():
		if child is CanvasLayer and child.get_child_count() > 0:
			child.queue_free()
	await get_tree().process_frame

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	var before_right: int = _game.get_child_count()
	area._on_input_event(null, right, Vector3.ZERO, Vector3.UP, 0)
	await get_tree().process_frame
	_expect(_game.get_child_count() > before_right, "RIGHT click on a removed card opens it too")

	await _check_pits(grave, removed)

	print("[Removed] %d checks | failures: %d" % [_checks, _fails])
	print("[Removed] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


## THE PITS (scripts/game/pit.gd): both piles are drawn as pits, BESIDE THE DECK TO ITS RIGHT on screen (Break Zone
## first, then Removed), mirrored for the opponent; a card in a pit is hidden; a discard is pulled in and flares it;
## clicking the pit opens the zone window.
func _check_pits(grave: Node3D, removed: Node3D) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var g_pit = grave.get("pit")
	var r_pit = removed.get("pit")
	_expect(g_pit != null and r_pit != null, "both piles have a pit")
	if g_pit == null or r_pit == null or cam == null:
		return
	_expect(g_pit.get("kind") == "graveyard" and r_pit.get("kind") == "removed",
		"the Break Zone pit is the blue one, the Removed pit the purple one")
	for side in [["Player", false], ["Opponent", true]]:
		var deck: Vector2 = cam.unproject_position(_game.get_node("%s/Deck" % side[0]).global_position)
		var g_node: Node3D = _game.get_node("%s/Graveyard" % side[0])
		var r_node: Node3D = _game.get_node("%s/Removed" % side[0])
		var g: Vector2 = cam.unproject_position(g_node.global_position)
		var r: Vector2 = cam.unproject_position(r_node.global_position)
		# From that player's seat: screen right/down for the player, screen left/up for the opponent.
		var dir: float = -1.0 if side[1] else 1.0
		var g_r_px: float = _radius_px(cam, g_node.get("pit"))
		var r_r_px: float = _radius_px(cam, r_node.get("pit"))
		print("[Removed] %s: deck (%.0f, %.0f), Break Zone pit (%.0f, %.0f) r %.0f px, Removed pit (%.0f, %.0f) r %.0f px"
			% [side[0], deck.x, deck.y, g.x, g.y, g_r_px, r.x, r.y, r_r_px])
		_expect((g.x - deck.x) * dir > 0.0 and (g.y - deck.y) * dir > 0.0,
			"%s: the Break Zone pit is right of the deck and lower, from that seat" % side[0])
		_expect((r.x - g.x) * dir > 0.0 and (r.y - g.y) * dir < 0.0,
			"%s: the Removed pit is up and to the right of it - a diagonal, as in Master Duel" % side[0])
		_expect(r_r_px < g_r_px * 0.9, "%s: the Removed pit is the smaller one (%.0f vs %.0f px)" % [side[0], r_r_px, g_r_px])
		_expect(g.distance_to(r) > g_r_px + r_r_px, "%s: the two pits do not overlap" % side[0])
		_expect(g.distance_to(deck) > g_r_px, "%s: the Break Zone pit does not sit on the deck" % side[0])

	# Every card resting in a pit is hidden.
	var shown := 0
	for pile in [grave, removed]:
		for c in pile.graveyard_cards:
			if is_instance_valid(c) and c.get_parent() == pile and c.visible:
				shown += 1
	_expect(shown == 0, "no card resting in a pit is drawn (%d shown)" % shown)

	# A discard is pulled in: it lands in the rules list at once, ends hidden, flares the pit, and is not left white.
	var hand = _game.get_node("Player/Hand")
	if hand.cards.is_empty():
		_expect(false, "the debug hand has a card to discard")
		return
	var card: Card = hand.cards[0]
	var flares: int = int(g_pit.get("flare_count"))
	hand.discard_card(card)
	_expect(grave.graveyard_cards.has(card), "a discarded card is in the Break Zone at once")
	await get_tree().create_timer(0.3).timeout
	_expect(card.visible, "while it flies to the pit it is drawn")
	await Vfx.idle()
	await get_tree().process_frame
	var white = (card.get("mat") as ShaderMaterial).get_shader_parameter("whiteout")
	_expect(not card.visible and card.get_parent() == grave, "once in, it is hidden in the pit")
	_expect(int(g_pit.get("flare_count")) == flares + 1, "the pit flared as it went in")
	_expect(white is float and is_zero_approx(white), "and the white wash is cleared for when it comes back out")

	# The pit is the click target now: it opens the zone window.
	var before: int = _game.get_child_count()
	g_pit.emit_signal("clicked")
	await get_tree().process_frame
	_expect(_game.get_child_count() > before, "clicking the Break Zone pit opens the zone window")


func _radius_px(cam: Camera3D, pit: Node3D) -> float:
	var r: float = float(pit.get("radius"))
	return cam.unproject_position(pit.global_position + Vector3(r, 0, 0)).distance_to(
		cam.unproject_position(pit.global_position))
