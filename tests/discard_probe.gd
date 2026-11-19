extends Node
## DISCARD probe — the AI side of "your opponent discards 1 card from their hand".
##
## The rule is that the DISCARDER chooses, so the seam asks the side that owns the hand. The local player's branch
## opens the hand-selection UI and cannot be driven headlessly; what is checked here is the other branch — an AI
## asked to discard — plus the empty-hand guard, which is the case that would otherwise crash mid-effect.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DiscardProbe] ok   %s" % what)
	else:
		_fails += 1
		print("[DiscardProbe] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var ai_hand = _game.get("opponent_hand")
	var ai_grave = _game.get("opponent_graveyard")
	var before_hand: int = ai_hand.cards.size()
	var before_grave: int = ai_grave.graveyard_cards.size()
	print("[DiscardProbe] AI hand %d, graveyard %d" % [before_hand, before_grave])

	var was_face_down: bool = ai_hand.cards.all(func(c): return not c.revealed)
	var t0: int = Time.get_ticks_msec()
	await _game.discard_from(2, 1)
	var gone: Card = ai_grave.graveyard_cards.back() if ai_grave.graveyard_cards.size() > before_grave else null
	_expect(was_face_down, "the AI's hand cards are face down before the discard")
	# A discard is public: the card turns face-up (yawing out of the hand) before it flies into the pit.
	var revealed_mid := false
	# Once it leaves for the pit (reparented into it) it only MOVES: its orientation must not change.
	var flight_q = null
	var max_turn := 0.0
	var shown_upside_down = null   # read while it is held face-up, before it leaves for the pit
	var cam: Camera3D = get_viewport().get_camera_3d()
	while not Vfx.is_idle():
		if gone != null and gone.revealed and gone.visible:
			revealed_mid = true
			if gone.get_parent() != ai_grave and cam != null:
				shown_upside_down = ai_grave.is_upside_down_on_screen(gone.global_basis.orthonormalized(),
					gone.global_position, cam)
			if gone.get_parent() == ai_grave:
				var q: Quaternion = gone.global_basis.get_rotation_quaternion()
				if flight_q == null:
					flight_q = q
				else:
					max_turn = maxf(max_turn, rad_to_deg((flight_q as Quaternion).angle_to(q)))
		await get_tree().process_frame
	var took: float = (Time.get_ticks_msec() - t0) / 1000.0
	var gy = ai_grave
	var reveal_min: float = gy.discard_reveal_flip_seconds + gy.discard_reveal_hold_seconds
	_expect(gone != null and gone.revealed, "the discarded card is face-up (revealed) once it is in the pile")
	_expect(took >= reveal_min, "the reveal flip + hold played before the intake (%.2fs >= %.2fs)" % [took, reveal_min])
	_expect(revealed_mid, "the card was seen face-up while still visible, before the pit swallowed it")
	_expect(shown_upside_down == false,
		"the revealed card reads the RIGHT WAY UP for the player (its top points up the screen)")
	_expect(flight_q != null and max_turn < 1.0,
		"after the reveal it moves to the pit without turning (turned %.1f° at most)" % max_turn)
	_expect(ai_hand.cards.size() == before_hand - 1,
		"the AI's hand lost exactly one card (%d -> %d)" % [before_hand, ai_hand.cards.size()])
	_expect(ai_grave.graveyard_cards.size() == before_grave + 1,
		"and it went to the AI's graveyard (%d -> %d)" % [before_grave, ai_grave.graveyard_cards.size()])

	# --- DISCARD 2: chosen first, then revealed and flown TOGETHER, a short stagger apart --------------------------
	var grave_before2: int = ai_grave.graveyard_cards.size()
	var hand_before2: int = ai_hand.cards.size()
	var t2: int = Time.get_ticks_msec()
	var two: int = await _game.discard_from(2, 2)
	var gone2: Array = ai_grave.graveyard_cards.slice(grave_before2)
	_expect(two == 2 and gone2.size() == 2 and ai_hand.cards.size() == hand_before2 - 2,
		"discard 2: two different cards leave the hand and reach the pile (%d)" % gone2.size())
	var first_up := [-1, -1]
	var both_up_at_once := false
	var apart_px := 0.0
	var upright2 := true
	var cam2: Camera3D = get_viewport().get_camera_3d()
	while not Vfx.is_idle():
		var now: int = Time.get_ticks_msec() - t2
		var up := 0
		for i in gone2.size():
			var c: Card = gone2[i]
			if c.revealed and c.visible and c.get_parent() != ai_grave:
				up += 1
				if first_up[i] < 0:
					first_up[i] = now
				if cam2 != null and ai_grave.is_upside_down_on_screen(c.global_basis.orthonormalized(), c.global_position, cam2):
					upright2 = false
		if up == 2 and cam2 != null:
			both_up_at_once = true
			apart_px = maxf(apart_px, cam2.unproject_position(gone2[0].global_position).distance_to(
				cam2.unproject_position(gone2[1].global_position)))
		await get_tree().process_frame
	var took2: float = (Time.get_ticks_msec() - t2) / 1000.0
	var g = ai_grave
	var one_card: float = g.discard_reveal_flip_seconds + g.discard_reveal_hold_seconds + g.discard_seconds \
		+ g.intake_hover_seconds + g.intake_sink_seconds
	_expect(both_up_at_once, "the two are revealed CONCURRENTLY: both face-up on screen at the same time")
	_expect(first_up[0] >= 0 and first_up[1] > first_up[0],
		"with a small delay between them (%d ms then %d ms)" % [first_up[0], first_up[1]])
	_expect(apart_px > 120.0, "held side by side, not on top of each other (%.0f px apart)" % apart_px)
	_expect(upright2, "both read the right way up")
	_expect(took2 < one_card * 2.0 - 0.2,
		"the whole discard takes %.2f s, well under two cards played one after the other (%.2f s)" % [took2, one_card * 2.0])

	# --- the human cannot pick the same card twice: only the cards still on offer are choosable --------------------
	var my_hand = _game.get("hand")
	if my_hand.cards.size() >= 2:
		my_hand.choose_card_allowed = [my_hand.cards[0]]
		_expect(my_hand._choosable(my_hand.cards[0]) and not my_hand._choosable(my_hand.cards[1]),
			"while choosing, a card already picked is not choosable again")
		my_hand.end_choose_card()
		_expect(my_hand.choose_card_allowed.is_empty(), "and the restriction ends with the choice")

	# --- the AI keeps its cheapest card, so the expensive ones should survive ---------------------------
	print("[DiscardProbe] AI hand now: %s" % str(_names(ai_hand.cards)))

	# --- empty hand must not crash or loop -------------------------------------------------------------
	for card in ai_hand.cards.duplicate():
		ai_hand.discard_card(card)
	_expect(ai_hand.cards.is_empty(), "hand emptied for the guard test")
	await _game.discard_from(2, 3)
	_expect(ai_hand.cards.is_empty(), "asking an empty hand to discard three times is a no-op, not a crash")

	# --- the effects exist -----------------------------------------------------------------------------------
	_expect(FileAccess.file_exists("res://assets/effects/card_33.gd")
		and FileAccess.file_exists("res://assets/effects/card_51.gd"),
		"cards 33 (Argath) and 51 (Nooj) carry the effect in code")

	_finish()


func _names(cards: Array) -> String:
	var out: Array = []
	for c in cards:
		out.append(c.card_name)
	return ", ".join(out)


func _finish() -> void:
	print("[DiscardProbe] %d checks | failures: %d" % [_checks, _fails])
	print("[DiscardProbe] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
