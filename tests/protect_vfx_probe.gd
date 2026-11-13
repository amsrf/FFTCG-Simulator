extends Node
## PROTECT SHELL probe (unbreakable status -> protect_shell_cue.gd -> protect_shell.gd).
##
## Asserts what the player is promised:
##   the "unbreakable" status preset resolves to the shell cue,
##   a field card gaining "cannot be broken" plays exactly one shell, and gaining it again while it has it plays none,
##   the shell builds (panels, then the flare), sits above the card face, never reaches the neighbouring card,
##   the cue releases the queue once the shell has closed (the shell outlives it), and the shell frees itself.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHELL := preload("res://scripts/vfx/protect_shell.gd")
const PLAIN := 41

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ProtectVfx] ok   %s" % what)
	else:
		_fails += 1
		print("[ProtectVfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	await Vfx.idle()
	Vfx.clear_events()

	var preset: VfxPreset = Vfx.preset_for(VfxEvent.new(VfxEvent.Kind.STATUS_APPLIED, [], "", 0, null, "", "unbreakable"))
	_expect(preset != null and preset.status == "unbreakable" and preset.impact_scene != null,
		"the unbreakable status preset points at the shell cue")

	var card: Card = _place(game, field, PLAIN)
	_place(game, field, PLAIN)   # a neighbour on the same row: the shell must never reach it
	card.add_status_effect("unbreakable", 1)
	_expect(card.is_unbreakable(), "the card cannot be broken")
	_expect(_events() == 1, "gaining it raises one unbreakable event")
	await get_tree().process_frame
	var cue: Node = _find_cue()
	_expect(cue != null and int(cue.call("shell_count")) == 1, "the director plays the shell cue: one shell")
	var shells: Array = _shells()
	_expect(shells.size() == 1, "one shell exists (got %d)" % shells.size())
	card.add_status_effect("unbreakable", 1)
	_expect(_events() == 1, "gaining it again while it has it plays no second shell")
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
	print("[ProtectVfx] shell reach %.3f m, neighbour's near edge %.3f m from the centre" % [reach, gap_x])
	_expect(gap_x > 0.0 and reach < gap_x, "the shell never reaches the neighbouring card")
	var card_half_w: float = card._card_face_size().x * card.global_transform.basis.get_scale().x * 0.5
	_expect(reach > card_half_w, "but it is wider than the card it protects (%.3f > %.3f)" % [reach, card_half_w])
	_expect(float(shell.call("lowest_corner_height")) > 0.0, "the shell sits above the card face (the card cannot hide it)")

	# The timeline, frozen at chosen moments (sample(t) is deterministic).
	shell.set_process(false)
	shell.call("sample", 0.05)
	_expect(float(shell.call("shader_value", "build")) == 0.0, "at first only the comets: no panels yet")
	shell.call("sample", SHELL.BUILD_END)
	_expect(float(shell.call("shader_value", "build")) >= 1.0, "by BUILD_END every panel has started forming")
	_expect(float(shell.call("shader_value", "flare")) > 0.95, "and the outline flares as the shell closes")
	shell.call("sample", SHELL.LIFETIME)
	_expect(float(shell.call("shader_value", "fade")) >= 0.999, "at the end of its life it has faded out")
	shell.set_process(true)

	var started: int = Time.get_ticks_msec()
	await Vfx.idle()
	var held: float = (Time.get_ticks_msec() - started) / 1000.0
	_expect(held < SHELL.LIFETIME, "the cue releases the queue before the shell ends (%.2f s)" % held)
	await get_tree().create_timer(SHELL.LIFETIME + 0.2).timeout
	_expect(_shells().is_empty(), "the shell frees itself")
	_finish(game)


func _place(game: Node, field, id: int) -> Card:
	var c: Card = game.call("create_card", id, "player")
	game.add_child(c)
	field.play_card(c, false, false, false)
	return c


func _events() -> int:
	var n := 0
	for e in Vfx.get_events():
		if e.kind == VfxEvent.Kind.STATUS_APPLIED and e.status == "unbreakable":
			n += 1
	return n


func _find_cue() -> Node:
	for child in Vfx.get_children():
		if child.has_method("shell_count"):
			return child
	return null


func _shells() -> Array:
	var out: Array = []
	for child in get_tree().root.get_children():
		if child.name.begins_with("ProtectShell") and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _finish(game: Node) -> void:
	print("[ProtectVfx] RESULT: %s (%d checks, %d failed)" % ["all checks passed" if _fails == 0 else "FAILED", _checks, _fails])
	game.queue_free()
	get_tree().quit(0 if _fails == 0 else 1)
