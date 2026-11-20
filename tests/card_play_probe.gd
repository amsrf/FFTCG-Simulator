extends Node
## HOW A CHARACTER IS PLAYED (card_hologram.gd; ~/Desktop/Clips/play frames 148-202 at 60 fps).
##
## Casts a cheap Forward and then a cost-8+ one through the real payment path and checks the beats: a hologram stand-in
## where the card was, the line drawing crossing to hover ABOVE the slot while that is still dissolving, the DRAWING
## falling onto the slot (accelerating) and flooding white only on contact, the card hidden until then and revealed
## already at rest, no dust, and a camera jolt for every card (harder for a big one) that returns the camera EXACTLY. Also: field cards are thick,
## everywhere else thin.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const HOLOGRAM := preload("res://scripts/cards/card_hologram.gd")
const CARD_EDGE := preload("res://scripts/cards/card_edge.gd")
const CHEAP := 25   # Squire, cost 2, vanilla
const BIG := 6      # Garland, Brave only; its cost is raised to 9 here

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _hand = null
var _assistant = null


const FIELD_SHADOW := preload("res://scripts/cards/card_field_shadow.gd")

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CardPlay] ok   %s" % what)
	else:
		_fails += 1
		print("[CardPlay] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [CHEAP, BIG],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_hand = _game.get("hand")
	_assistant = _game.get("assistant")
	var camera: Camera3D = get_viewport().get_camera_3d()

	var cheap: Card = null
	var big: Card = null
	for c in _hand.cards:
		if c.id == CHEAP:
			cheap = c
		elif c.id == BIG:
			big = c
	_expect(cheap != null and big != null, "both test Forwards are in hand")
	_expect(absf(CARD_EDGE.thickness_of(cheap) - CARD_EDGE.CARD_EDGE_THICKNESS) < 0.0001,
		"a hand card is card-thin (%.3f)" % CARD_EDGE.thickness_of(cheap))
	big.cost = 9
	_expect(_field.slam_tier(cheap) == 0 and _field.slam_tier(big) == 2, "the two land in slam tiers 0 and 2")

	# ---- the cheap card -------------------------------------------------------------------------------------------
	var camera_home: Vector3 = camera.global_position
	var source_position: Vector3 = cheap.global_position
	var t0: int = Time.get_ticks_msec()
	_hand.charge(cheap)
	await get_tree().process_frame
	_assistant.on_charge_complete()
	await get_tree().create_timer(0.06).timeout
	var ghost: MeshInstance3D = cheap.hologram.source_ghost
	_expect(ghost != null and is_instance_valid(ghost), "the cast card turns into a hologram stand-in")
	if ghost != null and is_instance_valid(ghost):
		_expect(ghost.global_position.distance_to(source_position) < 0.3,
			"which stays where the card was cast (%.2f m away)" % ghost.global_position.distance_to(source_position))
		var holo_mat := ghost.get_surface_override_material(0) as ShaderMaterial
		_expect(float(holo_mat.get_shader_parameter("holo")) > 0.5, "and its art has drained into the hologram")
	_expect(not cheap.visible, "the real card is hidden while it leaves")

	# The drawing leaves from where the card was cast, while the hologram is still going.
	await _wait_for(func() -> bool: return cheap.hologram.blueprint != null, 1.0)
	var lines: MeshInstance3D = cheap.hologram.blueprint
	_expect(lines != null and is_instance_valid(lines), "a line drawing of the card appears")
	_expect(ghost != null and is_instance_valid(ghost), "while the hologram is still dissolving (no dead beat)")
	_expect(cheap.hologram.phase == "travel", "it is travelling")
	_expect(cheap.current_zone == Card.Zone.FIELD and _field.front_cards.has(cheap), "the rules have it on the field")
	_expect(absf(CARD_EDGE.thickness_of(cheap) - CARD_EDGE.FIELD_THICKNESS) < 0.0001,
		"a card joining the field is already a solid piece (%.3f)" % CARD_EDGE.thickness_of(cheap))
	var slot: Vector3 = cheap.hand_mesh.global_position
	if lines != null and is_instance_valid(lines):
		_expect(lines.global_position.distance_to(source_position) < 0.25,
			"it starts where the card was cast (%.2f m from it)" % lines.global_position.distance_to(source_position))
		var path: Array = []
		while is_instance_valid(lines) and cheap.hologram.phase == "travel":
			path.append(lines.global_position)
			await get_tree().process_frame
		var screen_moved: float = 0.0
		if path.size() > 1:
			screen_moved = camera.unproject_position(path[0]).distance_to(camera.unproject_position(path[-1]))
		_expect(path.size() > 5 and screen_moved > 150.0,
			"and visibly CROSSES the board to the slot (%d frames, %.0f px on screen)" % [path.size(), screen_moved])
	_expect(not cheap.visible, "the card is still hidden")

	await _wait_for(func() -> bool: return cheap.hologram.phase == "hold", 1.0)
	if lines != null and is_instance_valid(lines):
		var over: Vector3 = lines.global_position - slot
		_expect(Vector2(over.x, over.z).length() < 0.01 and absf(over.y - HOLOGRAM.SLAM_HEIGHT) < 0.01,
			"it hovers right over the slot (%.2f m up)" % over.y)
	_expect(not cheap.visible, "the card is hidden through the hold")
	# The DRAWING falls (not the card), slowly at first and then all at once, and fills white only on the floor.
	await _wait_for(func() -> bool: return cheap.hologram.phase == "drop", 1.0)
	_expect(not cheap.visible, "the drawing falls while the card is still hidden")
	var fall: Array = []   # [ms, height above the face]
	var fall_t0: int = Time.get_ticks_msec()
	while lines != null and is_instance_valid(lines) and cheap.hologram.phase == "drop":
		fall.append([Time.get_ticks_msec() - fall_t0, lines.global_position.y - slot.y])
		var lines_mat := lines.material_override as ShaderMaterial
		var fill_now = lines_mat.get_shader_parameter("fill")
		if fill_now is float and fill_now > 0.01:
			_expect(false, "the drawing is not white yet while it falls")
			break
		await get_tree().process_frame
	var fall_ms: int = Time.get_ticks_msec() - fall_t0
	_expect(fall_ms > 50 and fall_ms < 220, "the fall is quick: %d ms (ref ~1-2 frames, ours 0.10 s)" % fall_ms)
	var half_drop: float = -1.0
	for sample in fall:
		if float(sample[0]) <= fall_ms * 0.5:
			half_drop = 1.0 - float(sample[1]) / HOLOGRAM.SLAM_HEIGHT
	_expect(half_drop >= 0.0 and half_drop < 0.3,
		"and ACCELERATES: only %.0f%% of the way down at half time" % (half_drop * 100.0))
	_expect(cheap.hologram.phase == "fill", "it floods white on contact")
	if lines != null and is_instance_valid(lines):
		_expect(absf(lines.global_position.y - slot.y - HOLOGRAM.LIGHT_LIFT) < 0.002,
			"lying on the slot (%.3f m above the face)" % (lines.global_position.y - slot.y))
	_expect(_find_named(get_tree().root, "CardPlaySparks") != null, "sparks jump off its rim")
	_expect(not cheap.visible, "the card is still hidden inside the white")
	await _wait_for(func() -> bool: return cheap.hologram.phase == "landed", 1.0)
	var landed_ms: int = Time.get_ticks_msec() - t0
	_expect(cheap.visible, "then the card is there")
	_expect(cheap.hand_mesh.global_position.distance_to(slot) < 0.001, "already at rest on its slot")
	_expect(landed_ms > 850 and landed_ms < 1600,
		"slow enough to read: %d ms from confirm to reveal (0.85-1.6 s)" % landed_ms)
	_expect(_find_named(get_tree().root, "SlamDust") == null, "no dust: the impact is light")
	await get_tree().process_frame
	var cheap_moved: float = 0.0
	var cheap_jolted := false
	for i in 20:
		if HOLOGRAM.is_jolting():
			cheap_jolted = true
		cheap_moved = maxf(cheap_moved, camera.global_position.distance_to(camera_home))
		await get_tree().process_frame
	_expect(cheap_jolted and cheap_moved > 0.003, "even a cost-2 card jolts the camera (%.3f m)" % cheap_moved)
	await get_tree().create_timer(0.3).timeout
	_expect(not HOLOGRAM.is_jolting() and camera.global_position.is_equal_approx(camera_home),
		"and puts it back exactly")
	# THE WOOD SHADOW (card_field_shadow.gd): on the slab under the card, offset by FALL, full strength at rest, and
	# lighter while the card was still falling.
	await get_tree().process_frame
	var shadow = cheap.field_shadow
	_expect(shadow != null and shadow.active and shadow.is_visible_in_tree(), "a field card casts a wood shadow")
	if shadow != null:
		var want := Vector3(cheap.global_position.x + FIELD_SHADOW.FALL.x, FIELD_SHADOW.WOOD_Y,
			cheap.global_position.z + FIELD_SHADOW.FALL.y)
		_expect(shadow.global_position.distance_to(want) < 0.005,
			"on the wood, offset by FALL (%s vs %s)" % [str(shadow.global_position), str(want)])
		_expect(absf(shadow.strength() - FIELD_SHADOW.STRENGTH) < 0.02, "at full strength at rest (%.2f)" % shadow.strength())
	await get_tree().create_timer(0.4).timeout
	_expect(lines == null or not is_instance_valid(lines), "the drawing's light has gone")
	_expect(ghost == null or not is_instance_valid(ghost), "and so has the hologram")
	await Vfx.idle()

	# ---- the big card ---------------------------------------------------------------------------------------------
	_hand.charge(big)
	await get_tree().process_frame
	_assistant.on_charge_complete()
	await _wait_for(func() -> bool: return big.hologram.phase == "landed", 3.0)
	_expect(big.visible, "the big card lands")
	var big_sparks: int = 0
	for node in get_tree().root.get_children():
		# By class: a second spark burst under the root while the departure's is still alive gets an auto-name.
		if node is CPUParticles3D:
			big_sparks = maxi(big_sparks, int(node.get("amount")))
	_expect(big_sparks == HOLOGRAM.CONTACT_SPARKS[2], "and throws more sparks (%d)" % big_sparks)
	await get_tree().process_frame
	var moved: float = 0.0
	var jolted := false
	for i in 20:
		if HOLOGRAM.is_jolting():
			jolted = true
		moved = maxf(moved, camera.global_position.distance_to(camera_home))
		await get_tree().process_frame
	_expect(jolted, "a cost-9 card jolts the camera")
	_expect(moved > cheap_moved * 1.3 and moved < 0.15, "harder than the cheap one, a few pixels' worth (%.3f m vs %.3f m)" % [moved, cheap_moved])
	await get_tree().create_timer(0.3).timeout
	_expect(not HOLOGRAM.is_jolting() and camera.global_position.is_equal_approx(camera_home),
		"and puts it back exactly")
	await Vfx.idle()

	# ---- thickness follows the zone -------------------------------------------------------------------------------
	await _game.put_card_into_graveyard(cheap)
	_expect(absf(CARD_EDGE.thickness_of(cheap) - CARD_EDGE.CARD_EDGE_THICKNESS) < 0.0001,
		"off the field it is card-thin again")
	_expect(cheap.field_shadow == null or not cheap.field_shadow.active, "and casts no wood shadow")

	print("[CardPlay] %d checks | failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("[CardPlay] RESULT: all checks passed")
	else:
		print("[CardPlay] RESULT: %d FAILED" % _fails)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _find_named(node: Node, prefix: String) -> Node:
	for child in node.get_children():
		if child.name.begins_with(prefix):
			return child
	return null


func _wait_for(predicate: Callable, seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
