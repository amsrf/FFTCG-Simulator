extends CanvasLayer
## SKILL CHOICE — pick WHICH ability to activate when a card has more than one.
##
## Shown when a card's `skill` array holds 2+ entries (Rikku 89: her normal mill and her S ability). Each ability is a
## selectable container showing its own text; the selected one gets an accent border, and Confirm stays disabled until
## something is picked. Cancel (or Escape) exits with CHOOSE_NONE.
##
## The texts come from the optional `"text"` key on a skill definition. Without it, a readable fallback is built from
## the cost and the instructions, so new data is never blank on screen.

signal finished(index: int)

const CHOOSE_NONE := -1
const PANEL_WIDTH := 820.0
const TEXT_COLOUR := Color(0.90, 0.93, 0.98)
const DIM_TEXT_COLOUR := Color(0.52, 0.55, 0.62)
const IDLE_BORDER := Color(0.30, 0.33, 0.40)
const HOVER_BORDER := Color(0.55, 0.60, 0.70)
const SELECTED_BORDER := Color(1.0, 0.45, 0.05)
const SELECTED_BG := Color(0.20, 0.14, 0.08)
const IDLE_BG := Color(0.09, 0.10, 0.14)

const ELEMENT_NAMES := {
	"火": "Fire", "氷": "Ice", "風": "Wind", "土": "Earth",
	"雷": "Lightning", "水": "Water", "光": "Light", "闇": "Dark",
}

var _selected: int = -1
var _buttons: Array = []
var _usable: Array = []
var _confirm: Button = null
var _title: Label = null
var _list: VBoxContainer = null


func _ready() -> void:
	layer = 12
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Dim that also swallows clicks, so nothing behind the modal can be pressed while it is open.
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
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	column.add_child(_list)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140, 44)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(cancel_choice)
	row.add_child(cancel)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(170, 44)
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


## Open for `card`. `usable` is one flag per skill: an entry whose cost cannot be paid (an S ability with no matching
## card in hand) is shown but disabled, rather than hidden — the player should see the ability exists.
func open(card: Card, skills: Array, usable: Array = []) -> void:
	_title.text = "%s — choose an ability" % card.card_name
	for i in range(skills.size()):
		var def: Dictionary = skills[i]
		var can_use: bool = true if usable.is_empty() else bool(usable[i])
		_usable.append(can_use)
		var box := _make_skill_box(_skill_text(def), i, can_use)
		_list.add_child(box)
		_buttons.append(box)
	_refresh_borders()


func _make_skill_box(text: String, index: int, can_use: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 86.0)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", TEXT_COLOUR if can_use else DIM_TEXT_COLOUR)
	b.add_theme_color_override("font_hover_color", Color.WHITE if can_use else DIM_TEXT_COLOUR)
	b.add_theme_color_override("font_pressed_color", Color.WHITE if can_use else DIM_TEXT_COLOUR)
	b.disabled = not can_use
	if can_use:
		b.pressed.connect(func() -> void: select_skill(index))
	return b


func _border_style(selected: bool, hover: bool, can_use: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SELECTED_BG if selected else IDLE_BG
	if not can_use:
		s.bg_color = Color(0.06, 0.065, 0.08)
	s.border_color = SELECTED_BORDER if selected else (HOVER_BORDER if hover else IDLE_BORDER)
	s.set_border_width_all(3 if selected else 1)
	s.set_corner_radius_all(9)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func _refresh_borders() -> void:
	for i in range(_buttons.size()):
		var b: Button = _buttons[i]
		var can_use: bool = bool(_usable[i]) if i < _usable.size() else true
		var selected: bool = i == _selected
		b.add_theme_stylebox_override("normal", _border_style(selected, false, can_use))
		b.add_theme_stylebox_override("hover", _border_style(selected, true, can_use))
		b.add_theme_stylebox_override("pressed", _border_style(selected, true, can_use))
		b.add_theme_stylebox_override("focus", _border_style(selected, false, can_use))
		b.add_theme_stylebox_override("disabled", _border_style(false, false, can_use))
	if _confirm != null:
		_confirm.disabled = _selected < 0


## Select an ability by index. Unusable entries ignore the click.
func select_skill(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	if index < _usable.size() and not bool(_usable[index]):
		return
	_selected = index
	_refresh_borders()


func confirm_choice() -> void:
	if _selected < 0:
		return
	_finish(_selected)


func cancel_choice() -> void:
	_finish(CHOOSE_NONE)


func _finish(index: int) -> void:
	visible = false
	finished.emit(index)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_choice()
		get_viewport().set_input_as_handled()


# --- probe accessors ---------------------------------------------------------------------------------------

func skill_button_count() -> int:
	return _buttons.size()


func selected_index() -> int:
	return _selected


func confirm_enabled() -> bool:
	return _confirm != null and not _confirm.disabled


func skill_border_colour(index: int) -> Color:
	if index < 0 or index >= _buttons.size():
		return Color.TRANSPARENT
	var style = _buttons[index].get_theme_stylebox("normal")
	return style.border_color if style is StyleBoxFlat else Color.TRANSPARENT


func skill_is_enabled(index: int) -> bool:
	return index >= 0 and index < _buttons.size() and not _buttons[index].disabled


func skill_text(index: int) -> String:
	return _buttons[index].text if index >= 0 and index < _buttons.size() else ""


## The display text for one skill: its `text` key if the data has one, else a readable fallback built from the cost and
## the first instruction, so an undocumented ability is never a blank container.
static func _skill_text(def: Dictionary) -> String:
	var explicit: String = str(def.get("text", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var tokens: Array = []
	var cost: Dictionary = def.get("cost", {})
	for key in cost:
		var amount: int = int(cost[key])
		if str(key) == "neutral":
			if amount > 0:
				tokens.append(str(amount))
			continue
		for _i in range(amount):
			tokens.append(str(ELEMENT_NAMES.get(str(key), key)))
	if bool(def.get("s_cost", false)):
		tokens.append("S")
	if bool(def.get("tap", false)):
		tokens.append("Dull")
	var head: String = ""
	if not tokens.is_empty():
		head = "《%s》 " % String("-").join(tokens)
	var instructions: Array = def.get("instructions", [])
	var effect: String = "ability"
	if not instructions.is_empty():
		effect = str(instructions[0].get("name", "ability")).replace("_", " ")
	return head + effect
