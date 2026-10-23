extends Node
## PARTY-SPLIT window probe (slice 2) — the blocker's damage distribution.
##
## Drives `bump()` / `confirm()`, which is exactly what the ▲▼ buttons and the Confirm button call, so the test runs
## the real paths. The window is a Control tree, not a game rule, so no Game instance is needed for the first half.

const SPLIT_SCENE := preload("res://party_split.tscn")

var _checks: int = 0
var _fails: int = 0
## A MEMBER, not a local: GDScript lambdas capture locals by value, so `got = split` inside the callback would write to
## a copy and the assertion would always see the empty original.
var _got: Array = []


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Split] ok   %s" % what)
	else:
		_fails += 1
		print("[Split] FAIL %s" % what)


func _card(id: int) -> Card:
	var card: Card = load("res://card.tscn").instantiate()
	card.id = id
	card.card_name = "Card %d" % id
	return card


func _ready() -> void:
	var a: Card = _card(41)     # Squall
	var b: Card = _card(43)     # Snow
	add_child(a)
	add_child(b)

	var window = SPLIT_SCENE.instantiate()
	add_child(window)
	window.open([a, b], 4000)

	_expect(window.can_confirm() == false, "Confirm starts disabled (0 of 4000 assigned)")
	_expect(window.assigned() == 0, "nothing is assigned yet")

	window.bump(0, 1)
	_expect(window.assigned() == 1000, "one ▲ is 1000 (assigned %d)" % window.assigned())
	_expect(window.can_confirm() == false, "still disabled")

	window.bump(0, 2)
	_expect(window.assigned() == 3000, "two more up-arrows -> 3000")
	window.bump(1, 1)
	_expect(window.assigned() == 4000, "the last 1000 fills the pool")
	_expect(window.can_confirm(), "Confirm enables exactly when the total EQUALS the blocker's power")

	# Overshooting is clamped, not refused: the total can never exceed the pool.
	window.bump(0, 1)
	_expect(window.assigned() == 4000, "an extra ▲ does not push the total past the pool")
	_expect(window.split() == [3000, 1000], "the split is [3000, 1000] as assigned")

	# Down-arrows, and the disabled state comes back.
	window.bump(1, -1)
	_expect(window.assigned() == 3000 and not window.can_confirm(), "▼ takes 1000 back and Confirm disables")
	window.bump(1, 1)

	# Confirm reports the split and the window frees itself.
	window.finished.connect(func(split): _got = split)
	window.confirm()
	await get_tree().process_frame
	_expect(_got == [3000, 1000], "Confirm emits the split (%s)" % str(_got))

	# --- an odd total: the final step is partial ------------------------------------------------------
	var w2 = SPLIT_SCENE.instantiate()
	add_child(w2)
	w2.open([a, b], 2500)
	w2.bump(0, 2)             # 2000
	w2.bump(0, 1)             # would be 3000 -> clamped to the remaining 500
	_expect(w2.assigned() == 2500, "a 2500 blocker can be distributed exactly (got %d)" % w2.assigned())
	_expect(w2.split() == [2500, 0], "and the partial step lands on the last member bumped (%s)" % str(w2.split()))
	_expect(w2.can_confirm(), "so Confirm is available")
	w2.queue_free()

	print("[Split] %d checks | failures: %d" % [_checks, _fails])
	print("[Split] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
