extends Control
const CATALOG := preload("res://scripts/demo_catalog.gd")
var _rows: Array[Button] = []
var _empty: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Demos & Previews"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Choose a demo. Use the Demos button or F8 to come back and switch."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.7, 0.75, 0.9)
	box.add_child(hint)
	var search := LineEdit.new()
	search.placeholder_text = "Search demos…"
	search.clear_button_enabled = true
	search.text_changed.connect(_filter)
	box.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for entry in CATALOG.entries():
		var button := Button.new()
		button.text = entry.title
		button.tooltip_text = entry.path
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 44
		button.pressed.connect(MatchSetup.start_demo.bind(entry.path))
		list.add_child(button)
		_rows.append(button)
	_empty = Label.new()
	_empty.text = "No matching demos."
	list.add_child(_empty)
	_filter("")
	var back := Button.new()
	back.text = "Back to Main Menu"
	back.custom_minimum_size.y = 44
	back.pressed.connect(MatchSetup.go_to_menu)
	box.add_child(back)
	search.grab_focus()

func _filter(query: String) -> void:
	var count := 0
	for button in _rows:
		button.visible = query.strip_edges().is_empty() or query.to_lower() in button.text.to_lower()
		if button.visible:
			count += 1
	_empty.visible = count == 0

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		MatchSetup.go_to_menu()
