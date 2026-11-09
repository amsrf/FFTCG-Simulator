extends RefCounted
## THE NAME, ENLARGED. The card's own printed name box, cut out of its artwork and drawn a little bigger over the
## original, so a card's name reads on the field and in the hand. The companion of card_cost_badge.gd.
##
## The box is in the same place on every card image (429 x 600), measured from the averages of 300 Characters and 245
## Summons: a band from y 19 to 62.5. Characters have a box with pointed ends (tips at x 66.5 and 411); Summons have a
## slanted, slightly curved box. Each style has a mask image over the same crop (assets/ui/name_box_mask_*.png), so
## only the box comes with it.
##
## Shown and hidden with the cost badge (Card.refresh_cost_badge), drawn under it.

const SHADER := preload("res://shaders/name_badge.gdshader")
const MASK_CHARACTER := preload("res://assets/ui/name_box_mask_char.png")
const MASK_SUMMON := preload("res://assets/ui/name_box_mask_summon.png")
const IMAGE_SIZE := Vector2(429.0, 600.0)
## The crop both masks cover, in image pixels.
const CROP := Rect2(60.0, 16.0, 360.0, 50.0)
## The box is wide (about 80% of the card), so it is enlarged only a little.
const ENLARGE := 1.15
## It grows away from this x (image pixels), near its left end, not from its centre: grown from the centre, its left
## end slid under the enlarged cost crystal and the name's first letter was covered. From here the text (which starts
## at about x 92) stays clear of the crystal (which reaches about x 79), and the extra width goes to the right.
const GROW_FROM_X := 150.0
## Just above the face; the cost badge sits on top of it (render priority).
const LIFT := 0.0012

static func install(card: Node3D, texture: Texture2D, face: Vector2, is_summon: bool) -> MeshInstance3D:
	var badge: MeshInstance3D = card.get_node_or_null("NameBadge") as MeshInstance3D
	if badge == null:
		badge = MeshInstance3D.new()
		badge.name = "NameBadge"
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.add_child(badge)
	var px: Vector2 = face / IMAGE_SIZE
	var plane := PlaneMesh.new()
	plane.size = CROP.size * px * ENLARGE
	badge.mesh = plane
	var crop_centre: Vector2 = CROP.position + CROP.size * 0.5
	crop_centre.x = GROW_FROM_X + (crop_centre.x - GROW_FROM_X) * ENLARGE
	var centre: Vector2 = crop_centre * px - face * 0.5
	var top: float = 0.0
	var face_mesh: MeshInstance3D = card.get_node_or_null("HandMesh") as MeshInstance3D
	if face_mesh != null and face_mesh.mesh != null:
		top = face_mesh.mesh.get_aabb().end.y
	badge.position = Vector3(centre.x, top + LIFT, centre.y)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("card_texture", texture)
	material.set_shader_parameter("box_mask", MASK_SUMMON if is_summon else MASK_CHARACTER)
	material.set_shader_parameter("uv_rect", Vector4(CROP.position.x / IMAGE_SIZE.x, CROP.position.y / IMAGE_SIZE.y,
		CROP.size.x / IMAGE_SIZE.x, CROP.size.y / IMAGE_SIZE.y))
	# Above the card's ring, below the cost badge (which overlaps its left end).
	material.render_priority = 1
	badge.material_override = material
	badge.visible = false
	return badge
