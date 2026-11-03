extends CanvasLayer
## Declare a number for an 《X》 cost. One value, +/- buttons, Confirm and Cancel.
##
## The declaration happens BEFORE payment: once confirmed, the ability's cost becomes {"neutral": X}, so the normal
## exact-payment pipeline can take over. The choice goes through Agent.choose_number(), which keeps human UI, AI and a
## future remote player on the same seam.

signal finished(value: int)

const CHOOSE_NONE := -1
const PANEL_WIDTH := 420.0
const VALUE_FONT := 34

var _minimum: int = 0
var _maximum: int = 0
var _value: int = 0
var _title: Label = null
var _value_label: Label = null
var _range_label: Label = null
var _minus: Button = null
var _plus: Button = null
var _confirm: Button = null


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

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)

	_minus = Button.new()
	_minus.text = "−"
	_minus.custom_minimum_size = Vector2(58, 52)
	_minus.add_theme_font_size_override("font_size", 26)
	_minus.pressed.connect(func() -> void: bump(-1))
	row.add_child(_minus)

	_value_label = Label.new()
	_value_label.custom_minimum_size = Vector2(90, 52)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_size_override("font_size", VALUE_FONT)
	_value_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(_value_label)

	_plus = Button.new()
	_plus.text = "+"
	_plus.custom_minimum_size = Vector2(58, 52)
	_plus.add_theme_font_size_override("font_size", 26)
	_plus.pressed.connect(func() -> void: bump(1))
	row.add_child(_plus)

	_range_label = Label.new()
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_range_label.add_theme_font_size_override("font_size", 15)
	_range_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84))
	column.add_child(_range_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(130, 44)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(cancel_choice)
	buttons.add_child(cancel)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(160, 44)
	_confirm.add_theme_font_size_override("font_size", 18)
	_confirm.pressed.connect(confirm_choice)
	buttons.add_child(_confirm)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.06, 0.08, 0.98)
	s.border_color = Color(0.55, 0.60, 0.72)
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	return s


func open(minimum: int, maximum: int, prompt: String = "Choose a number", initial: int = -1) -> void:
	_minimum = mini(minimum, maximum)
	_maximum = maxi(minimum, maximum)
	_value = initial if initial >= _minimum and initial <= _maximum else _maximum
	_title.text = prompt
	_range_label.text = "from %d to %d" % [_minimum, _maximum]
	_refresh()


func bump(delta: int) -> void:
	_value = clampi(_value + delta, _minimum, _maximum)
	_refresh()


func _refresh() -> void:
	if _value_label != null:
		_value_label.text = str(_value)
	if _minus != null:
		_minus.disabled = _value <= _minimum
	if _plus != null:
		_plus.disabled = _value >= _maximum
	if _confirm != null:
		_confirm.disabled = _value < _minimum or _value > _maximum


func confirm_choice() -> void:
	_finish(_value)


func cancel_choice() -> void:
	_finish(CHOOSE_NONE)


func _finish(value: int) -> void:
	visible = false
	finished.emit(value)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_choice()
		get_viewport().set_input_as_handled()


# --- probe accessors ---------------------------------------------------------------------------------------

func value() -> int:
	return _value


func minimum() -> int:
	return _minimum


func maximum() -> int:
	return _maximum


func confirm_enabled() -> bool:
	return _confirm != null and not _confirm.disabled
