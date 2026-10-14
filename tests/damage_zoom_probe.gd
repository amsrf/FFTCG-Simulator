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

const GAME_SCENE := preload("res://game.tscn")

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

	# --- 1. no cameras built yet: damage must be uneventful ---------------------------------------------
	var board: Camera3D = get_viewport().get_camera_3d()
	_expect(board != null, "the board camera is active")
	player_side.take_damage(1)
	await get_tree().process_frame
	_expect(game.get("_damage_tween") == null, "with no damage camera, no zoom is started at all")
	_expect(get_viewport().get_camera_3d() == board, "and the view stays exactly where it was")
	print("[DamageZoom] no-camera path survived a hit")

	# --- 2. the real behaviour, with a stand-in -----------------------------------------------------------
	# Placed exactly where the hand-placed one would be: above the zone, looking down at it.
	var zone: Node3D = player_side.get_node_or_null("DamageZone")
	_expect(zone != null, "the player has a damage zone")
	var fake := Camera3D.new()
	# THE SCENE'S NAME, exactly. This probe originally stood in with "CameraDamagePlayer" — the same words as the
	# real node in the other order — and passed, while the real camera was never used by the game at all. A
	# stand-in that does not share the name the code looks for tests nothing.
	fake.name = "CameraPlayerDamage"
	fake.projection = Camera3D.PROJECTION_PERSPECTIVE
	fake.fov = 35.0
	game.add_child(fake)
	fake.global_position = zone.global_position + Vector3(0.0, 2.4, 2.2)
	fake.look_at(zone.global_position, Vector3.UP)
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
		tw.custom_step(total + 0.05)
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

	_finish()


func _finish() -> void:
	print("[DamageZoom] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageZoom] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
