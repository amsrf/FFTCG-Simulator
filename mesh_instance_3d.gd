extends MeshInstance3D
## The card's visible mesh, and where the HAND'S HOVER begins.
##
## THE HOVER IS A GROWTH IN PLACE NOW. It used to lift the mesh off the fan, come toward the camera and cancel the
## card's tilt, while the Hand slid the neighbours aside. All of that is gone: the card simply GROWS, to the size it
## will be when it reaches the stack, and nothing else moves. That is the deck search window's behaviour, and the
## point of it is that a card played straight from the hand is already the right size when it lands — it used to
## shrink to the hand's size on the way and then pop back up on the stack.
##
## The size itself is NOT set here. It belongs to the Hand (`Hand.set_hovered`), because it is the CARD's scale that
## has to change — that is what the drag and the zone system both already use, and it is what survives the drag.

func _on_card_area_3d_mouse_entered():
	var card: Card = get_parent() as Card
	if card == null:
		return
	var owner_hand: Node = card.get_parent()
	if not owner_hand is Hand:
		return
	# A card already in the air keeps whatever it has: re-growing it under the pointer would be a second animation.
	if card.is_dragging:
		return
	(owner_hand as Hand).set_hovered(card, true)

func _on_card_area_3d_mouse_exited() -> void:
	var card: Card = get_parent() as Card
	if card == null:
		return
	var owner_hand: Node = card.get_parent()
	if owner_hand is Hand:
		(owner_hand as Hand).set_hovered(card, false)

func _on_card_area_3d_card_grabbed(_card: Variant) -> void:
	# Deliberately does nothing to the size. The card keeps the size it grew to — it is on its way to the stack, which
	# draws cards at exactly that size — and the drag itself owns its position from the next frame.
	pass

## Immediate, unanimated reset of the MESH's own offset. The card's scale belongs to the Hand and the zone system,
## so it is not touched here.
func reset():
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE
