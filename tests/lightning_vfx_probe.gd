extends Node
## LIGHTNING DAMAGE VFX probe.
##
## Asserts the path that matters for the first authored element effect:
##   a 雷 damage event resolves the lightning preset,
##   the preset points at a real cue scene,
##   the cue is instantiated by the director,
##   it strikes the target card once in single-target mode,
##   and the director frees it after the one-shot finishes.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
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

	await _check_effect_break(game, field, origin)

	print("[LightningVfx] %d checks | failures: %d" % [_checks, _fails])
	print("[LightningVfx] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## A lightning effect that BREAKS a card outright (no damage) gets the maximum-tier strike, and the card shatters at
## the bolt's impact, where it was - not at once, and not in the Break Zone it has already been moved to.
func _check_effect_break(game: Node, field, origin: Card) -> void:
	await Vfx.idle()
	var victim: Card = game.create_card(41, "opponent")
	game.add_child(victim)
	field.play_card(victim, true, false)
	await get_tree().process_frame
	var where: Vector3 = victim.global_position
	var shards_before: int = _shard_count()
	Vfx.clear_events()
	var ctx = EFFECT_CONTEXT.new(game, origin, "test", {}, origin, [victim])
	ctx.break_cards([victim])
	_expect(not victim.is_on_field(), "a lightning break by effect still breaks the card at once (rules)")
	var breaks: Array = Vfx.get_events().filter(func(e): return e.kind == VfxEvent.Kind.EFFECT_BREAK)
	_expect(breaks.size() == 1 and breaks[0].damage_tier() == 3 and breaks[0].element == "雷",
		"it emits one EFFECT_BREAK event at the maximum damage tier")
	_expect(_shard_count() == shards_before, "the card does not shatter before the bolt lands")
	var held: Array = get_tree().root.find_children("HeldCard*", "", true, false)
	_expect(held.size() == 1 and (held[0] as Node3D).global_position.distance_to(where) < 0.01 and held[0].visible
		and not victim.visible, "until then a stand-in holds the card on its slot, and the real card is hidden in the pile")
	await get_tree().process_frame
	await get_tree().process_frame
	var cue: Node = null
	for child in Vfx.get_children():
		if child.has_method("strike_count"):
			cue = child
	_expect(cue != null and int(cue.call("strike_count")) == 1, "the lightning cue strikes the broken card")
	var strike: Node = cue.get_child(0) if cue != null and cue.get_child_count() > 0 else null
	_expect(strike != null and (strike.get("_target_position") as Vector3).distance_to(where) < 0.01,
		"the bolt lands where the card was, not on the Break Zone pile")
	await get_tree().create_timer(0.25).timeout
	_expect(_shard_count() > shards_before, "the card shatters at the impact")
	_expect(victim.visible and get_tree().root.find_children("HeldCard*", "", true, false).is_empty(),
		"and then the stand-in is gone and the real card shows in the Break Zone")

	# A card protection keeps on the field is struck all the same, and survives it.
	await Vfx.idle()
	var guarded: Card = game.create_card(41, "opponent")
	game.add_child(guarded)
	field.play_card(guarded, true, false)
	guarded.add_status_effect("unbreakable", 1)
	await get_tree().process_frame
	Vfx.clear_events()
	var guarded_before: int = _shard_count()
	EFFECT_CONTEXT.new(game, origin, "test", {}, origin, [guarded]).break_cards([guarded])
	var guarded_events: Array = Vfx.get_events().filter(func(e): return e.kind == VfxEvent.Kind.EFFECT_BREAK)
	await get_tree().create_timer(0.30).timeout
	_expect(guarded.is_on_field() and guarded_events.size() == 1 and _shard_count() == guarded_before
		and get_tree().root.find_children("HeldCard*", "", true, false).is_empty() and guarded.visible,
		"a protected card is struck anyway and survives: no stand-in, no shatter")

	# An element without a staged break keeps the plain immediate shatter and gets no strike.
	await Vfx.idle()
	# Water (151): Fire now stages its breaks too (the fire burst), so it can no longer stand in for "no staging".
	var water_source: Card = game.create_card(151, "player")
	game.add_child(water_source)
	var plain: Card = game.create_card(41, "opponent")
	game.add_child(plain)
	field.play_card(plain, true, false)
	await get_tree().process_frame
	Vfx.clear_events()
	var before: int = _shard_count()
	EFFECT_CONTEXT.new(game, water_source, "test", {}, water_source, [plain]).break_cards([plain])
	_expect(Vfx.get_events().filter(func(e): return e.kind == VfxEvent.Kind.EFFECT_BREAK).is_empty()
		and _shard_count() > before, "a break by an element without a staged break shatters at once, no strike")


func _shard_count() -> int:
	var shards_script: Script = preload("res://scripts/cards/card_shards.gd")
	var count: int = 0
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node.get_script() == shards_script:
			count += 1
	return count
