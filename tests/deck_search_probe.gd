extends Node
## The deck search window's MODEL: what it offers, how the fan is laid out, what is selected, and what Confirm
## and Cancel report back.
##
## Mouse-driven behaviour cannot be simulated headless, but the ARRANGEMENT can: laying the fan out only needs a
## size, so the shape, the spacing and the containment are all checked here directly.
##
## Uses the real Agrias deck's shape: SIX Ovelia (three under each of two ids), three Agrias, one Auron. The
## duplicates are the point — they are what broke the first version of both the window and this probe.
##
## Run: godot --headless res://tests/deck_search_probe.tscn --quit-after 400

const SEARCH := preload("res://deck_search.tscn")
## The script as well as the scene: CHOOSE_NONE lives on the class, and reaching it through an instance that has
## already freed itself is how this probe crashed the first time it ran.
const SEARCH_SCRIPT := preload("res://scripts/deck_search.gd")

const OVELIA_A := 714
const OVELIA_B := 156
const AGRIAS := 151
const AURON := 1

## The aura is tweened over 0.12 s, so a check that reads it must wait longer than one frame.
const FADE_WAIT := 0.2
## The room the fan is given while measuring. Headless has a zero-size viewport, so the probe sets this itself —
## which is also what makes the layout reachable without a real window.
const FAN_ROOM := Vector2(820.0, 300.0)

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	var deck: Array = [OVELIA_A, OVELIA_B, OVELIA_B, OVELIA_B, OVELIA_A, OVELIA_A, AGRIAS, AGRIAS, AGRIAS, AURON]

	var window = SEARCH.instantiate()
	add_child(window)
	await get_tree().process_frame

	# --- opening: only the matches, sorted --------------------------------------------------
	window.open(deck, {"name": "Ovelia"})
	await get_tree().process_frame
	_expect(window._fan.get_child_count() == 6,
		"ONLY the six matching cards are shown, not the whole deck (%d)" % window._fan.get_child_count())
	var shown: Array = []
	for i in range(window._fan.get_child_count()):
		shown.append(_id_at(window, i))
	_expect(shown == [OVELIA_B, OVELIA_B, OVELIA_B, OVELIA_A, OVELIA_A, OVELIA_A],
		"and they are sorted by name then id (%s)" % str(shown))
	_expect(window.selected_id == SEARCH_SCRIPT.CHOOSE_NONE, "nothing starts selected")
	_expect(window._confirm.disabled, "and Confirm starts DISABLED, so nothing is confirmed by accident")
	_expect(window._subtitle.text.contains("Ovelia"),
		"the subtitle says what is being searched for (%s)" % window._subtitle.text)
	_expect(window._title.text != "", "and there is a title (%s)" % window._title.text)

	# --- the fan's SHAPE --------------------------------------------------------------------
	window._fan.size = FAN_ROOM
	window._place_cards(true)
	await get_tree().process_frame
	var middle_y: float = _node_at(window, 2).position.y
	var end_y: float = _node_at(window, 0).position.y
	_expect(middle_y < end_y - 1.0,
		"the fan curves UP at the middle, not down (%0.1f vs %0.1f)" % [middle_y, end_y])

	var tilt: float = _node_at(window, 0).rotation_degrees
	_expect(absf(tilt) > 0.5, "and the outer cards lean (%0.1f degrees)" % tilt)
	# An even count has NO card at the exact centre — the two middle ones sit at t = ±0.2 — so the lean is compared
	# between an end card and a middle one rather than against zero.
	_expect(absf(tilt) > absf(_node_at(window, 2).rotation_degrees) + 0.5,
		"and the lean grows towards the ends (%0.1f at the end vs %0.1f in the middle)" % [
			tilt, _node_at(window, 2).rotation_degrees])

	# --- the pivot is the BOTTOM edge -------------------------------------------------------
	# A fan is held at the bottom, so the cards must splay from there. Rotating about the centre instead swings
	# them around their middle, which reads as cards lying on a line rather than being held.
	var pivot: Vector2 = _node_at(window, 0).pivot_offset
	_expect(absf(pivot.y - _node_at(window, 0).size.y) < 0.5,
		"each card rotates about its BOTTOM edge (%0.1f vs a card %.1f tall)" % [pivot.y, _node_at(window, 0).size.y])
	_expect(absf(pivot.x - _node_at(window, 0).size.x * 0.5) < 0.5, "at its horizontal centre")

	# --- spacing: a tightly packed fan -------------------------------------------------------
	var card_width: float = window._card_size().x
	var step: float = _node_at(window, 1).position.x - _node_at(window, 0).position.x
	_expect(step <= card_width * float(window.MAX_GAP_FRACTION) + 0.01,
		"neighbours are at most %d%% of a card apart, so the row stays a fan (%0.1f vs %0.1f)" % [
			roundi(float(window.MAX_GAP_FRACTION) * 100.0), step, card_width])
	var overlap: float = (card_width - step) / card_width
	_expect(overlap >= 0.5 - 0.01,
		"the bottom edges overlap by more than half a card (%d%%)" % roundi(overlap * 100.0))
	_expect(step >= -card_width * float(window.MAX_OVERLAP_FRACTION) - 0.01,
		"and no card is buried deeper than the overlap limit")

	# --- CONTAINMENT: every card stays inside the fan's box ----------------------------------
	# This is the check that would have caught the cards hanging out of the bottom of the window. The allowance is
	# the extra height a leaning card's top corner swings up by, which _card_size() already reserves.
	var lean: float = card_width * 0.5 * sin(deg_to_rad(absf(tilt)))
	var outside: int = 0
	for i in range(window._fan.get_child_count()):
		var card: Control = _node_at(window, i)
		if (card.position.x < -0.5
				or card.position.y < -lean - 0.5
				or card.position.x + card.size.x > FAN_ROOM.x + 0.5
				or card.position.y + card.size.y > FAN_ROOM.y + lean + 0.5):
			outside += 1
	_expect(outside == 0, "every card sits inside the fan's box (%d outside)" % outside)
	_expect(window._card_size().x <= window.CARD.x + 0.01,
		"and cards are never enlarged past their preferred size")

	# --- paging ------------------------------------------------------------------------------
	# 24 matches is three pages of ten, four and four. The pager only exists when there is more than one page.
	var many: Array = []
	for i in range(24):
		many.append(OVELIA_A)
	window.open(many, {"name": "Ovelia"})
	await get_tree().process_frame
	_expect(window._page_count() == 3, "24 matches make three pages (%d)" % window._page_count())
	_expect(window._fan.get_child_count() == 10,
		"and the first page holds ten cards (%d)" % window._fan.get_child_count())
	_expect(window._prev.visible and window._next.visible, "with the pager shown")
	_expect(window._prev.disabled, "and Back disabled on the first page")
	window._change_page(1)
	await get_tree().process_frame
	_expect(window._fan.get_child_count() == 10, "the second page holds ten")
	window._change_page(1)
	await get_tree().process_frame
	_expect(window._fan.get_child_count() == 4, "and the last page holds the remainder (%d)" % window._fan.get_child_count())
	_expect(window._next.disabled, "with Forward disabled on the last page")
	_expect(not window._prev.disabled, "and Back available")
	# A page turn is a fresh arrangement, so nothing may stay selected across it.
	_expect(window.selected_id == SEARCH_SCRIPT.CHOOSE_NONE, "turning a page clears any selection")
	window._change_page(-1)
	window._change_page(-1)
	await get_tree().process_frame
	_expect(window._page == 0, "and Back returns to the first page")
	_expect(window._fan.get_child_count() == 10, "which is populated again")

	# --- hovering: the card comes toward the viewer, and NOTHING ELSE MOVES -------------------
	# The hovered card IS the zoom now that the preview panel is gone, and the row no longer makes room for it by
	# sliding the neighbours away. So a hover must enlarge exactly one card and move no other.
	window.open(deck, {"name": "Ovelia"})
	await get_tree().process_frame
	window._fan.size = FAN_ROOM
	window._place_cards(true)
	await get_tree().process_frame
	var first: Control = _node_at(window, 0)
	var next: Control = _node_at(window, 3)
	var neighbour_before: Vector2 = _node_at(window, 4).position
	var far_before: Vector2 = first.position
	window._hover(OVELIA_A, next)
	await get_tree().create_timer(FADE_WAIT).timeout
	_expect(next.scale.x > 1.05, "the hovered card grows toward the viewer (%.2f x)" % next.scale.x)
	_expect(next.z_index > 0, "and is drawn over its neighbours, so it cannot pass behind them")
	_expect(_node_at(window, 4).position.is_equal_approx(neighbour_before),
		"while the neighbouring card does NOT move (%s vs %s)" % [
			str(_node_at(window, 4).position), str(neighbour_before)])
	_expect(first.position.is_equal_approx(far_before), "and neither does the far end of the row")
	# The ENLARGED card has to fit too. It grows upward from its base, so this is what the height budget reserves
	# room for — a hover that grew out of the top of the box would be the same bug as the row overflowing the bottom.
	var grown_top: float = next.position.y + next.size.y * (1.0 - next.scale.y)
	_expect(grown_top >= -0.5,
		"and the enlarged card still fits inside the box (its top at %0.1f)" % grown_top)

	window._unhover()
	await get_tree().create_timer(FADE_WAIT).timeout
	_expect(absf(next.scale.x - 1.0) < 0.02, "and the card settles back to its resting size (%.2f x)" % next.scale.x)
	_expect(next.z_index == 0, "and back into its place in the stack")

	# --- selecting, on a deck that holds duplicates -----------------------------------------
	window._select(OVELIA_B, first)
	await get_tree().create_timer(FADE_WAIT).timeout
	_expect(window.selected_id == OVELIA_B, "selecting records the choice")
	_expect(not window._confirm.disabled, "and enables Confirm")
	_expect(_aura_of(first) > 0.5, "and lights the copy that was clicked")

	window._select(OVELIA_A, next)
	await get_tree().create_timer(FADE_WAIT).timeout
	_expect(window.selected_id == OVELIA_A, "selecting another moves the choice")
	_expect(_aura_of(next) > 0.5, "and lights the newly clicked copy")
	_expect(_aura_of(first) < 0.5, "while the previous copy goes dark again")

	# --- clicking the selection again takes it back ------------------------------------------
	window._select(OVELIA_A, next)
	await get_tree().create_timer(FADE_WAIT).timeout
	_expect(window.selected_id == SEARCH_SCRIPT.CHOOSE_NONE, "clicking the selected card DESELECTS it")
	_expect(_aura_of(next) < 0.5, "and its aura goes out")
	_expect(window._confirm.disabled, "and Confirm is disabled again, because nothing is chosen")

	# --- what Confirm reports --------------------------------------------------------------
	var reported: Array = []
	window.finished.connect(func(id: int): reported.append(id))
	window._select(OVELIA_A, next)
	await get_tree().process_frame
	window._confirm.emit_signal("pressed")
	await get_tree().process_frame
	_expect(reported == [OVELIA_A], "Confirm reports the selected card's id (%s)" % str(reported))

	# --- what Cancel reports ---------------------------------------------------------------
	# Cancel is how a player takes nothing, so it must work with NO selection and must be distinguishable from any
	# card id.
	var window2 = SEARCH.instantiate()
	add_child(window2)
	await get_tree().process_frame
	window2.open(deck, {"name": "Ovelia"})
	await get_tree().process_frame
	_expect(window2._confirm.disabled, "a fresh window has Confirm disabled")
	_expect(not window2._cancel.disabled, "and Cancel available immediately")
	var cancelled: Array = []
	window2.finished.connect(func(id: int): cancelled.append(id))
	window2._cancel.emit_signal("pressed")
	await get_tree().process_frame
	_expect(cancelled == [SEARCH_SCRIPT.CHOOSE_NONE],
		"Cancel reports CHOOSE_NONE, which is no card's id (%s)" % str(cancelled))

	# --- a filter nothing matches ------------------------------------------------------------
	# The window must still open, must offer nothing, and must still let the player out.
	var window3 = SEARCH.instantiate()
	add_child(window3)
	await get_tree().process_frame
	window3.open(deck, {"name": "nobody has this name"})
	await get_tree().process_frame
	_expect(window3._fan.get_child_count() == 0, "a filter nothing matches offers no cards")
	_expect(window3._confirm.disabled, "with Confirm disabled")
	_expect(not window3._cancel.disabled, "and Cancel still available, so the player is never stuck")
	_expect(not window3._prev.visible, "and no pager, because there is nothing to page")

	print("[DeckSearchProbe] %d checks | failures: %d" % [_checks, _failures])
	print("[DeckSearchProbe] RESULT: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

## The database id of the card shown at fan index `i`.
func _id_at(window, i: int) -> int:
	var node: Control = _node_at(window, i)
	return window._id_of(node)

func _node_at(window, i: int) -> Control:
	return window._fan.get_child(i) as Control

## How lit a node's aura currently is.
func _aura_of(node: Control) -> float:
	var material: ShaderMaterial = node.material
	var value: Variant = material.get_shader_parameter("hover")
	return float(value) if value is float else 0.0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DeckSearchProbe] ok   %s" % what)
	else:
		_failures += 1
		print("[DeckSearchProbe] FAIL %s" % what)
