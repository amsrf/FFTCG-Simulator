extends CanvasLayer
## Pick one Element. Used by "name an Element" effects such as Mime 173.
##
## The UI is intentionally small: six choices, a selected accent border, Confirm and Cancel. The choice goes through
## Agent.choose_element(), so the human UI, the AI and a future remote player all share the same seam.

signal finished(element: String)

const CHOOSE_NONE := ""
const PANEL_WIDTH := 640.0
const TEXT_COLOUR := Color(0.90, 0.93, 0.98)
const IDLE_BORDER := Color(0.30, 0.33, 0.40)
const HOVER_BORDER := Color(0.55, 0.60, 0.70)
const SELECTED_BORDER := Color(1.0, 0.45, 0.05)
const SELECTED_BG := Color(0.20, 0.14, 0.08)
const IDLE_BG := Color(0.09, 0.10, 0.14)

const LABELS := {
	"火": "Fire", "氷": "Ice", "風": "Wind", "土": "Earth",
	"雷": "Lightning", "水": "Water", "光": "Light", "闇": "Dark",
}

var _options: Array = []
var _selected: int = -1
var _buttons: Array = []
var _confirm: Button = null
var _title: Label = null
var _list: HBoxContainer = null


func _ready() -> void:
	layer = 12
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_title)

	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	column.add_child(_list)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(130, 44)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(cancel_choice)
	row.add_child(cancel)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(160, 44)
	_confirm.add_theme_font_size_override("font_size", 18)
	_confirm.disabled = true
	_confirm.pressed.connect(confirm_choice)
	row.add_child(_confirm)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.06, 0.08, 0.98)
	s.border_color = Color(0.55, 0.60, 0.72)
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	return s


func open(options: Array, prompt: String = "Choose an Element") -> void:
	_options = options.duplicate()
	_title.text = prompt
	for i in range(_options.size()):
		var element: String = str(_options[i])
		var button := Button.new()
		button.text = "%s\n%s" % [element, LABELS.get(element, element)]
		button.custom_minimum_size = Vector2(82, 62)
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", TEXT_COLOUR)
		button.pressed.connect(func() -> void: select_element(i))
		_list.add_child(button)
		_buttons.append(button)
	_refresh_borders()


func _border_style(selected: bool, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SELECTED_BG if selected else IDLE_BG
	s.border_color = SELECTED_BORDER if selected else (HOVER_BORDER if hover else IDLE_BORDER)
	s.set_border_width_all(3 if selected else 1)
	s.set_corner_radius_all(9)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _refresh_borders() -> void:
	for i in range(_buttons.size()):
		var button: Button = _buttons[i]
		var selected: bool = i == _selected
		button.add_theme_stylebox_override("normal", _border_style(selected, false))
		button.add_theme_stylebox_override("hover", _border_style(selected, true))
		button.add_theme_stylebox_override("pressed", _border_style(selected, true))
		button.add_theme_stylebox_override("focus", _border_style(selected, false))
	if _confirm != null:
		_confirm.disabled = _selected < 0


func select_element(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	_selected = index
	_refresh_borders()


func confirm_choice() -> void:
	if _selected < 0:
		return
	_finish(str(_options[_selected]))


func cancel_choice() -> void:
	_finish(CHOOSE_NONE)


func _finish(element: String) -> void:
	visible = false
	finished.emit(element)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_choice()
		get_viewport().set_input_as_handled()


# --- probe accessors ---------------------------------------------------------------------------------------

func option_count() -> int:
	return _buttons.size()


func selected_index() -> int:
	return _selected


func confirm_enabled() -> bool:
	return _confirm != null and not _confirm.disabled


func option_border_colour(index: int) -> Color:
	if index < 0 or index >= _buttons.size():
		return Color.TRANSPARENT
	var style = _buttons[index].get_theme_stylebox("normal")
	return style.border_color if style is StyleBoxFlat else Color.TRANSPARENT
