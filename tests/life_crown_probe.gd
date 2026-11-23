extends Node
## LIFE CROWN probe (scripts/ui/life_crown.gd): the Chaos crown in the hand-Backup band.
##
##   1. Built: 7 crystals, all alive, visible for seat 1.
##   2. Placed ON THE BOARD: on the stone strip below the wood, leaning back toward the field, centred and inside
##      the band (below the local field cards, above the resting hand).
##   3. Real hits (PlayerSide.take_damage, the path every damage source uses) break crystals in the order
##      outer-left, outer-right, next-left ... centre last, and only once the damage zoom has handed the view back.
##   4. Each break spawns a burst that frees itself; healing (damage zone shrinking) restores the last broken.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const BURST := preload("res://scripts/vfx/life_crystal_burst.gd")
const GROUNDS := preload("res://scripts/core/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[LifeCrown] ok   %s" % what)
	else:
		_fails += 1
		print("[LifeCrown] FAIL %s" % what)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _bursts(crown: Node) -> int:
	var n := 0
	for c in crown.get_children():
		if c.get_script() == BURST:
			n += 1
	return n

func _alive(crown) -> Array:
	var out: Array = []
	for i in range(7):
		out.append(1 if crown.crystal_visible(i) else 0)
	return out

func _ready() -> void:
	# The CLEAN ground: a mock opponent that never attacks, so the only damage is the probe's own.
	MatchSetup.config = GROUNDS.config("clean")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await _wait(0.5)
	var crown = game.get("life_crown")
	_expect(crown != null, "the game built a life crown")
	if crown == null:
		_finish()
		return
	_expect(crown.visible, "it is shown for seat 1 (Chaos)")
	_expect(crown.lives_shown() == 7, "7 crystals alive at the start (got %d)" % crown.lives_shown())

	# --- the layout is the one source of truth: game.tscn's station nodes must match assets/board/layout.json -----
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/board/layout.json"))
	var node_for := {"deck": "%s/Deck", "graveyard": "%s/Graveyard", "removed": "%s/Removed"}
	var mismatched: Array = []
	for who in ["player", "opponent"]:
		var side_name: String = "Player" if who == "player" else "Opponent"
		var st: Dictionary = layout["stations"][who]
		for key in node_for:
			var n: Node3D = game.get_node(node_for[key] % side_name)
			var want := Vector3(st[key][0], st[key][1], st[key][2])
			if n.position.distance_to(want) > 0.002:
				mismatched.append("%s %s %s != %s" % [who, key, n.position, want])
		for pair in [["forward", "LocalForward" if who == "player" else "OpponentForward"], ["cancel", "LocalCancel" if who == "player" else "OpponentCancel"]]:
			var b: Node3D = game.get_node("Assistant/ButtonStations/" + pair[1])
			var want_b := Vector3(st[pair[0]][0], st[pair[0]][1], st[pair[0]][2])
			if b.position.distance_to(want_b) > 0.002:
				mismatched.append("%s %s %s != %s" % [who, pair[0], b.position, want_b])
	_expect(mismatched.is_empty(), "game.tscn's decks, pits and button stations match assets/board/layout.json %s" % [mismatched])

	# --- placement ---------------------------------------------------------------------------------------
	var cam: Camera3D = game.board_camera()
	_expect(cam != null, "the board camera is known")
	var view: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = crown.screen_rect()
	print("[LifeCrown] viewport %s, crown rect %s (centre %.3f, %.3f of the view, height %.3f)" % [
		view, rect, rect.get_center().x / view.x, rect.get_center().y / view.y, rect.size.y / view.y])
	_expect(absf(rect.get_center().x / view.x - 0.5) < 0.01, "centred horizontally")
	_expect(rect.size.y / view.y > 0.08 and rect.size.y / view.y < 0.16, "0.08-0.16 of the viewport tall (inside the ~168 px band)")
	var field_bottom := -INF
	for card in game.field.get_all_cards():
		if card.controller != "player":
			continue
		field_bottom = maxf(field_bottom, cam.unproject_position(card.get_global_face_centre()).y)
	var hand_top := INF
	for card in game.player.hand.cards:
		hand_top = minf(hand_top, cam.unproject_position(card.get_global_face_centre()).y)
	print("[LifeCrown] lowest local field card centre y %.0f, highest hand card centre y %.0f" % [field_bottom, hand_top])
	if field_bottom > -INF:
		_expect(rect.position.y > field_bottom, "top edge below the local field cards' centres")
	if hand_top < INF:
		_expect(rect.end.y < hand_top + 40.0, "bottom edge above the hand row")
	# ON THE BOARD: every crystal's foot is on the stone strip below the wood (world z < -1.8), in front of the
	# hand nodes' depth from the camera, and each collar reaches below the lowest rock under it.
	for i in range(7):
		var foot: Vector3 = crown.crystal_foot(i)
		var tip: Vector3 = crown.crystal_tip(i)
		if foot.z > -1.8 or foot.y > 0.4 or tip.z <= foot.z:
			_expect(false, "crystal %d stands on the stones and leans toward the field (foot %s tip %s)" % [i, foot, tip])
	_expect(true, "every crystal stands on the stone strip, leaning back toward the field")
	var tip_px: float = cam.unproject_position(crown.crystal_tip(3)).y - cam.unproject_position(crown.crystal_foot(3)).y
	print("[LifeCrown] centre crystal on screen: %.0f px tall" % -tip_px)
	_expect(-tip_px > 60.0 and -tip_px < 120.0, "the centre crystal is 60-120 px tall on screen")

	# --- real hits ---------------------------------------------------------------------------------------
	game.player.take_damage(1)
	await _wait(0.6)
	_expect(crown.lives_shown() == 7, "still 7 while the zoom is on the damage card")
	var dz: DamageZone = game.player.damage_zone
	var hit_card: Card = dz.cards[dz.cards.size() - 1]
	_expect(hit_card.visible and dz.pending.has(hit_card), "the damage card is on show (revealed) during the zoom")
	var rest_scale: float = hit_card.scale.x
	await game.damage_zoom_finished
	await _wait(DamageZone.ABSORB_SECONDS * 0.5)
	_expect(crown.crystal_visible(0) and hit_card.visible and hit_card.scale.x < rest_scale * 0.9,
		"once the view is back the card flies into the crystal, shrinking (scale %.2f), before it breaks (crystal %s, card visible %s, rest %.2f)" % [hit_card.scale.x, crown.crystal_visible(0), hit_card.visible, rest_scale])
	await _wait(DamageZone.ABSORB_SECONDS * 0.5 + crown.crack_seconds + 0.15)
	_expect(not hit_card.visible and dz.cards.has(hit_card) and dz.pending.is_empty(),
		"then the card is gone from view but still in the damage zone")
	_expect(_alive(crown) == [0, 1, 1, 1, 1, 1, 1], "hit 1 breaks the outermost LEFT crystal (%s)" % [_alive(crown)])
	_expect(_bursts(crown) == 1, "and spawns one burst")
	game.player.take_damage(2)
	await game.damage_zoom_finished
	await _wait(DamageZone.ABSORB_SECONDS + crown.crack_seconds + crown.stagger_seconds + 0.15)
	_expect(_alive(crown) == [0, 1, 1, 1, 1, 1, 0] or _alive(crown) == [0, 0, 1, 1, 1, 1, 0],
		"hit 2 breaks the outermost RIGHT next (%s)" % [_alive(crown)])
	await _wait(0.3)
	_expect(_alive(crown) == [0, 0, 1, 1, 1, 1, 0], "a 2-damage hit takes right then next-left (%s)" % [_alive(crown)])
	await _wait(1.2)
	_expect(_bursts(crown) == 0, "every burst freed itself")
	game.player.take_damage(3)
	await game.damage_zoom_finished
	await _wait(DamageZone.ABSORB_SECONDS + crown.crack_seconds + crown.stagger_seconds * 2 + 0.3)
	_expect(_alive(crown) == [0, 0, 0, 1, 0, 0, 0], "six hits leave only the CENTRE crystal (%s)" % [_alive(crown)])

	# --- the opponent's (Cosmos) crystals on the top edge -----------------------------------------------
	var opp = game.get("opponent_life_crown")
	_expect(opp != null and opp.style == "cosmos" and opp.edge == "top", "the opponent has Cosmos crystals on the top edge")
	if opp != null:
		_expect(opp.lives_shown() == 7, "7 Cosmos crystals alive")
		var all_top := true
		for i in range(7):
			all_top = all_top and opp.crystal_foot(i).z > 2.2 and opp.crystal_foot(i).z < 2.45
		_expect(all_top, "every Cosmos crystal stands on the far edge of the wood (2.2 < z < 2.45)")
		var otip: float = cam.unproject_position(opp.crystal_foot(3)).y - cam.unproject_position(opp.crystal_tip(3)).y
		print("[LifeCrown] Cosmos centre crystal on screen: %.0f px tall (local: %.0f)" % [otip, -tip_px])
		_expect(absf(otip + tip_px) < 12.0, "the far centre crystal is as tall on screen as the near one (within 12 px)")
		_expect(opp.crystal_foot(0).x < 0.0, "Cosmos index 0 is the OPPONENT's left (world -x, screen-right)")
		var orect: Rect2 = opp.screen_rect()
		print("[LifeCrown] Cosmos rect %s" % orect)
		_expect(orect.position.y > 40.0 and orect.end.y < 170.0, "the Cosmos crystals sit between the opponent's hand and field")
		game.opponent.take_damage(1)
		await game.damage_zoom_finished
		await _wait(DamageZone.ABSORB_SECONDS + opp.crack_seconds + 0.15)
		_expect(not opp.crystal_visible(0) and opp.lives_shown() == 6, "an opponent hit breaks THEIR leftmost crystal")

	# --- click to view ---------------------------------------------------------------------------------------
	var hidden_all := true
	for c in game.player.damage_zone.cards:
		hidden_all = hidden_all and not c.visible
	_expect(hidden_all, "no damage card is drawn in the zone any more (%d cards, all hidden)" % game.player.damage_zone.cards.size())
	var before: int = game.get_child_count()
	crown.open_damage_view()
	await _wait(0.2)
	var window: Node = null
	for c in game.get_children():
		if c.has_method("open_view"):
			window = c
	_expect(game.get_child_count() > before and window != null, "clicking the crystals opens the Damage Zone viewer")
	if window != null:
		window.queue_free()
	_expect(crown.get_node_or_null("ClickArea") != null, "the crystal row has a click area")

	# --- heal ------------------------------------------------------------------------------------------
	var zone = game.player.damage_zone
	var healed = zone.cards.pop_back()
	crown.sync(false)
	_expect(_alive(crown) == [0, 0, 0, 1, 1, 0, 0], "a healed point restores the last broken crystal, inner right (%s)" % [_alive(crown)])
	if healed != null:
		zone.cards.append(healed)
	_finish()

func _finish() -> void:
	# Let the shatter sounds finish, or the exit reports their streams as leaked.
	await _wait(1.5)
	print("[LifeCrown] RESULT: %s (%d checks, %d failed)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
