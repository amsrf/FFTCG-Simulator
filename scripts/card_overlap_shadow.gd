extends RefCounted

const MAX_CASTERS := 4

## Shared full silhouettes: only current geometry determines casting and reception.
static func update(container: Node3D, cards: Array,
		strength: float = 0.62, width: float = 0.055, radius: float = 0.03) -> void:
	var camera := container.get_viewport().get_camera_3d()
	var geometry: Array[Dictionary] = []
	for card: Card in cards:
		if not is_instance_valid(card):
			continue
		card.clear_edge_shadow()
		if camera == null or card.get_parent() != container or card.is_dragging or not card.visible:
			continue
		var placement := card.hand_mesh.global_transform
		var face := card._card_face_size()
		var half := face * 0.5
		var bounds := Rect2()
		var depths := Vector2(INF, -INF)
		var first := true
		for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
			var world: Vector3 = placement * corner
			var screen := camera.unproject_position(world)
			bounds = Rect2(screen, Vector2.ZERO) if first else bounds.expand(screen)
			first = false
			var depth := world.dot(camera.global_basis.z)
			depths.x = minf(depths.x, depth)
			depths.y = maxf(depths.y, depth)
		geometry.append({"card": card, "placement": placement, "face": face, "bounds": bounds, "depths": depths})
	for receiver in geometry:
		var candidates: Array[Dictionary] = []
		var receiver_bounds: Rect2 = receiver.bounds
		for caster in geometry:
			if caster.card == receiver.card or caster.depths.y <= receiver.depths.x + 0.00001:
				continue
			var caster_bounds: Rect2 = caster.bounds
			var intersection := receiver_bounds.grow(12.0).intersection(caster_bounds.grow(12.0))
			if not intersection.has_area():
				continue
			if not _can_cover(camera, receiver.placement, caster.placement, intersection):
				continue
			var ray := -camera.project_ray_normal(camera.unproject_position(receiver.placement.origin))
			var gap := maxf(0.0, (caster.placement.origin - receiver.placement.origin).dot(ray))
			var scale_x: float = caster.placement.basis.get_scale().x
			var softness: float = width * caster.face.x + minf(gap * 0.08 / maxf(scale_x, 0.001), caster.face.x * 0.15)
			var opacity: float = strength / (1.0 + gap * 1.5)
			candidates.append({"caster": caster, "softness": softness, "opacity": opacity,
				"score": intersection.get_area() / (1.0 + gap * 4.0)})
		candidates.sort_custom(func(a, b): return a.score > b.score)
		for slot in range(mini(MAX_CASTERS, candidates.size())):
			var candidate: Dictionary = candidates[slot]
			var caster: Dictionary = candidate.caster
			receiver.card.set_overlap_shadow(slot, caster.placement.affine_inverse(), caster.face,
				radius, candidate.opacity, candidate.softness, camera)

## Planar depth comparison at overlap bounds rejects fully-behind candidates.
## Intersecting/tilted cases remain candidates and are resolved per shader pixel.
static func _can_cover(camera: Camera3D, receiver: Transform3D, caster: Transform3D, bounds: Rect2) -> bool:
	var receiver_plane := Plane(receiver.basis.y.normalized(), receiver.origin)
	var caster_plane := Plane(caster.basis.y.normalized(), caster.origin)
	for pixel in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.get_center()]:
		var origin := camera.project_ray_origin(pixel)
		var ray := camera.project_ray_normal(pixel)
		var receiving_hit = receiver_plane.intersects_ray(origin, ray)
		var casting_hit = caster_plane.intersects_ray(origin, ray)
		if receiving_hit != null and casting_hit != null and (receiving_hit - casting_hit).dot(ray) > 0.00001:
			return true
	return false
