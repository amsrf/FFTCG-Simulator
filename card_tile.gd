class_name CardTile
extends Control
## Compact battlefield tile: name bar + art crop + element border + power badge.
##
## ADAPTED FROM the original CardTile. Two changes on top of the @export pass:
##
##   * THE NAME HAS ITS OWN BAR. It used to be drawn over the art, which cost the art its top edge. The bar is a real row
##     now and the tile is taller by its height — see name_bar_height and the sizes, which measure the WHOLE tile.
##   * THE BORDER IS DRAWN, NOT TINTED. The original tinted frame_texture per element, which does nothing when there is no
##     frame texture — and there is none in this repo, so tiles had no element border at all. A StyleBoxFlat border needs
##     no texture and always shows. frame_texture still works if you ever add one; it draws under the border.
##
## Add a plain Control node with this script, or CardTile.new(). The root MUST be a Control — a Control script cannot be
## attached to a Node3D.

signal hovered(tile: CardTile)
signal unhovered(tile: CardTile)

@export_group("Size")
## THE WHOLE TILE, name bar included. The art cell is whatever is left after the bar and the insets.
@export var forward_size := Vector2(140, 124)
@export var backup_size := Vector2(120, 106)

@export_group("Name bar")
## Height of the bar across the top. The tile grows by this much, so the art keeps its own height.
@export var name_bar_height: float = 26.0:
	set(value):
		name_bar_height = value
		_apply_layout()

@export var name_font_size: int = 13:
	set(value):
		name_font_size = value
		if _name_label:
			_name_label.add_theme_font_size_override("font_size", value)

@export_range(0.0, 1.0, 0.01) var name_bar_opacity: float = 0.72:
	set(value):
		name_bar_opacity = value
		_apply_layout()

@export var name_bar_color := Color(0.06, 0.07, 0.10):
	set(value):
		name_bar_color = value
		_apply_layout()

@export_group("Art")
## Part of the full card image to show, as FRACTIONS of width/height: x, y, width, height. Default is between the name bar
## and the rules text. Tweak if the scans differ — and turn on Debug Show Crop to see it.
@export var art_region := Rect2(0.03, 0.11, 0.94, 0.48):
	set(value):
		art_region = value
		if _art:
			_apply_art_crop()

## Gap between the tile edge and the art, so the border and corners have room.
@export var art_inset: float = 3.0:
	set(value):
		art_inset = value
		_apply_layout()

## Draws art_region over the whole card, on top of the tile, so the crop can be judged directly.
@export var debug_show_crop: bool = false:
	set(value):
		debug_show_crop = value
		if _crop_debug:
			_crop_debug.visible = value

@export_group("Element border")
## The border is coloured from the card's element, so a tile's element reads at a glance.
@export var show_element_border: bool = true:
	set(value):
		show_element_border = value
		_apply_layout()

@export var border_width: int = 3:
	set(value):
		border_width = value
		_apply_layout()

@export var border_radius: int = 5:
	set(value):
		border_radius = value
		_apply_layout()

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

@export_group("Optional frame texture")
## Drawn UNDER the element border, tinted per element. Tiles look complete without it — this is only for a decorative
## frame image if one is added later.
@export var frame_texture: Texture2D:
	set(value):
		frame_texture = value
		if _frame:
			_frame.texture = value

@export_group("Power badge")
@export var badge_size := Vector2(68, 20)
@export var badge_font_size: int = 12:
	set(value):
		badge_font_size = value
		if _power_label:
			_power_label.add_theme_font_size_override("font_size", value)
			_damage_label.add_theme_font_size_override("font_size", value)

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
var _border: Panel
var _name_bar: Panel
var _name_label: Label
var _element_dot: Panel
var _power_panel: Panel
var _power_label: Label
var _damage_label: Label
var _crop_debug: Control

## The full card image as handed to setup(), kept so the crop can be redrawn when art_region changes.
var _card_texture: Texture2D = null
## The element colour last applied, so the border can be recoloured when width/radius change.
var _element_color: Color = Color.WHITE


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

	_element_color = element_colors.get(element.to_lower(), Color.WHITE)
	_frame.self_modulate = _element_color
	(_element_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = _element_color
	(_power_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = _element_color

	# Backups have no power, so only Forwards get the badge.
	_power_panel.visible = is_forward and power_text != ""
	_power_label.text = power_text
	set_damage(damage)

	custom_minimum_size = forward_size if is_forward else backup_size
	size = custom_minimum_size
	pivot_offset = size / 2.0
	_apply_layout()
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


## EVERYTHING POSITIONAL LIVES HERE, so the bar, the art cell and the border cannot disagree. The art starts BELOW the
## name bar — that separation is the whole point, and it is the one thing that must not drift back to an overlay.
func _apply_layout() -> void:
	if _name_bar == null or _art == null:
		return

	# The name bar owns the top strip, edge to edge.
	_name_bar.offset_left = 0.0
	_name_bar.offset_right = 0.0
	_name_bar.offset_top = 0.0
	_name_bar.offset_bottom = name_bar_height
	var nb := _name_bar.get_theme_stylebox("panel")
	if nb is StyleBoxFlat:
		(nb as StyleBoxFlat).bg_color = Color(name_bar_color.r, name_bar_color.g, name_bar_color.b, name_bar_opacity)

	# The art cell is what is left: under the bar, inset on the other three sides.
	var top: float = name_bar_height + art_inset
	for node in [_art, _frozen]:
		node.offset_left = art_inset
		node.offset_top = top
		node.offset_right = -art_inset
		node.offset_bottom = -art_inset

	# The element border draws over the art's edge, so it needs no texture to be visible.
	_border.visible = show_element_border
	var bs := _border.get_theme_stylebox("panel")
	if bs is StyleBoxFlat:
		var sb: StyleBoxFlat = bs
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = _element_color
		sb.set_border_width_all(border_width)
		sb.set_corner_radius_all(border_radius)

	_power_panel.offset_left = -(badge_size.x + art_inset + 3.0)
	_power_panel.offset_right = -(art_inset + 3.0)
	_power_panel.offset_top = -(badge_size.y + art_inset + 3.0)
	_power_panel.offset_bottom = -(art_inset + 3.0)


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
	# Highlight glow (e.g. "can be played / selected"), hidden by default. Added FIRST, so its shadow draws behind the
	# art rather than washing over it.
	_glow = Panel.new()
	_fill(_glow)
	var gs := _box(Color(0, 0, 0, 0), border_radius, Color("3dffb0"), 3)
	gs.shadow_color = Color(0.24, 1.0, 0.69, 0.6)
	gs.shadow_size = 8
	_glow.add_theme_stylebox_override("panel", gs)
	_glow.visible = false
	add_child(_glow)

	# Art cell. Its rect is set in _apply_layout, under the name bar.
	_art = TextureRect.new()
	_fill(_art, art_inset)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_art)

	_frozen = ColorRect.new()
	_fill(_frozen, art_inset)
	_frozen.color = Color(0.5, 0.85, 1.0, 0.28)
	_frozen.visible = false
	add_child(_frozen)

	# Optional decorative frame, over the art.
	_frame = TextureRect.new()
	_fill(_frame)
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.texture = frame_texture
	add_child(_frame)

	# THE ELEMENT BORDER. A transparent panel that only paints its border, so it needs no texture and always shows.
	_border = Panel.new()
	_fill(_border)
	_border.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), border_radius, Color.WHITE, border_width))
	add_child(_border)

	# The name bar: its own strip across the top, ABOVE the art rather than over it.
	_name_bar = Panel.new()
	_name_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_bar.add_theme_stylebox_override("panel", _box(name_bar_color, 0))
	add_child(_name_bar)

	_name_label = _label(name_font_size)
	_fill(_name_label)
	_name_label.offset_left = art_inset + 4.0
	_name_label.offset_top = 2.0
	_name_label.offset_right = -22
	_name_label.offset_bottom = -2.0
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_bar.add_child(_name_label)

	# Small element dot at the right end of the bar.
	_element_dot = Panel.new()
	_element_dot.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_element_dot.offset_left = -17
	_element_dot.offset_right = -5
	_element_dot.offset_top = -6
	_element_dot.offset_bottom = 6
	_element_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_dot.add_theme_stylebox_override("panel", _box(Color.WHITE, 6))
	_name_bar.add_child(_element_dot)

	# Power / damage badge, bottom-right of the art cell: "7000 | 0".
	_power_panel = Panel.new()
	_power_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
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

	# Last, so it draws over everything including the border.
	_crop_debug = Control.new()
	_fill(_crop_debug)
	_crop_debug.visible = false
	add_child(_crop_debug)
