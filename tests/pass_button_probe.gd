extends Node
## THE PASS BUTTON: only the player holding priority has one, and its label says what passing does (rule 11.1.7).
## - "Next Phase": the opponent has just passed and the stack is empty, so this pass ends the phase.
## - "Pass": otherwise (priority goes to the opponent, or the top of the stack resolves).

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const DISC_SOCKET := preload("res://scripts/ui/disc_socket.gd")

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
	await get_tree().create_timer(DISC_SOCKET.FULL_TURN_SECONDS + DISC_SOCKET.SETTLE_SECONDS + 0.1).timeout

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

	# A PRESS IS A FLICK, AND ONLY FORWARD: it leaves at PRESS_SPIN_SPEED and decelerates at a constant rate to a stop
	# on the STONE, holds PRESS_HOLD_SECONDS locked (claims wait, presses refused), then turns to what is wanted.
	await _settle()
	_expect(mine.is_active() and is_zero_approx(pivot.rotation.x), "settled gem-up before the press test")
	var spin: float = DISC_SOCKET.press_spin_seconds(0.0)
	_expect(spin > 0.8 and spin < 1.5, "a press spin from the gem lasts %.2f s" % spin)
	mine.pulse()
	await get_tree().create_timer(0.25).timeout
	var early: float = pivot.rotation.x
	var max_first := DISC_SOCKET.PRESS_SPIN_SPEED * TAU * 0.3
	_expect(early > 1.0 and early < max_first, "it leaves at the set speed (%.2f rad in 0.25 s)" % early)
	_expect(not mine.imprint_shown(), "the text is hidden while it spins fast (%.2f rad still to go)" % (5.0 * PI - early))
	await get_tree().create_timer(0.25).timeout
	var mid: float = pivot.rotation.x
	_expect(mine.imprint_shown() == (5.0 * PI - mid <= DISC_SOCKET.IMPRINT_RETURN_ANGLE),
		"the text comes back only for the last turn (%.2f rad to go, shown %s)" % [5.0 * PI - mid, mine.imprint_shown()])
	await get_tree().create_timer(0.25).timeout
	var late: float = pivot.rotation.x
	_expect(mid - early > late - mid and late > mid,
		"and it slows down steadily (+%.2f then +%.2f rad)" % [mid - early, late - mid])
	button._sync()
	_expect(mine.is_busy() and not button._area.input_ray_pickable, "while spinning the disc is locked and takes no press")
	await get_tree().create_timer(spin - 0.75 + 0.1).timeout
	_expect(is_equal_approx(pivot.rotation.x, PI) and not mine.is_active() and mine.wants_active() and mine.is_busy(),
		"it stops on the STONE although the button is still offered, and holds (rotation %.3f)" % pivot.rotation.x)
	mine.pulse()
	await get_tree().create_timer(DISC_SOCKET.PRESS_HOLD_SECONDS * 0.5).timeout
	_expect(is_equal_approx(pivot.rotation.x, PI), "a press during the hold is refused: still on the stone")
	await get_tree().create_timer(DISC_SOCKET.PRESS_HOLD_SECONDS * 0.5 + DISC_SOCKET.HALF_TURN_SECONDS
		+ DISC_SOCKET.SETTLE_SECONDS + 0.1).timeout
	_expect(not mine.is_busy() and mine.is_active() and is_zero_approx(pivot.rotation.x),
		"after the hold it is released and turns to the gem it is wanted on (rotation %.3f)" % pivot.rotation.x)
	var glow: ShaderMaterial = (mine.get_node("RingGlow") as MeshInstance3D).material_override
	button._on_hover(true)
	await get_tree().create_timer(0.3).timeout
	_expect(float(glow.get_shader_parameter("intensity")) > 0.9, "hover lights the ring (%.2f)" %
		float(glow.get_shader_parameter("intensity")))
	var pillar: ShaderMaterial = (mine.get_node("LightPillar") as MeshInstance3D).material_override
	_expect(float(pillar.get_shader_parameter("intensity")) > 0.9, "and throws light UP off it (pillar %.2f)" %
		float(pillar.get_shader_parameter("intensity")))
	_expect(mine.motes_emitting(), "motes of light rise while the ring's light is on")
	button.hide_button()      # taken away under the pointer: no mouse_exited will ever come
	mine.pulse()
	await get_tree().create_timer(0.35).timeout
	var went_forward: bool = pivot.rotation.x > 0.3
	_expect(not mine.imprint_shown(), "no priority after the press: the gem is blank while it spins")
	await get_tree().create_timer(DISC_SOCKET.press_spin_seconds(0.0) - 0.35 - DISC_SOCKET.SETTLE_SECONDS).timeout
	_expect(not mine.imprint_shown(), "and stays blank through the last turn (%.2f rad)" % pivot.rotation.x)
	await get_tree().create_timer(DISC_SOCKET.SETTLE_PERIOD * 0.25).timeout
	var overshoot: float = pivot.rotation.x - 5.0 * PI
	_expect(overshoot > 0.05 and overshoot < 0.3, "it overshoots the stone a little (%.3f rad past)" % overshoot)
	await get_tree().create_timer(DISC_SOCKET.SETTLE_SECONDS + DISC_SOCKET.PRESS_HOLD_SECONDS).timeout
	_expect(went_forward and not mine.is_active() and is_equal_approx(pivot.rotation.x, PI),
		"a press that takes the button away turns it forward to the stone (rotation %.3f)" % pivot.rotation.x)
	_expect(float(glow.get_shader_parameter("intensity")) < 0.05, "and the ring glow goes out with it")
	await get_tree().process_frame
	_expect(not mine.motes_emitting(), "and the motes stop with the light")
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
