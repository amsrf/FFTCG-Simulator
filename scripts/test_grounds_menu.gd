extends Control
## TEST MODE — the screen behind the main menu's "Test Mode" button.
##
## One board per mechanic, listed from the registry in scripts/test_grounds.gd. Kept off the main menu on purpose: the
## everyday menu stays the short list of ways to start a real match, and these are the boards you open while building
## a mechanic.

const GROUNDS := preload("res://scripts/test_grounds.gd")

var _ground_buttons: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(760, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "Test Mode"
	title.add_theme_font_size_override("font_size", 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "One board per mechanic — curated so unrelated cards do not act."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.75, 0.9)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	if GROUNDS.names().is_empty():
		var empty := Label.new()
		empty.text = "No grounds registered."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)

	for name in GROUNDS.names():
		var button := Button.new()
		button.text = GROUNDS.title(name)
		button.custom_minimum_size = Vector2(760, 42)
		button.tooltip_text = GROUNDS.blurb(name)
		button.pressed.connect(func(): MatchSetup.start_match(name))
		box.add_child(button)
		_ground_buttons.append(button)

		var blurb := Label.new()
		blurb.text = GROUNDS.blurb(name)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(760, 0)
		blurb.modulate = Color(0.66, 0.7, 0.82)
		blurb.add_theme_font_size_override("font_size", 13)
		box.add_child(blurb)

	box.add_child(HSeparator.new())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(760, 42)
	back.pressed.connect(func(): MatchSetup.go_to_menu())
	box.add_child(back)


## Exposed for the probe: one entry per registered ground.
func ground_button_count() -> int:
	return _ground_buttons.size()

func ground_button_text(index: int) -> String:
	if index < 0 or index >= _ground_buttons.size():
		return ""
	return (_ground_buttons[index] as Button).text
