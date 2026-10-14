class_name CardTile
extends Control
## Compact battlefield tile: art crop + element-tinted frame + name strip + power badge.
##
## ADAPTED FROM the original CardTile: the structure and every drawing decision are unchanged, and what changed is that the
## values worth tuning are @export now instead of consts, so the look can be dialled in from the Inspector without editing
## this file. Plus a debug overlay that draws the art crop rectangle over the FULL card, which is the only way to see
## exactly what part of the scan is being used.
##
## Add a plain Control node with this script, or CardTile.new(). Note the root MUST be a Control — a Control script
## cannot be attached to a Node3D.

signal hovered(tile: CardTile)
signal unhovered(tile: CardTile)

@export_group("Frame")
## Optional decorative frame, drawn over the art and tinted per element. Tiles render fine without it.
@export var frame_texture: Texture2D:
	set(value):
		frame_texture = value
		if _frame:
			_frame.texture = value

@export_group("Size")
## Same 10:7 ratio as the frame texture (320x224).
@export var forward_size := Vector2(140, 98)
@export var backup_size := Vector2(120, 84)

@export_group("Art")
## Part of the full card image to show, as FRACTIONS of width/height: x, y, width, height. Default is between the name bar
## and the rules text. Tweak if the scans differ — and turn on Debug Show Crop to see it.
@export var art_region := Rect2(0.03, 0.11, 0.94, 0.48):
	set(value):
		art_region = value
		if _art:
			_apply_art_crop()

## Draws art_region over the whole card, on top of the tile, so the crop can be judged directly.
@export var debug_show_crop: bool = false:
	set(value):
		debug_show_crop = value
		if _crop_debug:
			_crop_debug.visible = value

@export_group("Name strip")
@export var name_font_size: int = 12:
	set(value):
		name_font_size = value
		if _name_label:
			_name_label.add_theme_font_size_override("font_size", value)

@export_range(0.0, 1.0, 0.01) var strip_opacity: float = 0.62:
	set(value):
		strip_opacity = value
		_refresh_strip()

@export var strip_height: float = 20.0:
	set(value):
		strip_height = value
		_refresh_strip()

@export_group("Power badge")
@export var badge_size := Vector2(68, 20)
@export var badge_font_size: int = 12:
	set(value):
		badge_font_size = value
		if _power_label:
			_power_label.add_theme_font_size_override("font_size", value)
			_damage_label.add_theme_font_size_override("font_size", value)

@export_group("Element")
var _unused_element_group_anchor: int = 0

@export var element_colors := {
	"fire": Color("e0503a"),
	"ice": Color("6fd0f0"),
	"wind": Color("4fbf6a"),
	"earth": Color("c9a23a"),
	"lightning": Color("a45be0"),
	"water": Color("3a78e0"),
	"light": Color("f2efe0"),
	"dark": Color("4a4458"),
}

@export_group("Filtering")
## NEAREST keeps the scan crisp at these small sizes; LINEAR smooths it. Which is better depends on how the cards were
## scanned, so it is a switch rather than a decision.
@export_enum("Nearest", "Linear") var texture_filter_mode: int = 1:
	set(value):
		texture_filter_mode = value
		_apply_texture_filter()

var _glow: Panel
var _art: TextureRect
var _frozen: ColorRect
var _frame: TextureRect
var _strip: Panel
var _name_label: Label
var _element_dot: Panel
var _power_panel: Panel
var _power_label: Label
var _damage_label: Label
var _crop_debug: Control

## The full card image as handed to setup(), kept so the crop can be redrawn when art_region changes.
var _card_texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	mouse_entered.connect(func(): hovered.emit(self))
	mouse_exited.connect(func(): unhovered.emit(self))


func setup(card_tex: Texture2D, display_name: String, element: String,
		is_forward: bool, power_text: String = "", damage: int = 0) -> void:
	_card_texture = card_tex
	_apply_art_crop()

	_name_label.text = display_name

	var c: Color = element_colors.get(element.to_lower(), Color.WHITE)
	_frame.self_modulate = c
	(_element_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = c
	(_power_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = c

	# Backups have no power, so only Forwards get the badge.
	_power_panel.visible = is_forward and power_text != ""
	_power_label.text = power_text
	set_damage(damage)

	custom_minimum_size = forward_size if is_forward else backup_size
	size = custom_minimum_size
	pivot_offset = size / 2.0
	_refresh_strip()
	_refresh_badge()
	_apply_texture_filter()
	_apply_crop_debug()


## Crop the art out of the full card image — no extra files needed.
func _apply_art_crop() -> void:
	if _card_texture == null or _art == null:
		return
	var s := _card_texture.get_size()
	var atlas := AtlasTexture.new()
	atlas.atlas = _card_texture
	atlas.region = Rect2(
		s.x * art_region.position.x, s.y * art_region.position.y,
		s.x * art_region.size.x, s.y * art_region.size.y)
	_art.texture = atlas


func _refresh_strip() -> void:
	if _strip == null:
		return
	_strip.offset_top = 4
	_strip.offset_bottom = 4 + strip_height
	var sb := _strip.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = Color(0, 0, 0, strip_opacity)


func _refresh_badge() -> void:
	if _power_panel == null:
		return
	_power_panel.offset_left = -(badge_size.x + 6.0)
	_power_panel.offset_right = -6
	_power_panel.offset_top = -(badge_size.y + 6.0)
	_power_panel.offset_bottom = -6


func _apply_texture_filter() -> void:
	var mode: int = CanvasItem.TEXTURE_FILTER_NEAREST if texture_filter_mode == 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	for node in [_art, _frame]:
		if node != null:
			(node as CanvasItem).texture_filter = mode


## Draws the crop region over the whole card, scaled to fit the tile. Gold outline, so it cannot be confused with anything
## the tile draws itself.
func _apply_crop_debug() -> void:
	if _crop_debug == null:
		return
	if _card_texture == null:
		_crop_debug.visible = false
		return
	var full := TextureRect.new()
	full.texture = _card_texture
	full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in _crop_debug.get_children():
		c.queue_free()
	_crop_debug.add_child(full)

	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.85, 0.2, 0.35)
	# Positioned in the fitted image's own box, which is what the stretch mode above produces.
	var box: Vector2 = _crop_debug.size
	var img: Vector2 = _card_texture.get_size()
	var scale_fit: float = minf(box.x / maxf(img.x, 1.0), box.y / maxf(img.y, 1.0))
	var drawn: Vector2 = img * scale_fit
	var origin: Vector2 = (box - drawn) / 2.0
	marker.position = origin + Vector2(img.x * art_region.position.x, img.y * art_region.position.y) * scale_fit
	marker.size = Vector2(img.x * art_region.size.x, img.y * art_region.size.y) * scale_fit
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crop_debug.add_child(marker)
	_crop_debug.visible = debug_show_crop


func set_power_text(text: String) -> void:
	_power_label.text = text


func set_damage(value: int) -> void:
	_damage_label.text = str(value)
	# Gray when untouched, red once the card has taken damage.
	var c := Color("ff6b6b") if value > 0 else Color(1, 1, 1, 0.55)
	_damage_label.add_theme_color_override("font_color", c)


func set_dull(on: bool) -> void:
	modulate = Color(0.55, 0.55, 0.65) if on else Color.WHITE


func set_frozen(on: bool) -> void:
	_frozen.visible = on


func set_highlight(on: bool) -> void:
	_glow.visible = on


# --- building the node tree -------------------------------------------------

func _fill(c: Control, inset: float = 0.0) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = inset
	c.offset_top = inset
	c.offset_right = -inset
	c.offset_bottom = -inset
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _box(bg: Color, radius: int, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	return sb


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _build() -> void:
	# Highlight glow (e.g. "can be played / selected"), hidden by default.
	_glow = Panel.new()
	_fill(_glow)
	var gs := _box(Color(0, 0, 0, 0), 9, Color("3dffb0"), 3)
	gs.shadow_color = Color(0.24, 1.0, 0.69, 0.6)
	gs.shadow_size = 8
	_glow.add_theme_stylebox_override("panel", gs)
	_glow.visible = false
	add_child(_glow)

	# Art, inset slightly so the rounded frame hides the corners.
	_art = TextureRect.new()
	_fill(_art, 3)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_art)

	_frozen = ColorRect.new()
	_fill(_frozen, 3)
	_frozen.color = Color(0.5, 0.85, 1.0, 0.28)
	_frozen.visible = false
	add_child(_frozen)

	# Frame texture, tinted per element.
	_frame = TextureRect.new()
	_fill(_frame)
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.texture = frame_texture
	add_child(_frame)

	# Name strip at the top.
	_strip = Panel.new()
	_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip.offset_left = 4
	_strip.offset_right = -4
	_strip.offset_top = 4
	_strip.offset_bottom = 24
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, strip_opacity), 5))
	add_child(_strip)

	_name_label = _label(name_font_size)
	_fill(_name_label)
	_name_label.offset_left = 6
	_name_label.offset_right = -22
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip.add_child(_name_label)

	# Small element dot at the right end of the strip.
	_element_dot = Panel.new()
	_element_dot.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_element_dot.offset_left = -17
	_element_dot.offset_right = -5
	_element_dot.offset_top = -6
	_element_dot.offset_bottom = 6
	_element_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_dot.add_theme_stylebox_override("panel", _box(Color.WHITE, 6))
	_strip.add_child(_element_dot)

	# Power / damage badge, bottom-right: "7000 | 0".
	_power_panel = Panel.new()
	_power_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_power_panel.offset_left = -74
	_power_panel.offset_right = -6
	_power_panel.offset_top = -26
	_power_panel.offset_bottom = -6
	_power_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.05, 0.1, 0.9), 6, Color.WHITE, 2))
	_power_panel.visible = false
	add_child(_power_panel)

	var row := HBoxContainer.new()
	_fill(row, 3)
	row.add_theme_constant_override("separation", 4)
	_power_panel.add_child(row)

	_power_label = _label(badge_font_size)
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_power_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(1, 0)
	divider.color = Color(1, 1, 1, 0.35)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)

	_damage_label = _label(badge_font_size)
	_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_label.custom_minimum_size = Vector2(16, 0)
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.text = "0"
	row.add_child(_damage_label)

	# Last, so it draws over everything including the frame.
	_crop_debug = Control.new()
	_fill(_crop_debug)
	_crop_debug.visible = false
	add_child(_crop_debug)
