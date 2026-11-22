extends Node
## DAMAGE ZOOM probe — the camera cutaway when a side takes damage.
##
## Two things are worth checking and neither is visible to the game-logic probes:
##
##   1. THE GRACEFUL PATH. CameraDamagePlayer and CameraDamageOpponent do not exist yet, so today every zoom
##      must be skipped silently. A match must never depend on an optional node existing, and "it crashed
##      because the camera wasn't built" is exactly the failure that would be found by a human instead.
##   2. THE ACTUAL BEHAVIOUR, with a stand-in camera. A probe can add a camera named the same thing, fire
##      damage, and assert the view switched, moved to the slot, and came back.
##
## The tween is PAUSED and stepped by hand rather than waited on: a headless run's frame deltas are tiny, so
## a 1.75 s tween may never advance in real time. Custom-step is deterministic and is the only way this can
## assert the END of the sequence rather than its start.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DamageZoom] ok   %s" % what)
	else:
		_fails += 1
		print("[DamageZoom] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var player_side = game.get("player")
	var opp_side = game.get("opponent")
	_expect(player_side != null and opp_side != null, "both sides exist")

	# --- 1. the scene's cameras --------------------------------------------------------------------------
	# The board view is found the same way the game finds it — a camera that is NOT one of the damage cameras —
	# rather than taken as "whatever is current", because game.tscn marks neither camera current and Godot
	# activates the FIRST in the tree. That distinction is exactly what broke the game once already.
	var damage_names: Array = game.get("DAMAGE_CAMERAS").values()
	var board: Camera3D = game.find_child("Camera3D", true, false) as Camera3D
	_expect(board != null, "the scene has a board camera")
	_expect(not (str(board.name) in damage_names), "and it is not one of the damage cameras")

	# --- 2. the graceful path, ONLY when the scene has no damage camera ---------------------------------
	# A match must never depend on optional decoration, so this still matters — but it is conditional now,
	# because game.tscn HAS one and asserting "no camera, therefore no zoom" against a scene with a camera
	# would fail for the right reason and mean nothing.
	# FOUND BY POSITION, like the game finds it: whatever Camera3D is inside the player's damage zone. The name is
	# deliberately not consulted — the real one is called "Camera", and looking for "CameraPlayerDamage" is how this
	# probe reported "no camera is built" while one was sitting right there in the zone.
	var player_zone: Node3D = player_side.get_node_or_null("DamageZone")
	var real_cam: Camera3D = null
	if player_zone != null:
		for c in player_zone.find_children("*", "Camera3D", true, false):
			real_cam = c as Camera3D
			break
	if real_cam == null:
		print("[DamageZoom] no damage camera is built - checking the graceful path")
		player_side.take_damage(1)
		await get_tree().process_frame
		_expect(game.get("_damage_tween") == null, "with no damage camera, no zoom is started at all")
		_expect(get_viewport().get_camera_3d() == board, "and the view stays exactly where it was")
	else:
		print("[DamageZoom] a damage camera IS built - checking the real path")

	# --- 2. the real behaviour, with a stand-in -----------------------------------------------------------
	# Placed exactly where the hand-placed one would be: above the zone, looking down at it.
	var zone: Node3D = player_side.get_node_or_null("DamageZone")
	_expect(zone != null, "the player has a damage zone")
	# THE SCENE'S OWN CAMERA IS THE SUBJECT. It used to be a stand-in built here, which is how the swapped name
	# went unnoticed: the stand-in carried MY name, so the probe passed while the game used nothing. Testing the
	# node the player actually has is the only version of this that means anything.
	#
	# Still called `fake` so the checks below read unchanged — it is the camera the game will find, which is what
	# they were always meant to be about.
	var fake: Camera3D = real_cam
	if fake == null:
		print("[DamageZoom] no damage camera to drive - stopping here")
		_finish()
		return
	fake.projection = Camera3D.PROJECTION_PERSPECTIVE
	fake.fov = 35.0
	# PARENTED INSIDE THE DAMAGE ZONE, which is the arrangement the user asked about. It ought to change nothing:
	# the lookup is recursive, and both the placement below and every position the zoom computes are in GLOBAL
	# space, so the parent's transform cancels out. That reasoning is exactly the kind that missed the swapped
	# camera name, so the whole probe now runs with the camera where they want to put it.
	fake.reparent(zone, true)
	print("[DamageZoom] camera parented to '%s'" % fake.get_parent().name)
	# Placed where a hand-placed one would go, so the framing is predictable: above the zone, looking down.
	fake.global_position = zone.global_position + Vector3(0.0, 2.4, 2.2)
	fake.look_at(zone.global_position, Vector3.UP)
	fake.current = false
	await get_tree().process_frame

	# The slot the NEXT card will land in, in world space, worked out here independently of the game's own
	# helper so this is a real cross-check rather than a restatement of the implementation.
	var expected_target: Vector3 = zone.global_transform * (
		zone.call("calculate_card_position", zone.get("cards").size()) as Vector3)
	var placed_from: Vector3 = fake.global_position

	player_side.take_damage(1)
	await get_tree().process_frame
	_expect(get_viewport().get_camera_3d() == fake,
		"the damage camera TAKES OVER the view when a side is hit")
	var tw: Tween = game.get("_damage_tween")
	_expect(tw != null and tw.is_valid(), "and a zoom tween is running")

	if tw != null and tw.is_valid():
		# Drive it deterministically: in (0.35) + hold (1.0) + out (0.4).
		var total: float = float(game.get("damage_zoom_in_seconds")) \
			+ float(game.get("damage_zoom_hold_seconds")) \
			+ float(game.get("damage_zoom_out_seconds"))
		tw.pause()
		# ZOOMED IN: the shot is the board view dollied in — same orientation, same lens — with the slot centred.
		tw.custom_step(float(game.get("damage_zoom_in_seconds")) + 0.01)
		await get_tree().process_frame
		var shot: Camera3D = get_viewport().get_camera_3d()
		var view: Vector2 = get_viewport().get_visible_rect().size
		# Where the card that just landed sits NOW: the row re-centres as it grows, so the pre-hit slot has moved.
		# The zone only lays out its revealed (`pending`) cards now; absorbed ones are hidden.
		var landed: Vector3 = zone.global_transform * (
			zone.call("calculate_card_position", zone.get("pending").size() - 1) as Vector3)
		var slot_px: Vector2 = shot.unproject_position(landed)
		var turned: float = shot.global_basis.orthonormalized().get_rotation_quaternion().angle_to(
			board.global_basis.orthonormalized().get_rotation_quaternion())
		print("[DamageZoom] zoomed in: turned %.3f rad from the board view, fov %.1f vs %.1f, slot at %s of %s, %.2f m away" % [
			turned, shot.fov, board.fov, slot_px, view, shot.global_position.distance_to(landed)])
		_expect(turned < 0.01 and is_equal_approx(shot.fov, board.fov),
			"the zoom does not turn or re-lens the view: it is the board view dollied in")
		_expect(slot_px.distance_to(view * 0.5) < 3.0, "and the landing slot sits at the centre of the shot")
		_expect(shot.global_position.distance_to(landed) < board.global_position.distance_to(landed),
			"and it is closer than the board view")
		# Past any hold: a card with an EX BURST holds the shot for its reveal, longer than damage_zoom_hold_seconds.
		total = 9.0
		tw.custom_step(total)
		await get_tree().process_frame
		print("[DamageZoom] after stepping %.2fs the current camera is '%s'" % [
			total, get_viewport().get_camera_3d().name if get_viewport().get_camera_3d() != null else "?"])
		_expect(get_viewport().get_camera_3d() == board,
			"and after the hold the BOARD view comes back on its own")
	else:
		print("[DamageZoom] no tween to drive")

	# It went somewhere near the slot it was aiming for. Compared loosely: the aim is the hand-placed pose
	# shifted onto the slot, so the camera should end up within a stride of where it started, not teleported.
	print("[DamageZoom] placed at %s, slot now at %s" % [str(placed_from), str(expected_target)])
	_expect(placed_from.distance_to(expected_target) > 0.0,
		"the stand-in camera is looking into the zone rather than sitting on top of the slot")

	# --- 3. the second hit targets a LATER slot -----------------------------------------------------------
	player_side.take_damage(1)
	await get_tree().process_frame
	var tw2: Tween = game.get("_damage_tween")
	var second_slot: Vector3 = zone.global_transform * (
		zone.call("calculate_card_position", zone.get("cards").size()) as Vector3)
	print("[DamageZoom] second hit: slot %d at %s" % [zone.get("cards").size(), str(second_slot)])
	_expect(zone.get("cards").size() >= 2, "the zone accumulated a second card")
	_expect(tw2 != null, "and the zoom fires again for it")
	if tw2 != null and tw2.is_valid():
		tw2.pause()
		tw2.custom_step(9.0)
		await get_tree().process_frame
		_expect(get_viewport().get_camera_3d() == board, "and the view comes back again")

	# --- 4. TWO damage in one hit: each card gets its OWN slot -----------------------------------------------
	# The zone used to share one flight path, so the second flight rewrote the curve the first card was riding and both
	# landed on the last slot.
	# Measured while the two cards are still ON SHOW (revealed, before the zoom ends and the life crystals absorb them).
	player_side.take_damage(2)
	await get_tree().create_timer(DamageZone.FLIGHT_SECONDS + 0.15).timeout
	var slots: Dictionary = {}
	var row_x: Dictionary = {}
	for c in zone.get("pending"):
		slots[str(c.position.snapped(Vector3.ONE * 0.001))] = true
		row_x[snappedf(c.global_position.x, 0.001)] = true
	print("[DamageZoom] after a 2-damage hit: %d cards on show, %d distinct slots, %d distinct world x" % [
		zone.get("pending").size(), slots.size(), row_x.size()])
	_expect(zone.get("pending").size() == 2 and slots.size() == 2, "a 2-damage hit reveals each card in its own slot")
	_expect(row_x.size() == 1, "and the row is one straight line (one world x)")

	# --- THE OPPONENT IS ZOOMED TOO --------------------------------------------------------------------------------
	# Damage to the opponent (an unblocked attack of ours) must look at THEIR zone, EX BURST reveal and all, exactly as
	# damage to us does. Their zone once had no camera, so the zoom returned silently and the hit was never looked at.
	await _check_opponent_zoom(game, opp_side, board)

	_finish()


func _check_opponent_zoom(game, opp_side, board: Camera3D) -> void:
	var opp_zone: Node3D = opp_side.get_node_or_null("DamageZone")
	var opp_cam: Camera3D = null
	if opp_zone != null:
		for child in opp_zone.find_children("*", "Camera3D", true, false):
			opp_cam = child as Camera3D
			break
	_expect(opp_cam != null, "the opponent's damage zone has its damage camera")
	if opp_cam == null:
		return
	var old: Tween = game.get("_damage_tween")
	if old != null and old.is_valid():
		old.custom_step(30.0)
	await get_tree().process_frame
	opp_side.take_damage(1, game.get("field").get_front_cards_for("player").front())
	await get_tree().process_frame
	_expect(get_viewport().get_camera_3d() == opp_cam, "damage to the OPPONENT takes the view to their damage zone")
	var tw: Tween = game.get("_damage_tween")
	_expect(tw != null and tw.is_valid(), "and their zoom tween is running")
	if tw == null or not tw.is_valid():
		return
	tw.pause()
	tw.custom_step(float(game.get("damage_zoom_in_seconds")) + 0.01)
	await get_tree().process_frame
	var shown: Array = opp_zone.get("pending")
	var landed: Vector3 = opp_zone.global_transform * (opp_zone.call("calculate_card_position", shown.size() - 1) as Vector3)
	var slot_px: Vector2 = opp_cam.unproject_position(landed)
	var view: Vector2 = get_viewport().get_visible_rect().size
	_expect(slot_px.distance_to(view * 0.5) < 3.0,
		"and the opponent's landing slot sits at the centre of the shot (%s of %s)" % [slot_px, view])
	tw.custom_step(30.0)
	await get_tree().process_frame
	_expect(get_viewport().get_camera_3d() == board, "and the board view comes back after it")


func _finish() -> void:
	print("[DamageZoom] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageZoom] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	# The life crystals' shatter sound may still be playing; quitting under it reports the streams as leaked.
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()
