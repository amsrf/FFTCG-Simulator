extends CanvasLayer
## Lives under MatchSetup so a demo's own reload preserves navigation.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	var corner := Control.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	var back := Button.new()
	back.text = "Demos  ·  F8"
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	back.offset_left = -180
	back.offset_top = -58
	back.offset_right = -20
	back.offset_bottom = -16
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(MatchSetup.go_to_demo_menu)
	corner.add_child(back)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		MatchSetup.go_to_demo_menu()
