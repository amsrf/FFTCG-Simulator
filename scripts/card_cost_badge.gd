extends RefCounted
## THE COST, ENLARGED. The card's own printed cost crystal, cut out of its artwork and drawn bigger over the original
## (like Master Duel's level stars), so a card's cost reads at a glance on the field and in the hand.
##
## The crystal is in exactly the same place on every card image (429 x 600), measured from the average of 400 cards:
## a stretched hexagon with its tips at (41.5, 6) and (41.5, 93) and its sides at x 19.5 and 63.5, from y 22 to 77.
## The badge samples that region of the card's texture and masks it to that hexagon, so nothing around the crystal
## comes with it.
##
## Shown on face-up cards on the field and in the hand; hidden on the stack (its face is a different texture), face
## down, and while the card is dissolving in or out (Card.teleport.chrome_hidden).

const SHADER := preload("res://shaders/cost_badge.gdshader")
const IMAGE_SIZE := Vector2(429.0, 600.0)
## The sampled rectangle, in image pixels: the hexagon plus a pixel of its dark rim on each side.
const CROP := Rect2(18.0, 4.0, 47.0, 91.0)
## How much bigger than the printed crystal it is drawn, around the same centre.
const ENLARGE := 1.6
## Just above the face, so it never fights the face for depth.
const LIFT := 0.0015

static func install(card: Node3D, texture: Texture2D, face: Vector2) -> MeshInstance3D:
	var badge: MeshInstance3D = card.get_node_or_null("CostBadge") as MeshInstance3D
	if badge == null:
		badge = MeshInstance3D.new()
		badge.name = "CostBadge"
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.add_child(badge)
	var px: Vector2 = face / IMAGE_SIZE   # local units per image pixel
	var plane := PlaneMesh.new()          # in the card's XZ plane, facing +Y like the face; UV v=0 is the top (-Z)
	plane.size = CROP.size * px * ENLARGE
	badge.mesh = plane
	var centre: Vector2 = (CROP.position + CROP.size * 0.5) * px - face * 0.5
	var top: float = 0.0
	var face_mesh: MeshInstance3D = card.get_node_or_null("HandMesh") as MeshInstance3D
	if face_mesh != null and face_mesh.mesh != null:
		top = face_mesh.mesh.get_aabb().end.y
	badge.position = Vector3(centre.x, top + LIFT, centre.y)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("card_texture", texture)
	material.set_shader_parameter("uv_rect", Vector4(CROP.position.x / IMAGE_SIZE.x, CROP.position.y / IMAGE_SIZE.y,
		CROP.size.x / IMAGE_SIZE.x, CROP.size.y / IMAGE_SIZE.y))
	material.set_shader_parameter("crop_px", CROP.size)
	# DRAWN AFTER THE CARD'S RING. Both are see-through layers; without this the ring's glow (drawn later) washed
	# over the part of the crystal that overhangs the card's corner.
	material.render_priority = 1
	badge.material_override = material
	badge.visible = false
	return badge
