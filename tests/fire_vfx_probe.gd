extends Node
## FIRE DAMAGE VFX probe (fire_burst_cue.gd + fire_burst.gd).
##
## Asserts what the eye is promised:
##   a 火 damage event resolves the fire preset and its cue,
##   one burst per target, its sparks GATHER (they get closer to the card over the charge),
##   nothing explodes and the card does not recoil until the detonation, and then both happen,
##   the cue releases the presentation queue, the burst frees itself,
##   a card the fire BREAKS is held on its slot and shatters in the blast, not before.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const BURST := preload("res://scripts/vfx/fire_burst.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[FireVfx] ok   %s" % what)
	else:
		_fails += 1
		print("[FireVfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	Vfx.clear_events()

	var target: Card = game.create_card(41, "player")
	game.add_child(target)
	field.play_card(target, false, false)
	var origin: Card = game.create_card(1, "player")   # Auron, 火
	game.add_child(origin)
	origin.visible = false
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	var preset: VfxPreset = Vfx.preset_for_element("火")
	_expect(preset != null and preset.impact_scene != null and preset.board_impact_scene != null,
		"the fire preset points at its cue for directed and board hits")
	_expect(preset != null and preset.owns_damage_reaction and preset.effect_break,
		"the fire cue owns the recoil and stages the breaks it causes")

	var ctx = EFFECT_CONTEXT.new(game, origin, "test", {}, origin, [target])
	ctx.damage([target], 1000)
	var events: Array = Vfx.get_events()
	_expect(events.size() == 1 and events[0].kind == VfxEvent.Kind.DAMAGE and events[0].element == "火",
		"fire damage emits one 火 DAMAGE event")
	await get_tree().process_frame
	var cue: Node = _find_cue()
	_expect(cue != null and int(cue.call("burst_count")) == 1, "the director plays the fire cue: one burst")
	var bursts: Array = _bursts()
	_expect(bursts.size() == 1, "one fire burst exists (got %d)" % bursts.size())
	if bursts.is_empty():
		_finish(game)
		return
	var burst: Node3D = bursts[0]
	_expect(int(burst.call("mote_count")) > 0 and int(burst.call("ember_count")) > 0,
		"the burst has gathering motes (%d) and embers (%d)" % [burst.call("mote_count"), burst.call("ember_count")])

	# THE SPARKS CONVERGE: their mean distance from the card shrinks across the charge.
	await get_tree().create_timer(0.07).timeout
	var early: float = _mean_mote_distance(burst, target.global_position)
	await get_tree().create_timer(0.14).timeout
	var late: float = _mean_mote_distance(burst, target.global_position)
	print("[FireVfx] mean mote distance: %.3f m early -> %.3f m late" % [early, late])
	_expect(early > 0.0 and late < early * 0.7, "the motes converge on the card")
	_expect(not (burst.get("_ball") as Node3D).visible, "no fireball before the detonation")
	_expect(not target.damage_fx.is_reacting(), "the card does not recoil before the detonation")

	await get_tree().create_timer(BURST.CHARGE_SECONDS - 0.21 + 0.08).timeout
	_expect(is_instance_valid(burst) and (burst.get("_ball") as Node3D).visible, "the fireball appears at the detonation")
	_expect(target.damage_fx.is_reacting(), "the card recoils at the detonation")

	# IT DISSIPATES, IT DOES NOT SHRINK: the fireball's size never goes down over its life.
	var sizes: Array[float] = []
	for _i in 6:
		if is_instance_valid(burst):
			sizes.append((burst.get("_ball") as Node3D).scale.x)
		await get_tree().create_timer(0.1).timeout
	var never_shrinks := sizes.size() >= 4
	for i in range(1, sizes.size()):
		if sizes[i] < sizes[i - 1] - 0.001:
			never_shrinks = false
	print("[FireVfx] fireball scale over its life: %s" % [sizes])
	_expect(never_shrinks, "the fireball keeps growing while it dissipates (never shrinks back)")
	_expect(_find_cue() == null, "the cue has released the presentation queue")
	await get_tree().create_timer(BURST.LIFETIME).timeout
	_expect(_bursts().is_empty(), "the burst frees itself once the embers are gone")

	# Several targets: one burst each.
	var second: Card = game.create_card(41, "player")
	game.add_child(second)
	field.play_card(second, false, false)
	await get_tree().process_frame
	await Vfx.idle()
	ctx.damage([target, second], 1000, "multi")
	await get_tree().process_frame
	var multi_cue: Node = _find_cue()
	_expect(multi_cue != null and int(multi_cue.call("burst_count")) == 2 and _bursts().size() == 2,
		"multi-target fire damage sets both cards on fire")
	await Vfx.idle()

	await _check_effect_break(game, field, origin)
	_finish(game)


## A card the fire BREAKS is held on its slot and shatters in the blast.
func _check_effect_break(game: Node, field, origin: Card) -> void:
	var victim: Card = game.create_card(41, "opponent")
	game.add_child(victim)
	field.play_card(victim, true, false)
	await get_tree().process_frame
	var shards_before: int = _shard_count()
	Vfx.clear_events()
	EFFECT_CONTEXT.new(game, origin, "test", {}, origin, [victim]).break_cards([victim])
	_expect(not victim.is_on_field(), "a fire break by effect still breaks the card at once (rules)")
	await get_tree().create_timer(0.15).timeout
	_expect(_shard_count() == shards_before and get_tree().root.find_children("HeldCard*", "", true, false).size() == 1,
		"during the charge the card is held on its slot, unbroken on screen")
	await get_tree().create_timer(BURST.CHARGE_SECONDS - 0.15 + 0.12).timeout
	_expect(_shard_count() > shards_before and get_tree().root.find_children("HeldCard*", "", true, false).is_empty(),
		"it shatters at the detonation")
	await Vfx.idle()


func _mean_mote_distance(burst: Node3D, centre: Vector3) -> float:
	var points: PackedVector3Array = burst.call("visible_mote_positions")
	var total := 0.0
	for at in points:
		total += Vector2(at.x - centre.x, at.z - centre.z).length()
	return total / points.size() if points.size() > 0 else 0.0


func _find_cue() -> Node:
	for child in Vfx.get_children():
		if child.has_method("burst_count"):
			return child
	return null


func _bursts() -> Array:
	var found: Array = []
	for child in get_tree().root.get_children():
		if child.get_script() == BURST:
			found.append(child)
	return found


func _shard_count() -> int:
	var shards_script: Script = preload("res://scripts/cards/card_shards.gd")
	var count: int = 0
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node.get_script() == shards_script:
			count += 1
	return count


func _finish(game: Node) -> void:
	print("[FireVfx] %d checks | failures: %d" % [_checks, _fails])
	print("[FireVfx] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
