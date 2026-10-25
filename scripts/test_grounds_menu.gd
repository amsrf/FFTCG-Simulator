extends Control
## TEST MODE — the screen behind the main menu's "Test Mode" button.
##
## Grounds are grouped into categories and laid out in columns. The registry owns the category mapping, so adding a
## ground still means one entry there and one dispatch arm; this screen only decides how the groups are drawn.

const GROUNDS := preload("res://scripts/test_grounds.gd")
const COLUMN_WIDTH := 300.0
const COLUMNS := 4

var _ground_buttons: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(COLUMN_WIDTH * COLUMNS + 60.0, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "Test Mode"
	title.add_theme_font_size_override("font_size", 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "One board per mechanic — grouped by the kind of rule being exercised."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.75, 0.9)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	if GROUNDS.names().is_empty():
		var empty := Label.new()
		empty.text = "No grounds registered."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)

	for category in GROUNDS.categories():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		grid.add_child(column)

		var heading := Label.new()
		heading.text = category
		heading.add_theme_font_size_override("font_size", 19)
		heading.add_theme_color_override("font_color", Color(0.86, 0.89, 1.0))
		column.add_child(heading)
		column.add_child(HSeparator.new())

		for name in GROUNDS.names_in(category):
			var button := Button.new()
			button.text = GROUNDS.title(name)
			button.custom_minimum_size = Vector2(COLUMN_WIDTH, 40)
			button.tooltip_text = GROUNDS.blurb(name)
			button.pressed.connect(func(): MatchSetup.start_match(name))
			column.add_child(button)
			_ground_buttons.append(button)

			var blurb := Label.new()
			blurb.text = GROUNDS.blurb(name)
			blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			blurb.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
			blurb.modulate = Color(0.66, 0.7, 0.82)
			blurb.add_theme_font_size_override("font_size", 12)
			column.add_child(blurb)

	box.add_child(HSeparator.new())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(COLUMN_WIDTH * COLUMNS + 60.0, 42)
	back.pressed.connect(func(): MatchSetup.go_to_menu())
	box.add_child(back)


## Exposed for the probe: one entry per registered ground.
func ground_button_count() -> int:
	return _ground_buttons.size()

func ground_button_text(index: int) -> String:
	if index < 0 or index >= _ground_buttons.size():
		return ""
	return (_ground_buttons[index] as Button).text

## Exposed for the probe: the grid really is using the requested number of columns.
func column_count() -> int:
	for child in get_children():
		var found: GridContainer = _find_grid(child)
		if found != null:
			return found.columns
	return 0

func _find_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found: GridContainer = _find_grid(child)
		if found != null:
			return found
	return null
