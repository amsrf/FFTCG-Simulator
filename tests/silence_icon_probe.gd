extends Node
## Silence icon: appears only while a field card has abilities_nullified, loops its dots, and disappears when the
## status expires or the card leaves the field.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	game.player_agent = MockAgent.new()
	game.player_agent.bind(game)
	game.opponent_agent = MockAgent.new()
	game.opponent_agent.bind(game)
	await get_tree().process_frame

	var field = game.field
	var card: Card = game.create_card(182, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame

	_expect(card.silence_icon == null or not card.silence_icon.visible,
		"an ordinary card shows no silence icon")

	card.add_status_effect("abilities_nullified", 1)
	await get_tree().process_frame
	var icon: Node3D = card.silence_icon
	_expect(icon != null and is_instance_valid(icon), "nullification builds the icon")
	_expect(icon.visible and bool(icon.call("is_active")), "and it is active on the field")
	_expect(int(icon.call("dot_count")) == 1, "the dot loop starts with one dot")
	icon.set("dot_seconds", 0.08)
	icon.call("_process", 0.09)
	_expect(int(icon.call("dot_count")) == 2, "after one beat, two dots are visible")
	icon.call("_process", 0.09)
	_expect(int(icon.call("dot_count")) == 3, "after the next beat, all three are visible")
	icon.call("_process", 0.09)
	_expect(int(icon.call("dot_count")) == 1, "and the loop returns to one")

	_expect(icon.position.x > 0.0, "the icon sits beside the card by default")
	_expect(icon.scale.x > 0.0, "and has a real size")

	card.turn_end()
	await get_tree().process_frame
	_expect(not bool(icon.call("is_active")) and not icon.visible,
		"end of turn hides the icon again")
	_expect(card.abilities_enabled(), "and the card's abilities are back")

	card.add_status_effect("abilities_nullified", 1)
	await get_tree().process_frame
	_expect(icon.visible, "setup: the icon is visible again")
	card.enter_zone(Card.Zone.HAND)
	await get_tree().process_frame
	_expect(not icon.visible, "leaving the field hides the icon")

	print("[Silence] %d checks | failures: %d" % [_checks, _fails])
	print("[Silence] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Silence] ok   ", what)
	else:
		_fails += 1
		print("[Silence] FAIL ", what)
