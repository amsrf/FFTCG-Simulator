extends Node
## HASTE CLOCK probe (Card.sync_haste_vfx + haste_clock_cue.gd + haste_clock.gd).
##
## Asserts what the player is promised:
##   the haste preset resolves to the clock cue,
##   a setup board with a Haste card plays nothing (it did not ENTER with Haste),
##   a card that gains Haste as a STATUS plays exactly one clock, and gaining it again while it has it plays none,
##   an AURA grant (Zangan 188 -> Tifa) plays the clock, and the grant ending reports STATUS_REMOVED, not a clock,
##   a printed-Haste card PLAYED to the field plays its clock only AFTER its arrival animation has been queued,
##   the clock draws on, spins its hands FAST (>= 2 turns per second), is screen-sized around the card,
##   the cue releases the queue early (the clock outlives it), and the clock frees itself.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const CLOCK := preload("res://scripts/vfx/haste_clock.gd")
const CHOCOBO := 75      # printed Haste
const PLAIN := 41        # no Haste
const ZANGAN := 188      # aura: a cost-4 Tifa gains Haste
const TIFA := 189

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[HasteVfx] ok   %s" % what)
	else:
		_fails += 1
		print("[HasteVfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	await Vfx.idle()
	Vfx.clear_events()

	var preset: VfxPreset = Vfx.preset_for(VfxEvent.new(VfxEvent.Kind.STATUS_APPLIED, [], "", 0, null, "", "haste"))
	_expect(preset != null and preset.status == "haste" and preset.impact_scene != null,
		"the haste status preset points at the clock cue")

	# A SETUP board: a printed-Haste card placed without animation did not enter with Haste.
	var setup: Card = _place(game, field, CHOCOBO)
	_expect(setup.has_haste() and _haste_events(VfxEvent.Kind.STATUS_APPLIED) == 0,
		"a pre-placed Haste card plays no clock")

	# GAINS HASTE AS A STATUS: one clock.
	var plain: Card = _place(game, field, PLAIN)
	_expect(not plain.has_haste(), "the plain Forward starts without Haste")
	# A neighbour on the same row: the clock must never reach it.
	_place(game, field, PLAIN)
	plain.add_status_effect("haste", 1)
	_expect(_haste_events(VfxEvent.Kind.STATUS_APPLIED) == 1, "gaining Haste as a status raises one haste event")
	await get_tree().process_frame
	var cue: Node = _find_cue()
	_expect(cue != null and int(cue.call("clock_count")) == 1, "the director plays the clock cue: one clock")
	var clocks: Array = _clocks()
	_expect(clocks.size() == 1, "one clock exists (got %d)" % clocks.size())
	plain.add_status_effect("haste", 1)
	_expect(_haste_events(VfxEvent.Kind.STATUS_APPLIED) == 1, "gaining Haste it already has plays no second clock")
	if not clocks.is_empty():
		var reach: float = float(clocks[0].call("max_visible_radius"))
		# The NEAREST card in the same row, wherever the layout put it.
		var gap_x: float = INF
		for other in field.get_all_cards():
			if other == plain or absf(other.global_position.z - plain.global_position.z) > 0.1:
				continue
			gap_x = minf(gap_x, absf(other.global_position.x - plain.global_position.x)
				- other._card_face_size().x * other.global_transform.basis.get_scale().x * 0.5)
		print("[HasteVfx] clock reach %.3f m, neighbour's near edge %.3f m from the centre" % [reach, gap_x])
		_expect(gap_x > 0.0 and reach < gap_x, "the clock never reaches the neighbouring card")
		await _check_clock(clocks[0], plain)
	await Vfx.idle()

	# AN AURA GRANT: Zangan gives a cost-4 Tifa Haste; it ending reports STATUS_REMOVED, not a clock.
	var tifa: Card = _place(game, field, TIFA)
	var before: int = _haste_events(VfxEvent.Kind.STATUS_APPLIED)
	var zangan: Card = _place(game, field, ZANGAN)
	_expect(tifa.has_haste() and _haste_events(VfxEvent.Kind.STATUS_APPLIED) == before + 1,
		"an aura granting Haste plays the clock")
	game.call("break_card", zangan)
	await get_tree().create_timer(0.3).timeout
	_expect(not tifa.has_haste() and _haste_events(VfxEvent.Kind.STATUS_REMOVED) >= 1,
		"losing the grant reports STATUS_REMOVED")
	_expect(_haste_events(VfxEvent.Kind.STATUS_APPLIED) == before + 1, "and plays no clock")
	await Vfx.idle()
	await get_tree().create_timer(CLOCK.LIFETIME).timeout

	# PLAYED WITH PRINTED HASTE: the clock event is queued AFTER the arrival presentation.
	# (The setup Chocobo leaves first: a second copy would be refused by the unique-name rule.)
	game.call("break_card", setup)
	await get_tree().create_timer(0.3).timeout
	await Vfx.idle()
	Vfx.clear_events()
	var chocobo: Card = game.call("create_card", CHOCOBO, "player")
	game.add_child(chocobo)
	field.play_card(chocobo, false, true, true)
	_expect(_haste_events(VfxEvent.Kind.STATUS_APPLIED) == 0, "no haste event while the card is still arriving")
	await Vfx.idle()
	var events: Array = Vfx.get_events()
	var arrival_at := -1
	var haste_at := -1
	for i in events.size():
		var e: VfxEvent = events[i]
		if e.kind == VfxEvent.Kind.PRESENT and arrival_at < 0:
			arrival_at = i
		if e.kind == VfxEvent.Kind.STATUS_APPLIED and e.status == "haste" and chocobo in e.targets:
			haste_at = i
	_expect(haste_at >= 0, "a card played with printed Haste raises the haste event")
	_expect(arrival_at >= 0 and haste_at > arrival_at,
		"the clock is queued after the arrival (arrival #%d, haste #%d)" % [arrival_at, haste_at])
	await Vfx.idle()
	_expect(chocobo.overlays.sickness_state() in ["NONE", "HIDDEN"], "a Haste card never shows the sickness waves")
	_expect(chocobo.is_drawn_on_field() and _clocks().size() == 1, "the played card gets its clock once it has landed")
	await get_tree().create_timer(CLOCK.LIFETIME + 0.2).timeout
	_expect(_clocks().is_empty(), "the clock frees itself")
	_finish(game)


func _check_clock(clock: Node3D, card: Card) -> void:
	var height: float = card._card_face_size().y * card.global_transform.basis.get_scale().z
	await get_tree().create_timer(0.05).timeout
	var early_reveal: float = float(clock.call("shader_value", "reveal"))
	var m0: float = float(clock.call("shader_value", "minute_hand"))
	var t0: float = float(clock.call("age"))
	_expect(early_reveal > 0.0 and early_reveal < 1.0, "the dial is still drawing itself on (reveal %.2f)" % early_reveal)
	await get_tree().create_timer(CLOCK.APPEAR_SECONDS).timeout
	_expect(float(clock.call("shader_value", "reveal")) >= 0.999, "the dial is fully drawn after the appearance")
	_expect(_find_cue() == null, "the cue has released the queue while the clock keeps going")
	_expect(is_instance_valid(clock), "the clock outlives its cue")
	var m1: float = float(clock.call("shader_value", "minute_hand"))
	var rate: float = (m1 - m0) / maxf(float(clock.call("age")) - t0, 0.001)
	print("[HasteVfx] minute hand: %.2f turns/s" % rate)
	_expect(rate >= 2.0, "the clock runs fast (%.2f turns/s)" % rate)
	# THE CARD MUST NOT COVER IT: the camera-facing quad is tilted against the card, so its lowest corner dips.
	var lowest: float = float(clock.call("lowest_corner_height"))
	print("[HasteVfx] lowest clock corner %.3f m above the card" % lowest)
	_expect(lowest > 0.02, "every corner of the clock stays above the card face (%.3f m)" % lowest)
	var size: float = float(clock.call("screen_size_metres"))
	print("[HasteVfx] clock size %.3f m vs card height %.3f m" % [size, height])
	_expect(size > height * 0.9 and size < height * 1.3, "the clock circles the card (%.2f card heights)" % (size / height))


func _place(game: Node, field, id: int) -> Card:
	var card: Card = game.call("create_card", id, "player")
	game.add_child(card)
	field.play_card(card, false, false, false)
	return card


func _haste_events(kind: int) -> int:
	var n := 0
	for e in Vfx.get_events():
		if e.kind == kind and e.status == "haste":
			n += 1
	return n


func _find_cue() -> Node:
	for child in Vfx.get_children():
		if child.has_method("clock_count"):
			return child
	return null


func _clocks() -> Array:
	var out: Array = []
	for child in get_tree().root.get_children():
		if child.name.begins_with("HasteClock"):
			out.append(child)
	return out


func _finish(game: Node) -> void:
	print("[HasteVfx] RESULT: %s (%d checks, %d failed)" % ["all checks passed" if _fails == 0 else "FAILED", _checks, _fails])
	game.queue_free()
	get_tree().quit()
