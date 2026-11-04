extends Node
## LIGHTNING DAMAGE VFX probe.
##
## Asserts the path that matters for the first authored element effect:
##   a 雷 damage event resolves the lightning preset,
##   the preset points at a real cue scene,
##   the cue is instantiated by the director,
##   it strikes the target card once in single-target mode,
##   and the director frees it after the one-shot finishes.

const GAME_SCENE := preload("res://game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[LightningVfx] ok   %s" % what)
	else:
		_fails += 1
		print("[LightningVfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	Vfx.clear_events()

	var target: Card = game.create_card(41, "player")
	game.add_child(target)
	field.play_card(target, false, false)
	var origin: Card = game.create_card(121, "player")
	game.add_child(origin)
	await get_tree().process_frame

	var preset: VfxPreset = Vfx.preset_for_element("雷")
	_expect(preset != null, "the lightning element has a preset")
	_expect(preset != null and preset.impact_scene != null,
		"the lightning preset points at an impact scene")
	_expect(preset != null and preset.board_impact_scene != null,
		"the lightning preset points at a board scene")

	var ctx = EFFECT_CONTEXT.new(game, origin, "test", {}, origin, [target])
	ctx.damage([target], 1)
	var events: Array = Vfx.get_events()
	_expect(events.size() == 1 and events[0].kind == VfxEvent.Kind.DAMAGE,
		"the directed hit emits one DAMAGE event")
	_expect(events.size() == 1 and events[0].element == "雷",
		"the event carries the lightning element")
	_expect(events.size() == 1 and events[0].target_count() == 1,
		"the event names the target card")

	var cue: Node = null
	for child in Vfx.get_children():
		if child.has_method("strike_count"):
			cue = child
			break
	_expect(cue != null, "the director instantiates the lightning cue")
	_expect(cue != null and int(cue.call("strike_count")) == 1,
		"single-target damage strikes exactly one card")

	# Let the one-shot finish, then confirm the director released it.
	await get_tree().create_timer(0.8).timeout
	await get_tree().process_frame
	var still_there: bool = false
	for child in Vfx.get_children():
		if child.has_method("strike_count"):
			still_there = true
			break
	_expect(not still_there, "the cue is freed after the strike finishes")

	# A multi-target event fans out: one strike per valid target, not a single
	# impact on whichever card happened to be first.
	var second: Card = game.create_card(41, "player")
	game.add_child(second)
	field.play_card(second, false, false)
	await get_tree().process_frame
	Vfx.clear_events()
	ctx.damage([target, second], 1, "multi")
	var multi_events: Array = Vfx.get_events()
	_expect(multi_events.size() == 1 and multi_events[0].target_count() == 2,
		"a multi-target damage event names both cards")
	var multi_cue: Node = null
	for child in Vfx.get_children():
		if child.has_method("strike_count"):
			multi_cue = child
			break
	_expect(multi_cue != null and int(multi_cue.call("strike_count")) == 2,
		"multi-target damage strikes both cards")
	await get_tree().create_timer(0.9).timeout

	# Damage tiers are semantic and shared by every element cue. 9000 starts the
	# maximum tier; 9000 is the explicit "9000+" breakpoint.
	var tier_cases: Array = [
		[3000, 0], [3001, 1], [4000, 1], [6000, 1],
		[7000, 2], [8999, 2], [9000, 3], [12000, 3],
	]
	for case in tier_cases:
		var amount: int = int(case[0])
		var expected: int = int(case[1])
		var event := VfxEvent.new(VfxEvent.Kind.DAMAGE, [], "雷", amount, null, "single")
		_expect(event.damage_tier() == expected,
			"%d damage resolves to tier %d" % [amount, expected])

	print("[LightningVfx] %d checks | failures: %d" % [_checks, _fails])
	print("[LightningVfx] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
