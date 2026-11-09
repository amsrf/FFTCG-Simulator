extends Node
## SelectionRequest + DeckSearch multi-select. Verifies that "different Elements" is a live constraint:
## selecting Fire dims the other Fire cards, deselecting restores them, and Confirm only reports a legal set.

const SEARCH := preload("res://scenes/ui/deck_search.tscn")
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const SELECTION_REQUEST := preload("res://scripts/effects/selection_request.gd")
const CARD_VIEW := preload("res://scripts/cards/card_view.gd")

const FIRE := 5
const FIRE_B := 7
const ICE := 33
const WIND := 69
const EARTH := 92

var _checks: int = 0
var _failures: int = 0
var _got: Array = []


func _ready() -> void:
	_test_request_rules()
	await _test_window()
	print("[Selection] %d checks | failures: %d" % [_checks, _failures])
	print("[Selection] RESULT: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit()


func _test_request_rules() -> void:
	var unique = SELECTION_REQUEST.new(
		CARD_QUERY.new().of_type("Forward").cost_at_most(2)
	).up_to(4).unique("element")

	_expect(unique.allows(FIRE, []), "an empty selection allows Fire")
	_expect(not unique.allows(FIRE, [FIRE]), "but another Fire is unavailable once Fire is selected")
	_expect(unique.allows(ICE, [FIRE]), "while Ice remains available")
	_expect(unique.valid([FIRE]), "one card is a legal 'up to 4' selection")
	_expect(unique.valid([FIRE, ICE, WIND, EARTH]), "four different Elements are legal")
	_expect(not unique.valid([]), "an empty selection is not confirmable")
	_expect(int(unique.maximum) == 4, "the request caps the selection at four")

	var exact = SELECTION_REQUEST.new(
		CARD_QUERY.new().of_type("Forward")
	).up_to(4).total_cost(4, 4)
	_expect(exact.allows(FIRE, [ICE]), "a cost-2 card is allowed while the total is 2")
	_expect(not exact.allows(WIND, [FIRE, ICE]), "a third cost-2 card would exceed the exact total of 4")
	_expect(exact.valid([FIRE, ICE]), "two cost-2 cards make exactly 4")
	_expect(not exact.valid([FIRE]), "one cost-2 card does not")

	var jobs = SELECTION_REQUEST.new(
		CARD_QUERY.new().of_type("Forward")
	).up_to(2).unique("job")
	_expect(not jobs.allows(92, [69]), "a second Standard Unit is unavailable when jobs must differ")
	_expect(jobs.allows(33, [69]), "but a different job is still selectable")


func _test_window() -> void:
	# Twelve matches, so the fan has a second page. All are cost-2 Forwards.
	var deck: Array = [5, 7, 9, 16, 25, 29, 33, 35, 69, 71, 73, 84]
	var request = SELECTION_REQUEST.new(
		CARD_QUERY.new().of_type("Forward").cost_at_most(2)
	).up_to(4).unique("element")

	var window = SEARCH.instantiate()
	add_child(window)
	await get_tree().process_frame
	window.open_multi(deck, {"type": "Forward", "max_cost": 2}, request, "Choose up to 4")
	await get_tree().process_frame

	_expect(window._multi, "the window is in multi-select mode")
	_expect(window._selected_ids.is_empty(), "and starts with nothing selected")
	_expect(window._confirm.disabled, "so Confirm starts disabled")

	window._toggle_multi(FIRE)
	await get_tree().process_frame
	_expect(window._selected_ids == [FIRE], "clicking a card records it")
	_expect(not window._confirm.disabled, "and enables Confirm for a legal one-card choice")
	var fire_node: Control = _node_for(window, FIRE)
	var fire_b_node: Control = _node_for(window, FIRE_B)
	_expect(fire_node != null and bool(window._node_selected.get(fire_node, false)),
		"the selected copy is the orange one")
	_expect(fire_b_node != null and fire_b_node.modulate.is_equal_approx(CARD_VIEW.UNAVAILABLE_TINT),
		"another Fire card is dimmed")
	_expect(fire_b_node != null and fire_b_node.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"and cannot be clicked")

	window._toggle_multi(ICE)
	await get_tree().process_frame
	_expect(window._selected_ids == [FIRE, ICE], "a different Element can be added")
	_expect(not window._confirm.disabled, "and the set remains confirmable")

	window._toggle_multi(FIRE)
	await get_tree().process_frame
	_expect(window._selected_ids == [ICE], "clicking a selected card removes it")
	fire_node = _node_for(window, FIRE)
	_expect(fire_node != null and fire_node.modulate.is_equal_approx(Color.WHITE),
		"and its Element becomes available again")

	# Page changes must not lose the selection.
	window._change_page(1)
	await get_tree().process_frame
	_expect(window._selected_ids == [ICE], "a page turn keeps the selection")
	window._change_page(0)
	await get_tree().process_frame
	_expect(window._selected_ids == [ICE], "and turning back keeps it too")

	window.finished_multi.connect(func(ids: Array): _got = ids)
	window._confirm.emit_signal("pressed")
	await get_tree().process_frame
	_expect(_got == [ICE], "Confirm reports the selected ids")

	# Cancel must also answer the multi-select await, with an empty list. Without this signal the LocalAgent
	# would hang forever when the player closes the window without picking anything.
	_got = [ICE]
	var cancel_window = SEARCH.instantiate()
	add_child(cancel_window)
	await get_tree().process_frame
	cancel_window.open_multi(deck, {"type": "Forward", "max_cost": 2}, request, "Choose up to 4")
	cancel_window.finished_multi.connect(func(ids: Array): _got = ids)
	cancel_window._cancel.emit_signal("pressed")
	await get_tree().process_frame
	_expect(_got.is_empty(), "Cancel reports an empty selection")

	# The windows free themselves after Confirm/Cancel; free them now if the deferred free has not run yet.
	if is_instance_valid(window):
		window.queue_free()
	if is_instance_valid(cancel_window):
		cancel_window.queue_free()


func _node_for(window, id: int) -> Control:
	for node in window._fan.get_children():
		if window._id_of(node) == id:
			return node
	return null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Selection] ok   %s" % what)
	else:
		_failures += 1
		print("[Selection] FAIL %s" % what)
