extends CanvasLayer
## THE ABILITY BADGE - the extra step before a single activated ability starts. Clicking a field card that has exactly ONE
## ability it can activate now shows this badge beside it: the ability's COST (chips: element, number, Dull, S) and its
## TEXT, nothing else. The badge IS the button: clicking it confirms (`confirmed`), and the normal activation flow begins
## (Field.begin_skill_activation). While it is up a transparent CATCHER covers the screen under it, so nothing hovers
## and nothing else can be clicked: a click anywhere but the badge or its card ONLY dismisses it (`dismissed`), and so
## do a right click, Escape, or the card stopping being activatable. A click on the card itself does nothing. A card with 2+ abilities never gets a badge; it opens skill_choice instead.
##
## Placement (the user's "option C"): a dark plate on the empty wood BESIDE the card, on the outer side of the board
## nearest to it (left half of the screen -> plate to the card's left), vertically centred on it, joined to the card's
## edge by a thin gold leader. It follows the card every frame, so a card that moves (the charging lift, a reflow) keeps
## its badge. Built in code like skill_choice.gd; preloaded by path, no class_name.

signal confirmed
signal dismissed

const ELEMENTS := preload("res://scripts/core/elements.gd")
const FONT := preload("res://assets/fonts/FOT-NewRodin Pro EB.otf")

const PLATE_WIDTH := 380.0
const GAP := 34.0                     # screen px between the card's edge and the plate
const SCREEN_MARGIN := 16.0
const TEXT_SIZE := 21
const CHIP := 30.0                    # chip height (px)
const PLATE_BG := Color(0.055, 0.05, 0.065, 0.90)
const BORDER := Color(1.0, 0.94, 0.82, 0.30)
const BORDER_HOVER := Color(0.91, 0.75, 0.43, 1.0)
const GOLD := Color(0.91, 0.75, 0.43)
const CREAM := Color(1.0, 0.965, 0.89)
const NEUTRAL_CHIP := Color(0.62, 0.61, 0.66)

var card: Card = null
var _button: Button = null
var _leader: Line2D = null
var _dot: Panel = null
var _hover := false
var _done := false


func _ready() -> void:
	layer = 11


## Show the badge for `source`'s ability `def` (an activation_skill() dictionary: its `text`, `cost`, `tap`, `s_cost`).
func open(source: Card, def: Dictionary) -> void:
	card = source
	# THE CATCHER, under everything else on this layer: it takes every pointer event, so no card hovers and nothing
	# behind it can be clicked while the badge is up.
	var catcher := Control.new()
	catcher.name = "BadgeCatcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_catcher_input)
	add_child(catcher)
	_leader = Line2D.new()
	_leader.width = 3.0
	_leader.default_color = Color(GOLD, 0.85)
	_leader.antialiased = true
	add_child(_leader)
	_dot = Panel.new()
	_dot.size = Vector2(10, 10)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.add_theme_stylebox_override("panel", _round(GOLD, 5.0))
	add_child(_dot)

	_button = Button.new()
	_button.name = "AbilityBadge"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(PLATE_WIDTH, 0.0)
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "focus", "disabled"]:
		_button.add_theme_stylebox_override(state, _plate(false))
	for state in ["hover", "pressed"]:
		_button.add_theme_stylebox_override(state, _plate(true))
	_button.pressed.connect(confirm)
	_button.mouse_entered.connect(func() -> void: _set_hover(true))
	_button.mouse_exited.connect(func() -> void: _set_hover(false))
	add_child(_button)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 20
	column.offset_right = -20
	column.offset_top = 16
	column.offset_bottom = -16
	_button.add_child(column)

	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	for chip in cost_chips(def):
		chips.add_child(_make_chip(chip))
	column.add_child(chips)

	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var label := Label.new()
	label.name = "AbilityText"
	label.text = effect_text(def)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(PLATE_WIDTH - 40.0, 0.0)
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_color_override("font_color", CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)

	# Height from the content (the plate is a Button, which does not size itself to a child container).
	var text_height: float = FONT.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, PLATE_WIDTH - 40.0,
		TEXT_SIZE).y
	_button.size = Vector2(PLATE_WIDTH, 16.0 + CHIP + 10.0 + 2.0 + 10.0 + text_height + 16.0)
	_place()


func confirm() -> void:
	if _done:
		return
	_done = true
	confirmed.emit()
	queue_free()


func dismiss() -> void:
	if _done:
		return
	_done = true
	dismissed.emit()
	queue_free()


func _process(_delta: float) -> void:
	if not is_instance_valid(card) or not card.is_drawn_on_field():
		dismiss()
		return
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()

## A click that missed the badge: on its card it does nothing; anywhere else it only dismisses the badge.
func _on_catcher_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	get_viewport().set_input_as_handled()
	if event.button_index == MOUSE_BUTTON_LEFT and is_over_card(event.position):
		return
	dismiss()

## Is the screen point `at` on the badge's card?
func is_over_card(at: Vector2) -> bool:
	var camera := card.get_viewport().get_camera_3d() if is_instance_valid(card) else null
	return camera != null and _screen_rect(card, camera).has_point(at)

## The card's face on screen, then the plate on the empty wood PAST THE END OF ITS ROW, on the board's outer side
## nearest to it (beside the card itself would cover its neighbours), clamped to the screen; the leader runs from the
## card's edge to the plate.
func _place() -> void:
	var camera := card.get_viewport().get_camera_3d()
	if camera == null or _button == null:
		return
	var own := _screen_rect(card, camera)
	var view := get_viewport().get_visible_rect().size
	var centre := own.get_center()
	var left: bool = centre.x < view.x * 0.5
	var row_edge: float = own.position.x if left else own.end.x
	for other in _row_of(card):
		if other == card or not is_instance_valid(other) or not other.is_drawn_on_field():
			continue
		var r := _screen_rect(other, camera)
		row_edge = minf(row_edge, r.position.x) if left else maxf(row_edge, r.end.x)
	var x: float = row_edge - GAP - _button.size.x if left else row_edge + GAP
	x = clampf(x, SCREEN_MARGIN, view.x - SCREEN_MARGIN - _button.size.x)
	var y: float = clampf(centre.y - _button.size.y * 0.5, SCREEN_MARGIN, view.y - SCREEN_MARGIN - _button.size.y)
	_button.position = Vector2(x, y)
	var from := Vector2(own.position.x if left else own.end.x, centre.y)
	var to := Vector2(x + _button.size.x if left else x, clampf(centre.y, y + 14.0, y + _button.size.y - 14.0))
	_leader.points = PackedVector2Array([from, to])
	_dot.position = from - _dot.size * 0.5

## A field card's face as a screen rectangle.
static func _screen_rect(c: Card, camera: Camera3D) -> Rect2:
	var face: Vector2 = c._card_face_size()
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner := camera.unproject_position(c.hand_mesh.to_global(Vector3(k.x * face.x, 0.0, k.y * face.y) * 0.5))
		lo = lo.min(corner)
		hi = hi.max(corner)
	return Rect2(lo, hi - lo)

## The field row `c` stands in (its controller's Forwards or Backups).
static func _row_of(c: Card) -> Array:
	var field = c.get_parent()
	if field == null or not field.has_method("get_front_cards_for"):
		return []
	var front: Array = field.get_front_cards_for(c.controller)
	return front if front.has(c) else field.get_back_cards_for(c.controller)


func _set_hover(on: bool) -> void:
	_hover = on
	if _leader != null:
		_leader.default_color = Color(GOLD, 1.0 if on else 0.85)


func _plate(hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PLATE_BG if not hover else Color(0.09, 0.075, 0.06, 0.94)
	s.border_color = BORDER_HOVER if hover else BORDER
	s.set_border_width_all(3 if hover else 2)
	s.set_corner_radius_all(16)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	return s


func _round(colour: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(int(radius))
	return s


# --------------------------------------------------------------------------------------------- content

## The cost as chips, in printed order: one per elemental CP (that element's colour), the generic CP as one number chip,
## then S and Dull. Each chip is {"text", "colour", "dark_text"}.
static func cost_chips(def: Dictionary) -> Array:
	var chips: Array = []
	var cost: Dictionary = def.get("cost", {})
	var neutral := 0
	for key in cost:
		var amount: int = int(cost[key])
		if str(key) == "neutral":
			neutral += amount
			continue
		var i: int = ELEMENTS.index_of(key)
		for _n in range(amount):
			chips.append({"text": "", "colour": ELEMENTS.ACCENT[i] if i >= 0 else NEUTRAL_CHIP, "element": true})
	if neutral > 0:
		chips.append({"text": str(neutral), "colour": NEUTRAL_CHIP, "element": false})
	if bool(def.get("s_cost", false)):
		chips.append({"text": "S", "colour": Color(0.95, 0.35, 0.70), "element": false})
	if bool(def.get("tap", false)):
		chips.append({"text": "Dull", "colour": Color(0.80, 0.80, 0.84), "element": false})
	if chips.is_empty():
		chips.append({"text": "Free", "colour": Color(0.55, 0.80, 0.60), "element": false})
	return chips

## The ability's effect, without the printed cost in front of it ("《火》《1》《Dull》: Choose 1 Forward." -> "Choose 1
## Forward."). Falls back to skill_choice's readable summary when the data has no text.
static func effect_text(def: Dictionary) -> String:
	var text: String = str(def.get("text", "")).strip_edges()
	if text.is_empty():
		text = preload("res://scripts/ui/skill_choice.gd")._skill_text(def)
	var cut: int = text.find("》:")
	if cut >= 0:
		return text.substr(cut + 2).strip_edges()
	if text.begins_with("《"):
		var colon: int = text.find(":")
		if colon >= 0:
			return text.substr(colon + 1).strip_edges()
	return text


func _make_chip(chip: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colour: Color = chip["colour"]
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.border_color = colour.lightened(0.45)
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(CHIP * 0.5))
	s.content_margin_left = 10 if str(chip["text"]).length() > 1 else 0
	s.content_margin_right = s.content_margin_left
	panel.add_theme_stylebox_override("panel", s)
	panel.custom_minimum_size = Vector2(CHIP, CHIP)
	var label := Label.new()
	label.text = str(chip["text"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.10))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


# --- probe accessors ---------------------------------------------------------------------------------------

func plate_rect() -> Rect2:
	return Rect2(_button.position, _button.size) if _button != null else Rect2()

func shown_text() -> String:
	var label := _button.find_child("AbilityText", true, false) as Label if _button != null else null
	return label.text if label != null else ""
