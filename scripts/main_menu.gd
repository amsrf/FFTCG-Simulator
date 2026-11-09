extends Control
## Main menu. The UI is built in code so main_menu.tscn stays a bare Control.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(460, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "FF TCG Simulator"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Opponent: Mock   (simple AI in progress)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.75, 0.9)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	for preset in MatchSetup.get_presets():
		var button := Button.new()
		button.text = MatchSetup.describe_preset(preset)
		button.custom_minimum_size = Vector2(460, 44)
		button.pressed.connect(func(): MatchSetup.start_match(preset))
		box.add_child(button)

	box.add_child(HSeparator.new())
	_add_online_section(box)
	box.add_child(HSeparator.new())

	# TEST MODE gets its own screen: one board per mechanic. Keeping it out of the preset list above means the
	# everyday menu stays the short list of ways to start a real match.
	var test_button := Button.new()
	test_button.text = "Test Mode"
	test_button.custom_minimum_size = Vector2(460, 44)
	test_button.tooltip_text = "Curated boards for testing one mechanic at a time"
	test_button.pressed.connect(func(): MatchSetup.go_to_test_grounds())
	box.add_child(test_button)

	var demo_button := Button.new()
	demo_button.text = "Demos & Previews"
	demo_button.custom_minimum_size = Vector2(460, 44)
	demo_button.pressed.connect(MatchSetup.go_to_demo_menu)
	box.add_child(demo_button)

	var deck_button := Button.new()
	deck_button.text = "Deck Editor"
	deck_button.custom_minimum_size = Vector2(460, 44)
	deck_button.pressed.connect(func(): MatchSetup.go_to_deck_picker())
	box.add_child(deck_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(460, 44)
	quit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_button)

	var hint := Label.new()
	hint.text = "Esc in a match returns here."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.6, 0.6, 0.7)
	box.add_child(hint)

## PLAY ONLINE: host on a port, or join the host's IP. Both bring the custom deck from the Deck Editor. The match
## starts by itself once the two machines have agreed on it (MatchSetup.net emits match_ready).
func _add_online_section(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Play Online  (your custom deck)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var address := LineEdit.new()
	address.placeholder_text = "Host IP, e.g. 192.168.0.12"
	address.text = "127.0.0.1"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address)
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 7777
	port.tooltip_text = "Port"
	row.add_child(port)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host"
	host_button.custom_minimum_size = Vector2(0, 44)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.custom_minimum_size = Vector2(0, 44)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(join_button)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(0, 44)
	cancel_button.disabled = true
	buttons.add_child(cancel_button)

	var practice := CheckBox.new()
	practice.text = "Host on the practice board (for testing)"
	practice.tooltip_text = "Both players start with Backups and Forwards already on the field, using the practice decks"
	box.add_child(practice)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color(0.7, 0.85, 1.0)
	box.add_child(status)

	var set_busy := func(busy: bool) -> void:
		host_button.disabled = busy
		join_button.disabled = busy
		cancel_button.disabled = not busy
	var open := func() -> Node:
		var session: Node = MatchSetup.new_online_session()
		session.status_changed.connect(func(text: String): status.text = text)
		session.disconnected.connect(func(): set_busy.call(false))
		return session
	host_button.pressed.connect(func():
		var session: Node = open.call()
		session.practice_board = practice.button_pressed
		set_busy.call(session.host(int(port.value), MatchSetup.online_deck()) == OK))
	join_button.pressed.connect(func():
		var session: Node = open.call()
		set_busy.call(session.join(address.text.strip_edges(), int(port.value), MatchSetup.online_deck()) == OK))
	cancel_button.pressed.connect(func():
		MatchSetup.close_online()
		status.text = "Cancelled."
		set_busy.call(false))

	# STARTED FROM THE COMMAND LINE (tools/run_two_instances.bat): `-- --host [--practice]` or `-- --join[=IP]`, plus
	# an optional `--port=N`, click the right buttons by themselves.
	var auto := ""
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a == "--host":
			auto = "host"
		elif a == "--join" or a.begins_with("--join="):
			auto = "join"
			if a.contains("="):
				address.text = a.get_slice("=", 1)
		elif a == "--practice":
			practice.button_pressed = true
		elif a.begins_with("--port="):
			port.value = int(a.get_slice("=", 1))
	if auto == "host" and not _auto_started:
		_auto_started = true
		host_button.pressed.emit()
	elif auto == "join" and not _auto_started:
		_auto_started = true
		join_button.pressed.emit()

## Only the first time the menu opens: coming back to it after a match must not start another one.
static var _auto_started: bool = false

## The session outlives this menu (it carries the match), but these labels and buttons do not: stop it calling them.
func _exit_tree() -> void:
	var session: Node = MatchSetup.net
	if session == null or not is_instance_valid(session):
		return
	for sig in ["status_changed", "disconnected"]:
		for connection in session.get_signal_connection_list(sig):
			session.disconnect(sig, connection["callable"])
