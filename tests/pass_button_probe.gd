extends Node
## THE PASS BUTTON: only the player holding priority has one, and its label says what passing does (rule 11.1.7).
## - "Next Phase": the opponent has just passed and the stack is empty, so this pass ends the phase.
## - "Pass": otherwise (priority goes to the opponent, or the top of the stack resolves).

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[PassButton] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _label(button) -> String:
	return str(button.get_text())

## A flip is 0.42 s; wait it out (plus the end-of-frame claim).
func _settle() -> void:
	await get_tree().create_timer(0.6).timeout

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for _i in range(4):
		await get_tree().process_frame
	var assistant = game.assistant
	var button = assistant.passPhaseButton
	var stack = game.stack
	GlobalVariables.refresh_mode()

	game.turn_owner = 1
	game.other_player_passed = false
	game.priority_holder = 1
	print("[PassButton] first pass of the phase: visible=%s text=%s" % [button.visible, _label(button)])
	_expect(button.visible and _label(button) == "Pass", "my priority, nobody has passed yet: Pass (it goes to the opponent)")
	game.other_player_passed = true
	game.priority_holder = 1
	_expect(button.visible and _label(button) == "Next Phase", "the opponent just passed, empty stack: Next Phase")

	# THE BOARD DISCS (scripts/ui/disc_socket.gd): the pass button is the large local disc turned gem-up, its label
	# on the wood says what it does, and a hide + show inside ONE frame must not turn the disc at all (claims are
	# coalesced to the end of the frame, or show_modal()'s hide-everything-first would make it twitch).
	var stations = assistant.button_stations
	var mine = stations.local_forward
	var theirs = stations.opponent_forward
	await _settle()
	_expect(mine.is_active() and mine.label_text() == "Next Phase",
		"my priority: the large disc is gem-up and its label reads Next Phase (got %s, '%s')" % [mine.is_active(), mine.label_text()])
	_expect(not theirs.wants_active(), "and the opponent's disc is down")
	_expect(not stations.local_cancel.wants_active() and not stations.opponent_cancel.wants_active(),
		"neither Cancel disc is up with no prompt open")
	button.hide_button()
	button.show_button()
	await get_tree().process_frame
	await get_tree().process_frame
	var pivot: Node3D = mine.get_node("Pivot")
	_expect(is_zero_approx(pivot.rotation.x),
		"a hide + show in one frame leaves the disc still (rotation %.3f)" % pivot.rotation.x)

	game.priority_holder = 2
	_expect(not button.visible, "the moment the opponent holds priority, I have no button")
	await _settle()
	_expect(not mine.is_active() and is_equal_approx(pivot.rotation.x, PI),
		"my disc has turned to its stone face (rotation %.3f)" % pivot.rotation.x)
	_expect(theirs.is_active(), "and the opponent's forward disc is up: they hold priority")
	_expect(not stations.opponent_cancel.wants_active(), "their Cancel never lights")
	GlobalVariables.refresh_mode()
	assistant._on_player_mode_change(GlobalVariables.get_player_mode())
	_expect(not button.visible, "and a free moment on screen does not bring it back")

	var effect: Card = game.create_card(4, "player")
	stack.add_child(effect)
	stack.cards.append(effect)
	game.priority_holder = 1
	print("[PassButton] stack waiting: visible=%s text=%s" % [button.visible, _label(button)])
	_expect(button.visible and _label(button) == "Pass", "the opponent passed but something is on the stack: Pass (it resolves)")
	stack.cards.erase(effect)
	effect.queue_free()

	game.turn_owner = 2
	game.other_player_passed = false
	game.priority_holder = 1
	_expect(button.visible and _label(button) == "Pass", "the opponent's turn, they acted: Pass (got %s)" % _label(button))

	# A PRESS ALWAYS SPINS, AND ONLY FORWARD: a full turn when the button stays offered, a half turn when the press
	# takes it away. The angle never runs backwards.
	await _settle()
	_expect(mine.is_active() and is_zero_approx(pivot.rotation.x), "settled gem-up before the press test")
	mine.pulse()
	await get_tree().create_timer(0.35).timeout
	var mid: float = pivot.rotation.x
	_expect(mid > PI * 0.5 and mid < PI * 1.75, "a press that keeps the button offered spins it (mid-spin %.2f rad)" % mid)
	await get_tree().create_timer(0.6).timeout
	_expect(mine.is_active() and is_zero_approx(pivot.rotation.x),
		"and it comes all the way round to the gem: a full 360 (rotation %.3f)" % pivot.rotation.x)
	var glow: ShaderMaterial = (mine.get_node("RingGlow") as MeshInstance3D).material_override
	button._on_hover(true)
	await get_tree().create_timer(0.3).timeout
	_expect(float(glow.get_shader_parameter("intensity")) > 0.9, "hover lights the ring (%.2f)" %
		float(glow.get_shader_parameter("intensity")))
	button.hide_button()      # taken away under the pointer: no mouse_exited will ever come
	mine.pulse()
	await get_tree().create_timer(0.35).timeout
	var went_forward: bool = pivot.rotation.x > 0.3
	await _settle()
	_expect(went_forward and not mine.is_active() and is_equal_approx(pivot.rotation.x, PI),
		"a press that takes the button away turns it forward to the stone (rotation %.3f)" % pivot.rotation.x)
	_expect(float(glow.get_shader_parameter("intensity")) < 0.05, "and the ring glow goes out with it")
	button.show_button()
	await _settle()
	_expect(mine.is_active() and is_zero_approx(pivot.rotation.x), "offered again: gem-up, still turning forward")

	game.match_over = true
	game.priority_holder = 1
	_expect(not button.visible, "no button once the match is over")
	game.priority_holder = 2
	_expect(not theirs.wants_active(), "and the opponent's disc stays down once the match is over")

	print("[PassButton] %d checks | failures: %d" % [_checks, _fails])
	print("[PassButton] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
