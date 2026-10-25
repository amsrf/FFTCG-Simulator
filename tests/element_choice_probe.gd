extends Node
## Element picker UI used by "name an Element" effects (Mime 173).

const SCENE := preload("res://element_choice.tscn")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ElementChoice] ok   %s" % what)
	else:
		_fails += 1
		print("[ElementChoice] FAIL %s" % what)


func _ready() -> void:
	var window = SCENE.instantiate()
	add_child(window)
	await get_tree().process_frame
	window.open(["火", "氷", "風", "土", "雷", "水"], "Name an Element")
	_expect(window.option_count() == 6, "six Elements are offered")
	_expect(not window.confirm_enabled(), "Confirm is disabled before a choice")
	window.select_element(2)
	_expect(window.selected_index() == 2, "clicking selects an Element")
	_expect(window.confirm_enabled(), "Confirm becomes available after a choice")
	_expect(window.option_border_colour(2) != window.option_border_colour(1),
		"the selected option is marked with a different border")
	var got: Array = [""]
	window.finished.connect(func(element: String) -> void: got[0] = element)
	window.confirm_choice()
	await get_tree().process_frame
	_expect(got[0] == "風", "Confirm reports the chosen Element")

	var cancelled = SCENE.instantiate()
	add_child(cancelled)
	await get_tree().process_frame
	cancelled.open(["火", "氷"], "Name an Element")
	var result: Array = ["not-called"]
	cancelled.finished.connect(func(element: String) -> void: result[0] = element)
	cancelled.cancel_choice()
	await get_tree().process_frame
	_expect(result[0] == "", "Cancel reports no choice")

	print("[ElementChoice] %d checks | failures: %d" % [_checks, _fails])
	print("[ElementChoice] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
