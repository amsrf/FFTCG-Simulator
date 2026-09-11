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
