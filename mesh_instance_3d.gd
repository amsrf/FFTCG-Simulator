extends MeshInstance3D
## The card's visible mesh, and where the HAND'S HOVER LIFT lives.
##
## It sits here rather than on the Card because it is presentation, not layout: the Card's own transform is the layout
## (the fan), and this offsets the mesh on top of it. The neighbours, though, are moved by the Hand — that is layout, so
## Hand.calculate_card_position() is what spreads them.
##
## ALL FOUR properties are tweened. They used to be assigned outright, which made the card jump rather than rise; and
## `position.y += 0.1` ACCUMULATED, so re-entering the area without a mouse_exited walked the card up the screen.

## How far the hovered card lifts, how much it grows, and how far it comes towards the viewer. All three are kept
## SMALL on purpose: with a camera this steeply angled, coming forward reads as rising too, so they stack up. The
## forward travel is the strongest of the three and the first one to reach for.
##
## `hover_reach` is a fixed distance toward the camera, not a delta: the lifted mesh cancels the card's own fan offset
## and then comes this far forward, so a smaller number really is less movement rather than a shifted plane.
@export var hover_lift: float = 0.05
@export var hover_scale: float = 1.25
@export var hover_reach: float = 0.32
## Seconds for the rise and the fall. Short enough to feel immediate, long enough to read as movement.
@export var hover_seconds: float = 0.16

var hand_center = GlobalVariables.get_hand_center();
var _tween: Tween = null

func _on_card_area_3d_mouse_entered():
	if not get_parent().get_parent() is Hand:
		return
	if get_parent().is_dragging:
		return
	var card: Card = get_parent()
	# Built from the card's CURRENT frame every time rather than adjusted in place, so the pose cannot drift.
	# `rotation` cancels the card's fan tilt, so a lifted card faces the player square-on.
	_tween_to(Vector3(position.x, hover_lift, -card.position.z - hover_reach),
		Vector3.ONE * hover_scale, -card.rotation)
	# Tell the hand, so the neighbours slide out of the way.
	var owner_hand: Node = card.get_parent()
	if owner_hand is Hand:
		(owner_hand as Hand).set_hovered(card, true)

func _on_card_area_3d_mouse_exited() -> void:
	dismiss()

func _on_card_area_3d_card_grabbed(_card: Variant) -> void:
	# Snapping down on grab is deliberate: the drag takes over the card's position immediately, and a tween running
	# against it would fight the pointer.
	reset()

## Drops the mesh back and tells the hand the hover has ended.
func dismiss() -> void:
	var card: Card = get_parent() as Card
	if card != null:
		var owner_hand: Node = card.get_parent()
		if owner_hand is Hand:
			(owner_hand as Hand).set_hovered(card, false)
	_tween_to(Vector3.ZERO, Vector3.ONE, Vector3.ZERO)

## Position, scale and rotation together. Any tween still running is killed first, so a fast pointer cannot leave the
## card stranded part-way between the two poses.
func _tween_to(to_position: Vector3, to_scale: Vector3, to_rotation: Vector3) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		position = to_position
		scale = to_scale
		rotation = to_rotation
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", to_position, hover_seconds)
	_tween.tween_property(self, "scale", to_scale, hover_seconds)
	_tween.tween_property(self, "rotation", to_rotation, hover_seconds)

## Immediate, unanimated drop. Used by the grab path, where the drag owns the position from the next frame.
func reset():
	if _tween != null and _tween.is_valid():
		_tween.kill()
	scale = Vector3.ONE
	position = Vector3.ZERO
	rotation = Vector3.ZERO
