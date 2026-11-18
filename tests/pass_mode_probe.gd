extends Node
## THE PASS MODE: Stop All / Smart / Pass All (Game.pass_mode, Assistant.auto_pass_would_answer) and the selector
## under the pass disc (scripts/ui/pass_mode_selector.gd).

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks := 0
var _fails := 0
var _game: Node = null

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[PassMode] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _card(id: int, side: String = "player") -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	return card

## Wait for the LIVE game to give the local player a priority window that `pred` accepts (passing by hand any window
## that is not it), then watch it for `seconds`. `during` runs once 0.3 s in. Returns [passed by itself, button ever
## up, seconds watched]. A window still open at the end is passed by hand so the game moves on.
var _ended := false

func _window(seconds: float, pred: Callable = Callable(), during: Callable = Callable()) -> Array:
	var agent = _game.get("player_agent")
	var assistant = _game.get("assistant")
	for _i in range(600):
		if bool(agent.get("_in_window")) and int(_game.get("priority_holder")) == 1:
			if not pred.is_valid() or pred.call():
				break
			assistant._pass_priority()
		await get_tree().create_timer(0.05).timeout
	_ended = false
	var raised := false
	var waited := 0.0
	var ran := false
	while not _ended and waited < seconds:
		raised = raised or assistant.passPhaseButton.visible
		if during.is_valid() and not ran and waited >= 0.3:
			ran = true
			during.call()
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var passed: bool = _ended
	if not _ended:
		assistant._pass_priority()
		await get_tree().process_frame
	return [passed, raised, waited]

func _key(code: Key, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	for _i in range(4):
		await get_tree().process_frame
	var field = _game.get("field")
	var assistant = _game.get("assistant")
	_game.priority_window_ended.connect(func(_acted: bool) -> void: _ended = true)

	# ---- THE SELECTOR -----------------------------------------------------------------------------------------
	var selector = assistant.pass_mode_selector
	_expect(selector != null, "the selector is built under the pass button")
	if selector != null:
		await get_tree().process_frame
		var panel: Control = selector.get("_panel")
		var buttons: Dictionary = selector.get("_buttons")
		_expect(buttons.size() == 4 and buttons.has("stop_all") and buttons.has("smart") and buttons.has("react") \
				and buttons.has("pass_all"), "it offers Stop All, Smart, React and Pass All")
		var socket: Node3D = assistant.get_node("ButtonStations/LocalForward")
		var cam: Camera3D = get_viewport().get_camera_3d()
		var disc: Vector2 = cam.unproject_position(socket.global_position)
		var view: Vector2 = get_viewport().get_visible_rect().size
		var centre_x: float = panel.position.x + panel.size.x * 0.5
		_expect(panel.visible and absf(centre_x - disc.x) < 4.0 or panel.position.x <= 8.5 \
				or panel.position.x + panel.size.x >= view.x - 8.5,
			"centred under the disc (selector x %.0f, disc x %.0f)" % [centre_x, disc.x])
		_expect(panel.position.y > disc.y and panel.position.y + panel.size.y <= view.y,
			"below the disc and on screen (top %.0f, disc %.0f, view %.0f)" % [panel.position.y, disc.y, view.y])
		_game.set("pass_mode", "pass_all")
		await get_tree().process_frame
		_expect((buttons["pass_all"] as Button).button_pressed and not (buttons["smart"] as Button).button_pressed,
			"it shows the match's mode when that changes")

	# ---- KEYS --------------------------------------------------------------------------------------------------------
	if selector != null:
		_game.set("pass_mode", "stop_all")
		var seen: Array = []
		for _i in range(4):
			selector._unhandled_key_input(_key(KEY_TAB))
			seen.append(str(_game.get("pass_mode")))
		_expect(seen == ["smart", "react", "pass_all", "stop_all"], "[Tab] cycles the modes in order (%s)" % str(seen))
		selector._unhandled_key_input(_key(KEY_TAB, true))
		_expect(str(_game.get("pass_mode")) == "pass_all", "[Shift+Tab] goes back")
		_game.set("pass_mode", "stop_all")
		var r0: Array = await _window(1.5, Callable(), func() -> void: selector._unhandled_key_input(_key(KEY_SPACE)))
		_expect(r0[0] and r0[2] < 1.0, "[Space] passes the window (%.1fs)" % r0[2])

	# ---- NOTHING TO PLAY ----------------------------------------------------------------------------------------
	_expect(not field.local_has_any_play(), "an empty board: nothing to play")
	_game.set("pass_mode", "stop_all")
	var r: Array = await _window(1.3)
	_expect(not r[0] and r[1], "STOP ALL: the window stays open with the button up, even with nothing to play")
	_game.set("pass_mode", "smart")
	r = await _window(2.0)
	_expect(r[0] and not r[1] and r[2] >= 0.5, "SMART: passed for them after a pause (%.1fs), button never up" % r[2])
	_game.set("pass_mode", "stop_all")
	r = await _window(2.5, Callable(), func() -> void: _game.set("pass_mode", "smart"))
	_expect(r[0], "switching STOP ALL -> SMART mid-window passes that window (%.1fs)" % r[2])
	_game.set("pass_mode", "smart")
	r = await _window(1.5, Callable(), func() -> void: _game.set("pass_mode", "stop_all"))
	_expect(not r[0], "switching SMART -> STOP ALL mid-window cancels the pending pass")

	# ---- SOMETHING TO PLAY ---------------------------------------------------------------------------------------
	var ifrit := _card(4)            # Summon, 1 fire: castable at instant speed
	_game.call("hand_for", 1).add_card(ifrit)
	var squall := _card(41, "opponent")
	field.play_card(squall, true, false, false)
	var mage := _card(3)             # fire Backup: pays for it
	field.play_card(mage, false, false, false)
	mage.untap()
	await get_tree().process_frame
	var has_play := func() -> bool: return field.local_has_any_play()
	var mine_main := func() -> bool:
		var ph = _game.get("phase")
		return field.local_has_any_play() and int(_game.get("turn_owner")) == 1 \
			and (ph == GlobalVariables.Phase.FIRST_MAIN_PHASE or ph == GlobalVariables.Phase.SECOND_MAIN_PHASE)
	var theirs := func() -> bool: return field.local_has_any_play() and int(_game.get("turn_owner")) == 2
	_game.set("pass_mode", "smart")
	r = await _window(1.3, has_play)
	_expect(not r[0] and r[1], "SMART stops when there is a play (Ifrit castable)")
	_game.set("pass_mode", "pass_all")
	r = await _window(1.3, mine_main)
	_expect(not r[0], "PASS ALL still stops in YOUR main phase with an empty stack when you have a play")
	_game.set("pass_mode", "pass_all")
	r = await _window(2.0, theirs)
	_expect(r[0] and not r[1], "PASS ALL passes a response window on the opponent's turn even with a play (%.1fs)" % r[2])

	# ---- REACT: pass unless the opponent put something on the stack ------------------------------------------------
	_game.set("pass_mode", "react")
	r = await _window(2.0, theirs)
	_expect(r[0], "REACT passes the opponent's turn while they do nothing, even with a play (%.1fs)" % r[2])
	# Decided by the predicate alone (the mock opponent never casts), INSIDE an open window on their turn (held open by
	# Stop All): an opponent's object on top of the stack stops React; without it React would pass.
	var stack = _game.get("stack")
	var probe_result := [null, null, false]
	var check := func() -> void:
		var a = _game.get("assistant")
		_game.set("pass_mode", "react")
		probe_result[0] = a.auto_pass_would_answer()
		var theirs_on_stack := _card(4, "opponent")
		stack.cards.append(theirs_on_stack)
		probe_result[1] = a.auto_pass_would_answer()
		probe_result[2] = field.local_has_any_play()
		stack.cards.erase(theirs_on_stack)
		theirs_on_stack.queue_free()
		_game.set("pass_mode", "stop_all")
	_game.set("pass_mode", "stop_all")
	await _window(0.6, theirs, check)
	_expect(probe_result[2] and probe_result[0] == true and probe_result[1] == false,
		"REACT stops when the opponent's object is on top of the stack (would pass: empty %s, theirs on top %s)"
		% [probe_result[0], probe_result[1]])

	# ---- PASS ALL lasts until YOUR next turn -----------------------------------------------------------------------
	_game.set("pass_mode", "smart")
	_game.set("pass_mode", "pass_all")
	var t_own: int = int(_game.get("turn_number"))
	for _i in range(800):
		if int(_game.get("turn_owner")) == 1 and int(_game.get("turn_number")) > t_own:
			break
		await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame
	_expect(str(_game.get("pass_mode")) == "smart",
		"PASS ALL went back to Smart when your turn started (now %s, turn %d)" % [_game.get("pass_mode"), _game.get("turn_number")])

	print("[PassMode] %d checks | failures: %d" % [_checks, _fails])
	print("[PassMode] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
