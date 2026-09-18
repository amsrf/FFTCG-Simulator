extends Node3D
class_name CrystalCost
## The mana payment row: ONE CRYSTAL PER POINT of the cost.
##
## A cost of {'火': 1, 'neutral': 3} draws one RED crystal and three WHITE ones. Each crystal then LIGHTS as it
## is paid, in the colour of whatever paid it — so a white crystal paid by a fire source turns red and shines,
## while an elemental crystal can only be paid by its own element, which means it never changes colour and only
## its shine comes on.
##
## The row shows the WHOLE cost and stays put while you pay; the lit crystals are the progress. It replaced a
## badge row that showed only what was still owed, so that row shrank as crystals were chosen and a player could
## never see what the cost had been.
##
## `cost` is the Dictionary Card.get_cost() produces, including its habit of keying elements by a one-element
## Array (["火"]) rather than a String, so both spellings are accepted. `paid` is Assistant.payment_breakdown():
## one entry per point in row order, each naming the element that paid that point or "" while it is still owed.
##
## The row faces the camera for the same reason the badges did: it floats above a player's head, and the board
## camera is only ~11 degrees off vertical, so a fixed row would be almost edge-on.

const CRYSTAL := preload("res://mana_crystal.tscn")
const LABEL_FONT := preload("res://Font/FOT-NewRodin Pro EB.otf")
const LABEL_FONT_SIZE := 64
const WILD := "neutral"

## The crystal's height in metres — and therefore its footprint: the mesh is twice as tall as it is wide and it
## spins, so its widest diagonal is exactly half its height.
@export var crystal_height_m: float = 0.15:
	set(value):
		crystal_height_m = value
		_rebuild()

## Kept because Assistant assigns it: the crystal height, under its old name. One number, so the row and the
## caller cannot drift apart over a rename.
@export var badge_size_m: float = 0.15:
	set(value):
		badge_size_m = value
		crystal_height_m = value

## Gap between crystals. The slot is the crystal's own widest diagonal (half its height) PLUS its outline, which
## grows it about another pixel per side — so 0.010 m left them touching, and two payments read as one blob. The
## check asked for 4-6 px of air; 0.030 is about 5.6 px at this camera's 187 px per metre.
@export var gap_m: float = 0.030

## An optional word before the row, like "Pay". Empty by default — the crystals say it on their own.
@export var label_text: String = "":
	set(value):
		label_text = value
		_rebuild()

@export var label_height_m: float = 0.10:
	set(value):
		label_height_m = value
		_rebuild()

## The FULL cost: {'火': 1, 'neutral': 3}.
@export var cost: Dictionary = {}:
	set(value):
		cost = value
		_rebuild()

## One entry per point, in row order, from Assistant.payment_breakdown().
@export var paid: Array = []:
	set(value):
		paid = value
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

## The crystals on show, in row order.
func crystals() -> Array:
	var out: Array = []
	for c in get_children():
		if c.has_method("colour_now"):
			out.append(c)
	return out

## Lays the row out along local +x — which, once the row faces the camera, is screen-right — and centres the
## whole thing on this node's origin.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	# remove_child() FIRST, then queue_free(). queue_free() alone is deferred to the end of the frame, so the old
	# crystals would still answer get_children() — and disappear only after the new ones were added — which is
	# exactly how a rebuilt row ended up holding two sets of children.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_label = null

	# One slot per point: the elemental points first, in the cost's own key order so the row is stable between
	# rebuilds, then the wild ones, which have no element of their own and are drawn white.
	var slots: Array = []
	for key in cost.keys():
		var element: String = ElementBadge.key_to_element(key)
		if element == WILD or element.is_empty():
			continue
		for _i in range(int(cost[key])):
			slots.append(element)
	for _i in range(int(cost.get(WILD, 0))):
		slots.append("")

	# The slot width comes from the crystal's OWN bounds, not from half its height.
	#
	# It was 0.5 * height, which was true of the first model (a bipyramid 2 units wide and 4 tall). The model was
	# then swapped for a hexagonal one that is proportionally WIDER — 0.60 of its height — so every crystal was
	# narrower than its slot over and the row overlapped itself, fusing the pair into one silhouette with the
	# outline tracing the union as a single heart-shaped rim. Asking the crystal means a future swap cannot do
	# that again. It is asked once, because every crystal in the row is the same size.
	var probe: Node3D = CRYSTAL.instantiate()
	probe.visible = false
	add_child(probe)
	probe.height_m = crystal_height_m
	var width: float = float(probe.call("slot_width_m"))
	remove_child(probe)
	probe.queue_free()
	var label_width: float = 0.0
	if not label_text.is_empty():
		var px: float = label_height_m / float(LABEL_FONT_SIZE)
		label_width = LABEL_FONT.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x * px
	if slots.is_empty() and label_text.is_empty():
		return
	var items: int = slots.size() + (0 if label_text.is_empty() else 1)
	var total: float = label_width + width * slots.size() + gap_m * maxf(0.0, float(items - 1))

	var x: float = -total * 0.5
	if not label_text.is_empty():
		_make_label()
		_label.position = Vector3(x + label_width * 0.5, 0.0, 0.0)
		x += label_width + gap_m
	for i in range(slots.size()):
		var crystal: Node3D = CRYSTAL.instantiate()
		add_child(crystal)
		crystal.height_m = crystal_height_m
		crystal.element = str(slots[i])
		# Fill in only what has been paid SO FAR: the breakdown is as long as the points that have been paid,
		# which is nothing at the moment the modal opens.
		if i < paid.size() and paid[i] is Dictionary:
			var payer: String = str((paid[i] as Dictionary).get("paid_by", ""))
			if not payer.is_empty():
				crystal.paid_element = payer
				crystal.lit = true
		crystal.position = Vector3(x + width * 0.5, 0.0, 0.0)
		x += width + gap_m

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
