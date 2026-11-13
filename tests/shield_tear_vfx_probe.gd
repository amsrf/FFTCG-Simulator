extends Node
## SHIELD TEAR probe (block_disabled status -> shield_tear_cue.gd -> shield_tear.gd).
##
## Asserts what the player is promised:
##   the "block_disabled" status preset resolves to the tear cue,
##   a field card losing the ability to block plays exactly one tear, and again while it still cannot block plays none,
##   blue gas builds up first, the shield arises out of it to sit high on the card, holds, tears apart and fades,
##   never reaching the neighbouring card,
##   the cue releases the queue once it has torn (the halves outlive it), and it frees itself.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHELL := preload("res://scripts/vfx/shield_tear.gd")
const PLAIN := 41

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ShieldTearVfx] ok   %s" % what)
	else:
		_fails += 1
		print("[ShieldTearVfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	await Vfx.idle()
	Vfx.clear_events()

	var preset: VfxPreset = Vfx.preset_for(VfxEvent.new(VfxEvent.Kind.STATUS_APPLIED, [], "", 0, null, "", "block_disabled"))
	_expect(preset != null and preset.status == "block_disabled" and preset.impact_scene != null,
		"the block_disabled status preset points at the tear cue")

	var card: Card = _place(game, field, PLAIN)
	_place(game, field, PLAIN)   # a neighbour on the same row: the shell must never reach it
	card.add_status_effect("block_disabled", 1)
	_expect(not field.can_block(card), "the card cannot block")
	_expect(_events() == 1, "losing blocking raises one block_disabled event")
	await get_tree().process_frame
	var cue: Node = _find_cue()
	_expect(cue != null and int(cue.call("tear_count")) == 1, "the director plays the tear cue: one shield")
	var shells: Array = _shells()
	_expect(shells.size() == 1, "one shield exists (got %d)" % shells.size())
	card.add_status_effect("block_disabled", 1)
	_expect(_events() == 1, "applying it again while it still cannot block plays no second shield")
	if shells.is_empty():
		_finish(game)
		return
	var shell: Node3D = shells[0]

	var reach: float = float(shell.call("max_visible_half_width"))
	var gap_x: float = INF
	for other in field.get_all_cards():
		if other == card or absf(other.global_position.z - card.global_position.z) > 0.1:
			continue
		gap_x = minf(gap_x, absf(other.global_position.x - card.global_position.x)
			- other._card_face_size().x * other.global_transform.basis.get_scale().x * 0.5)
	print("[ShieldTearVfx] halves reach %.3f m, neighbour's near edge %.3f m from the centre" % [reach, gap_x])
	_expect(gap_x > 0.0 and reach < gap_x, "the torn halves never reach the neighbouring card")
	# The timeline, frozen at chosen moments (sample(t) is deterministic).
	shell.set_process(false)
	shell.call("sample", 0.0)
	shell.call("sample", SHELL.RISE_START * 0.9)
	var st: Dictionary = shell.call("state")
	_expect(float(st["alpha"]) == 0.0 and int(shell.call("visible_puffs")) > 0,
		"the BUILD-UP comes first: blue gas, no shield yet (%d puffs)" % int(shell.call("visible_puffs")))
	shell.call("sample", (SHELL.RISE_START + SHELL.RISE_END) * 0.5)
	st = shell.call("state")
	_expect(float(st["lift"]) > SHELL.RISE_FROM + 0.05 and float(st["lift"]) < SHELL.CENTRE_UP and float(st["alpha"]) > 0.2,
		"then the shield ARISES out of it (half way: %.2f card heights up)" % float(st["lift"]))
	_expect(SHELL.RISE_END - SHELL.RISE_START >= 0.3, "and the rise takes its time (%.2f s)" % (SHELL.RISE_END - SHELL.RISE_START))
	shell.call("sample", SHELL.RISE_END)
	st = shell.call("state")
	_expect(is_equal_approx(float(st["lift"]), SHELL.CENTRE_UP) and SHELL.CENTRE_UP + SHELL.HEIGHT * 0.5 > 0.45,
		"it settles high on the card, its top near the card's top edge (centre %.2f card heights up)" % float(st["lift"]))
	_expect(float(st["split"]) == 0.0, "whole while it holds")
	shell.call("sample", (SHELL.RISE_END + SHELL.SPLIT_START) * 0.5)
	_expect(float(shell.call("state")["split"]) == 0.0, "it holds whole for a beat before it tears")
	_expect(shell.get_node_or_null("Crack") == null, "there is no crack line: it simply tears")
	shell.call("sample", SHELL.SPLIT_END)
	_expect(float(shell.call("state")["split"]) >= 0.999, "then the halves are fully apart")
	shell.call("sample", SHELL.LIFETIME - 0.001)
	_expect(float(shell.call("state")["alpha"]) <= 0.01, "and at the end of its life they have faded away")
	_expect(SHELL.LIFETIME <= 1.2, "the whole thing is still quick (%.2f s)" % SHELL.LIFETIME)
	shell.set_process(true)

	var started: int = Time.get_ticks_msec()
	await Vfx.idle()
	var held: float = (Time.get_ticks_msec() - started) / 1000.0
	_expect(held < SHELL.LIFETIME, "the cue releases the queue before the halves are gone (%.2f s)" % held)
	await get_tree().create_timer(SHELL.LIFETIME + 0.2).timeout
	_expect(_shells().is_empty(), "it frees itself")
	_finish(game)


func _place(game: Node, field, id: int) -> Card:
	var c: Card = game.call("create_card", id, "player")
	game.add_child(c)
	field.play_card(c, false, false, false)
	return c


func _events() -> int:
	var n := 0
	for e in Vfx.get_events():
		if e.kind == VfxEvent.Kind.STATUS_APPLIED and e.status == "block_disabled":
			n += 1
	return n


func _find_cue() -> Node:
	for child in Vfx.get_children():
		if child.has_method("tear_count"):
			return child
	return null


func _shells() -> Array:
	var out: Array = []
	for child in get_tree().root.get_children():
		if child.name.begins_with("ShieldTear") and child.has_method("sample") and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _finish(game: Node) -> void:
	print("[ShieldTearVfx] RESULT: %s (%d checks, %d failed)" % ["all checks passed" if _fails == 0 else "FAILED", _checks, _fails])
	game.queue_free()
	get_tree().quit(0 if _fails == 0 else 1)
