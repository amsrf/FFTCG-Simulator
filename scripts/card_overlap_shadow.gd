extends RefCounted

## In a stack, later entries cover earlier ones. A hand uses screen order and hover.
static func update(container: Node3D, cards: Array, stack_order: bool, hovered: Card = null,
		overlap_shadow_strength: float = 0.62, overlap_shadow_width: float = 0.055,
		card_corner_radius_m: float = 0.03) -> void:
	var cam := container.get_viewport().get_camera_3d()
	var geometry: Dictionary = {}
	if cam != null:
		for i in range(cards.size()):
			var card: Card = cards[i]
			if card == null or not is_instance_valid(card) or card.get_parent() != container or card.is_dragging:
				continue
			# CURRENT transform, not calculate_card_position(): that returns the destination of
			# a tween which may still be running. The shadow has to sit on the card as drawn.
			var placement: Transform3D = card.hand_mesh.global_transform
			var face: Vector2 = card._card_face_size()
			var left_x: float = cam.unproject_position(placement * Vector3(-face.x * 0.5, 0.0, 0.0)).x
			var right_x: float = cam.unproject_position(placement * Vector3(face.x * 0.5, 0.0, 0.0)).x
			geometry[i] = {
				"placement": placement,
				"x_sign": 1.0 if right_x >= left_x else -1.0,
				"face": face,
				"span": Vector2(minf(left_x, right_x), maxf(left_x, right_x)),
			}

	# Clear first: a card that stops being covered must stop being shadowed.
	for card in cards:
		if card != null and is_instance_valid(card):
			card.clear_edge_shadow()

	if geometry.size() < 2:
		return

	var best: Dictionary = {}
	var indices: Array = geometry.keys()
	for a in range(indices.size()):
		for b in range(a + 1, indices.size()):
			var ia: int = int(indices[a])
			var ib: int = int(indices[b])
			var geo_a: Dictionary = geometry[ia]
			var geo_b: Dictionary = geometry[ib]
			var span_a: Vector2 = geo_a["span"]
			var span_b: Vector2 = geo_b["span"]
			var overlap: float = minf(span_a.y, span_b.y) - maxf(span_a.x, span_b.x)
			if overlap <= 0.0:
				continue

			# Which card is visually above? A hovered card is lifted toward the camera and is
			# therefore above both neighbours; otherwise the one further to screen-right wins,
			# matching the hand's monotonic depth ramp.
			var upper_index: int
			var lower_index: int
			if stack_order:
				upper_index = ib
				lower_index = ia
			elif cards[ia] == hovered or cards[ib] == hovered:
				upper_index = ia if cards[ia] == hovered else ib
				lower_index = ib if upper_index == ia else ia
			else:
				var center_a: float = (span_a.x + span_a.y) * 0.5
				var center_b: float = (span_b.x + span_b.y) * 0.5
				upper_index = ia if center_a > center_b else ib
				lower_index = ib if upper_index == ia else ia

			var upper_span: Vector2 = geo_a["span"] if upper_index == ia else geo_b["span"]
			var lower_span: Vector2 = geo_a["span"] if lower_index == ia else geo_b["span"]
			var lower_width: float = maxf(lower_span.y - lower_span.x, 0.001)
			var lower_center: float = (lower_span.x + lower_span.y) * 0.5
			var upper_center: float = (upper_span.x + upper_span.y) * 0.5
			var side: float = 1.0 if upper_center > lower_center else -1.0

			# The upper card edge is a straight 3D line, but it is rotated independently of the
			# lower card. Project its two endpoints into the LOWER card's UV space and pass the
			# resulting line (edge at v=0.5 plus du/dv), so the shadow tracks the upper edge
			# exactly instead of staying parallel to the lower card's own edge.
			var upper_placement: Transform3D = geo_a["placement"] if upper_index == ia else geo_b["placement"]
			var upper_face: Vector2 = geo_a["face"] if upper_index == ia else geo_b["face"]
			var lower_placement: Transform3D = geo_a["placement"] if lower_index == ia else geo_b["placement"]
			var lower_face: Vector2 = geo_a["face"] if lower_index == ia else geo_b["face"]
			var edge_local_x: float = -side * float(geometry[upper_index]["x_sign"]) * upper_face.x * 0.5
			side *= float(geometry[lower_index]["x_sign"])
			var p0_world: Vector3 = upper_placement * Vector3(edge_local_x, 0.0, -upper_face.y * 0.5)
			var p1_world: Vector3 = upper_placement * Vector3(edge_local_x, 0.0, upper_face.y * 0.5)
			var lower_inv: Transform3D = lower_placement.affine_inverse()
			# Trace the visible edge back onto the receiving face through the camera.
			var plane := Plane(lower_placement.basis.y.normalized(), lower_placement.origin)
			var screen0 := cam.unproject_position(p0_world)
			var screen1 := cam.unproject_position(p1_world)
			var hit0 = plane.intersects_ray(cam.project_ray_origin(screen0), cam.project_ray_normal(screen0))
			var hit1 = plane.intersects_ray(cam.project_ray_origin(screen1), cam.project_ray_normal(screen1))
			if hit0 == null or hit1 == null:
				continue
			var p0: Vector3 = lower_inv * hit0
			var p1: Vector3 = lower_inv * hit1
			var u0: float = 0.5 + p0.x / maxf(lower_face.x, 0.0001)
			var v0: float = 0.5 + p0.z / maxf(lower_face.y, 0.0001)
			var u1: float = 0.5 + p1.x / maxf(lower_face.x, 0.0001)
			var v1: float = 0.5 + p1.z / maxf(lower_face.y, 0.0001)
			var dv: float = v1 - v0
			var slope: float = (u1 - u0) / dv if absf(dv) > 0.0001 else 0.0
			var edge: float = u0 + slope * (0.5 - v0)

			var visible_fraction: float = overlap / lower_width
			var strength: float = overlap_shadow_strength * clampf(visible_fraction / 0.12, 0.45, 1.0)
			# The card mesh has a real rounded corner radius of 0.03 m. Convert it through the
			# upper card's scale and back into the LOWER card's UV, because that is the space
			# the shader draws in.
			var upper_scale: float = (geo_a["placement"] if upper_index == ia else geo_b["placement"]).basis.get_scale().x
			var lower_scale: float = (geo_a["placement"] if lower_index == ia else geo_b["placement"]).basis.get_scale().x
			var radius_local: float = card_corner_radius_m * upper_scale / maxf(lower_scale, 0.0001)
			var corner_u: float = radius_local / maxf(lower_face.x, 0.0001)
			var corner_v: float = radius_local / maxf(lower_face.y, 0.0001)
			var previous: Dictionary = best.get(lower_index, {})
			if previous.is_empty() or overlap > float(previous.get("overlap", 0.0)):
				best[lower_index] = {
					"side": side,
					"edge": edge,
					"slope": slope,
					"strength": strength,
					"v_range": Vector2(minf(v0, v1), maxf(v0, v1)),
					"corner_u": corner_u,
					"corner_v": corner_v,
					"overlap": overlap,
				}

	for index in best:
		var card: Card = cards[int(index)]
		var entry: Dictionary = best[index]
		card.set_edge_shadow(entry["side"], entry["edge"], entry["slope"], entry["strength"],
			overlap_shadow_width, entry["corner_u"], entry["corner_v"], entry["v_range"])
