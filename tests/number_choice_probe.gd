extends Node
## The 《X》 declaration window: range, +/- clamping, and Confirm.

const NUMBER_CHOICE := preload("res://scenes/ui/number_choice.tscn")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Number] ok   %s" % what)
	else:
		_fails += 1
		print("[Number] FAIL %s" % what)


func _ready() -> void:
	var window = NUMBER_CHOICE.instantiate()
	add_child(window)
	await get_tree().process_frame
	window.open(0, 2, "Choose X")
	_expect(window.value() == 2, "the window opens at the maximum")
	_expect(window.minimum() == 0 and window.maximum() == 2, "it carries its declared range")
	_expect(window.confirm_enabled(), "Confirm is available")

	window.bump(-1)
	_expect(window.value() == 1, "minus decrements X")
	window.bump(-1)
	window.bump(-1)
	_expect(window.value() == 0, "X clamps at the minimum")
	window.bump(1)
	window.bump(1)
	window.bump(1)
	_expect(window.value() == 2, "X clamps at the maximum")

	window.confirm_choice()
	await get_tree().process_frame
	_expect(not is_instance_valid(window), "Confirm closes the window")

	print("[Number] %d checks | failures: %d" % [_checks, _fails])
	print("[Number] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
