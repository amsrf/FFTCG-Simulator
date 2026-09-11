extends Node3D
class_name BigButton

## Emitted whenever the button is actually pressed (in addition to any
## callback configured through configure()/set_on_press_callback()).
signal pressed

const VIEWPORT_SIZE := Vector2i(1024, 1024)
const BASE_FONT_SIZE := 96
const MIN_FONT_SIZE := 24

var _disabled := false
var _hovered := false
var _on_press_callback: Callable
var _background_material: StandardMaterial3D
var _base_color := Color(0.52549, 0, 0.223529, 1)
var _base_scale := Vector3.ONE

func _ready():
	# Smaller viewport than the original 2048x2048 stub keeps text crisp while
	# using a quarter of the memory per button.
	$ButtonTextViewport.size = VIEWPORT_SIZE

	var text_quad = $TextDisplay
	var text_material = StandardMaterial3D.new()
	text_material.albedo_texture = $ButtonTextViewport.get_texture()
	text_material.flags_unshaded = true
	text_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	$ButtonTextViewport.transparent_bg = true
	text_quad.material_override = text_material

	# Make the text fill the whole viewport so long labels center correctly.
	var control: Control = $ButtonTextViewport/Control
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = $ButtonTextViewport/Control/CenterContainer
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	_background_material = $Background/MeshInstance3D.get_surface_override_material(0)
	if _background_material != null:
		_base_color = _background_material.albedo_color
	_base_scale = scale

	$Area3D.button_pressed.connect(_on_area_pressed)
	$Area3D.button_hovered.connect(_on_area_hovered)
	$Area3D.button_unhovered.connect(_on_area_unhovered)

func configure(text: String, callback: Callable = Callable(), enabled: bool = true):
	set_text(text)
	set_on_press_callback(callback)
	set_disabled(not enabled)

func set_on_press_callback(callback: Callable):
	_on_press_callback = callback
	if not _disabled:
		$Area3D.set_on_press_callback(callback)

func set_text(text):
	var label: Label = $ButtonTextViewport/Control/CenterContainer/Label
	label.text = text
	_autofit_label(label)

func _autofit_label(label: Label):
	var font: Font = label.get_theme_font("font")
	var max_width := float(VIEWPORT_SIZE.x) * 0.85
	var font_size := BASE_FONT_SIZE
	while font_size > MIN_FONT_SIZE and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		font_size -= 4
	label.add_theme_font_size_override("font_size", font_size)

func set_disabled(value: bool):
	_disabled = value
	if _disabled:
		$Area3D.set_on_press_callback(Callable())
		_dim_to(_base_color.darkened(0.55))
	else:
		$Area3D.set_on_press_callback(_on_press_callback)
		_dim_to(_base_color)

func show_button():
	visible = true
	$Area3D.set_input_enabled(true)

func hide_button():
	visible = false
	$Area3D.set_input_enabled(false)

func _on_area_pressed():
	pressed.emit()
	_pulse()

func _on_area_hovered():
	_hovered = true
	if _disabled:
		return
	_tween_scale(_base_scale * 1.06)
	_dim_to(_base_color.lightened(0.25))

func _on_area_unhovered():
	_hovered = false
	if _disabled:
		return
	_tween_scale(_base_scale)
	_dim_to(_base_color)

func _pulse():
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale * 0.92, 0.06)
	tween.tween_property(self, "scale", _base_scale, 0.12)

func _tween_scale(target: Vector3):
	var tween := create_tween()
	tween.tween_property(self, "scale", target, 0.1)

func _dim_to(target: Color):
	if _background_material == null:
		return
	var tween := create_tween()
	tween.tween_property(_background_material, "albedo_color", target, 0.12)
