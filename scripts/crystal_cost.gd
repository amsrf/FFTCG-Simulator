extends Node3D
class_name CrystalCost
## The crystal cost readout: "Pay", then ONE BADGE PER ELEMENTAL POINT, then a single numeral badge for
## the neutral part.
##
## Elemental points get one badge each — that is how a player counts off what is still owed — while
## neutral, having no glyph of its own, gets one badge carrying the number. A 2-cost fire card
## ({'火': 1, 'neutral': 1}) therefore reads: Pay  [火]  [1].
##
## The cost Dictionary is exactly the one the mana model and Card.get_cost() already produce, including
## their habit of keying elements by a one-element Array (["火"]) instead of a String, so both shapes
## are accepted and neither needs a translation step. Neutral is always the String "neutral".
##
## The row faces the camera for the same reason a badge does: it will float above a player's head, and
## the board camera is only ~11 degrees off vertical, so a fixed row would be nearly edge-on.

const BADGE := preload("res://element_badge.tscn")
const LABEL_FONT := preload("res://Font/FOT-NewRodin Pro EB.otf")
const LABEL_FONT_SIZE := 64

@export var badge_size_m: float = 0.22:
	set(value):
		badge_size_m = value
		_rebuild()

@export var label_text: String = "Pay":
	set(value):
		label_text = value
		_rebuild()

## How tall the "Pay" word is, in metres. It has to be set alongside the badge size: at the 0.14 m the icons
## are drawn at, a 0.17 m word towered over the icons it introduces — which is exactly what happened, because
## this default is only overridden when something assigns it.
@export var label_height_m: float = 0.10:
	set(value):
		label_height_m = value
		_rebuild()

## Gap between items, in metres.
@export var gap_m: float = 0.035

## {'火': 1, 'neutral': 1} — the same shape Card.get_cost() returns.
@export var cost: Dictionary = {}:
	set(value):
		cost = value
		_rebuild()

var _label: Label3D = null

func _ready() -> void:
	_rebuild()
	_align_to_camera()

func _process(_delta: float) -> void:
	_align_to_camera()

func _align_to_camera() -> void:
	if not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		global_transform = Transform3D(cam.global_transform.basis, global_position)

## The badges this row is currently showing, in order. Elemental badges first, the neutral one last.
func badges() -> Array[ElementBadge]:
	var out: Array[ElementBadge] = []
	for c in get_children():
		if c is ElementBadge:
			out.append(c)
	return out

## Lays the row out along local +x — which, once the row faces the camera, is screen-right — and
## centres the whole thing on this node's origin.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	# remove_child() FIRST, then queue_free(). queue_free() alone is deferred to the end of the frame, so
	# the old badges would still answer get_children() — and disappear only after the new ones were added
	# — which is precisely how a rebuilt row ended up with both sets in it. Removing from the tree is
	# immediate; freeing can wait.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_label = null

	var entries: Array = []
	for key in cost.keys():
		var name_key: String = ElementBadge.key_to_element(key)
		if name_key == "neutral":
			continue
		for i in int(cost[key]):
			entries.append({"element": name_key, "number": -1})
	# Neutral: ONE badge with the number, not one per point — it has no glyph to repeat.
	var neutral: int = int(cost.get("neutral", 0))
	if neutral > 0:
		entries.append({"element": "", "number": neutral})

	# Measure first, then place, so the row can be centred as a whole.
	var widths: Array[float] = []
	var label_width: float = 0.0
	if not label_text.is_empty():
		var px: float = label_height_m / float(LABEL_FONT_SIZE)
		label_width = LABEL_FONT.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x * px
		widths.append(label_width)
	for e in entries:
		widths.append(badge_size_m)
	var total: float = 0.0
	for w in widths:
		total += w
	total += gap_m * maxf(0.0, float(widths.size() - 1))

	var x: float = -total * 0.5
	if not label_text.is_empty():
		_make_label()
		_label.position = Vector3(x + label_width * 0.5, 0.0, 0.0)
		x += label_width + gap_m
	for e in entries:
		var badge: ElementBadge = BADGE.instantiate()
		add_child(badge)
		badge.size_m = badge_size_m
		if int(e["number"]) >= 0:
			badge.number = int(e["number"])
		else:
			badge.element = str(e["element"])
		badge.position = Vector3(x + badge_size_m * 0.5, 0.0, 0.0)
		x += badge_size_m + gap_m

func _make_label() -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.name = "PayLabel"
	_label.font = LABEL_FONT
	_label.font_size = LABEL_FONT_SIZE
	_label.text = label_text
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # the row faces the camera, not the label
	_label.double_sided = true
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.pixel_size = label_height_m / float(LABEL_FONT_SIZE)
	add_child(_label)
