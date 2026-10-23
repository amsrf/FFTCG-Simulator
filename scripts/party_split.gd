extends CanvasLayer
## THE BLOCKER'S DAMAGE DISTRIBUTION WINDOW.
##
## When a Forward blocks a Party, its power is divided across the party's members in 1000-point increments, and the
## blocker's controller chooses how. This is that choice.
##
## Rules this enforces:
##   * every point must be assigned — Confirm stays disabled until the total EQUALS the blocker's power
##   * the running total can never exceed the pool, so there is no state the player has to undo
##   * a final partial step is allowed, so a 2500-power blocker can still be distributed exactly
##
## It returns the split through `finished` and frees itself; the caller (LocalAgent) is the only one who awaits it.

signal finished(split: Array)

const STEP := 1000
const CARD_SIZE := Vector2(150, 210)
const CARD_GAP := 52
const CARD_VIEW := preload("res://scripts/card_view.gd")

var _party: Array = []
var _total: int = 0
var _amounts: Array = []

var _root: Control = null
var _rows: Array = []          # per card: { "value": Label }
var _total_label: Label = null
var _confirm: Button = null


func open(party: Array, total: int) -> void:
	_party = party.duplicate()
	_total = maxi(total, 0)
	_amounts = []
	_amounts.resize(_party.size())
	_amounts.fill(0)
	_build()
	_refresh()


# --- public, so the probe can drive exactly what the buttons drive -------------------------------------------------
func bump(index: int, steps: int) -> void:
	if index < 0 or index >= _amounts.size():
		return
	var others: int = 0
	for i in range(_amounts.size()):
		if i != index:
			others += int(_amounts[i])
	var next: int = int(_amounts[index]) + steps * STEP
	# CLAMP TO THE POOL rather than refusing the click: the clamp is also what allows a partial final step when the
	# blocker's power is not a multiple of 1000.
	next = clampi(next, 0, maxi(0, _total - others))
	_amounts[index] = next
	_refresh()


func assigned() -> int:
	var sum: int = 0
	for a in _amounts:
		sum += int(a)
	return sum


func split() -> Array:
	return _amounts.duplicate()


func can_confirm() -> bool:
	return assigned() == _total


func confirm() -> void:
	if not can_confirm():
		return
	finished.emit(split())
	queue_free()


# --- building -------------------------------------------------------------------------------------------------------
func _build() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	# NOTE: ColorRect's set_anchors_preset does not resize it (it has no layout parent size), so set the anchors AND
	# let the full-rect offsets do the work.
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Distribute %d damage" % _total
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CARD_GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	for i in range(_party.size()):
		row.add_child(_make_card(i))

	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_total_label)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(220, 46)
	_confirm.pressed.connect(confirm)
	var confirm_row := HBoxContainer.new()
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_row.add_child(_confirm)
	column.add_child(confirm_row)


func _make_card(index: int) -> Control:
	var card: Card = _party[index]
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 8)

	var art := TextureRect.new()
	art.custom_minimum_size = CARD_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = CARD_VIEW.art_path(card.id)
	if path != "":
		art.texture = load(path) as Texture2D
	if art.texture != null:
		art.material = CARD_VIEW.round_material()
	cell.add_child(art)

	var name_label := Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(name_label)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	cell.add_child(controls)

	var down := Button.new()
	down.text = "▼"
	down.custom_minimum_size = Vector2(56, 44)
	down.pressed.connect(bump.bind(index, -1))
	controls.add_child(down)

	var value := Label.new()
	value.text = "0"
	value.custom_minimum_size = Vector2(74, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 24)
	controls.add_child(value)

	var up := Button.new()
	up.text = "▲"
	up.custom_minimum_size = Vector2(56, 44)
	up.pressed.connect(bump.bind(index, 1))
	controls.add_child(up)

	_rows.append({"value": value})
	return cell


func _refresh() -> void:
	for i in range(_rows.size()):
		(_rows[i]["value"] as Label).text = str(int(_amounts[i]))
	if _total_label != null:
		_total_label.text = "Assigned %d / %d" % [assigned(), _total]
	if _confirm != null:
		_confirm.disabled = not can_confirm()
