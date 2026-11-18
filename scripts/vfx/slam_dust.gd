extends RefCounted
## THE DUST A PLAYED CARD KICKS UP when it slams onto the board (card_hologram.gd play_in). Soft puffs leave the card's
## outline and roll outward along the surface it hit, swelling and fading. Sized by slam tier (Field.slam_tier): a cheap card
## puffs, a big one throws a ring. Plain alpha-blended sprites, not additive: dust is not light.
##
## Preloaded by PATH (no class_name).

## Per tier 0 / 1 / 2.
const COUNT: Array[int] = [14, 24, 38]
const SPEED: Array[float] = [1.1, 1.5, 2.0]
const PUFF_SIZE: Array[float] = [0.24, 0.32, 0.42]
const LIFETIME: Array[float] = [0.5, 0.65, 0.85]
const OPACITY: Array[float] = [0.5, 0.6, 0.7]
## Pale sand: the wood's own colour was invisible against it.
const COLOUR := Color(0.95, 0.91, 0.84)

const CARD_EDGE := preload("res://scripts/cards/card_edge.gd")

static var _material: StandardMaterial3D = null

## `face` is the card face's resting pose (where it lands): puffs leave its outline, in its plane.
static func spawn(card: Node3D, face: Transform3D, tier: int) -> CPUParticles3D:
	if card == null or not card.is_inside_tree():
		return null
	var i: int = clampi(tier, 0, COUNT.size() - 1)
	var size: Vector2 = card._card_face_size()
	var scale: Vector3 = face.basis.get_scale()
	var half := Vector2(size.x * 0.5 * scale.x, size.y * 0.5 * scale.z)
	# The outline, in WORLD orientation (the card's yaw), each point with its outward normal.
	var yaw := Basis(Vector3.UP, face.basis.get_euler().y)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var steps := 40
	for k in steps:
		var a: float = TAU * float(k) / float(steps)
		var d := Vector2(cos(a), sin(a))
		# Project the direction onto the rectangle's edge.
		var s: float = minf(half.x / maxf(absf(d.x), 1e-4), half.y / maxf(absf(d.y), 1e-4))
		var p := Vector3(d.x * s, 0.0, d.y * s)
		# A little OUTSIDE the outline: from under the card, puffs are hidden by it until they get clear.
		points.append(yaw * (p + Vector3(d.x, 0.0, d.y) * 0.03))
		normals.append((yaw * Vector3(d.x, 0.0, d.y)).normalized())
	var dust := CPUParticles3D.new()
	dust.name = "SlamDust"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PUFF_SIZE[i]
	# FLAT on the surface, not camera-facing: a standing sprite poked up through the card and clouded its face. Lying
	# in the slab-bottom plane, the opaque card hides the puffs under it and only what rolls out past its edges shows.
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _puff_material()
	dust.mesh = quad
	dust.amount = COUNT[i]
	dust.lifetime = LIFETIME[i]
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.randomness = 0.4
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	dust.emission_points = points
	dust.emission_normals = normals
	dust.direction = Vector3(1.0, 0.0, 0.0)   # along each point's normal, along the surface
	dust.spread = 18.0
	dust.flatness = 0.8
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = SPEED[i] * 0.5
	dust.initial_velocity_max = SPEED[i]
	dust.damping_min = SPEED[i] * 1.2
	dust.damping_max = SPEED[i] * 1.8
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.6))
	dust.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(COLOUR, OPACITY[i]))
	ramp.set_color(1, Color(COLOUR, 0.0))
	ramp.add_point(0.25, Color(COLOUR, OPACITY[i] * 0.8))
	dust.color_ramp = ramp
	card.get_tree().root.add_child(dust)
	# At the slab's BOTTOM, so the puffs roll out from under the piece. (Field cards rest on the wood, so the
	# slab bottom is the wood surface.)
	var bottom: float = CARD_EDGE.FIELD_THICKNESS * scale.y
	dust.global_transform = Transform3D(Basis.IDENTITY, face.origin - Vector3.UP * (bottom - 0.01))
	dust.emitting = true
	dust.get_tree().create_timer(LIFETIME[i] * 1.5 + 0.3).timeout.connect(dust.queue_free)
	return dust

static func _puff_material() -> StandardMaterial3D:
	if _material == null:
		var tex := GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		tex.gradient = g
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.vertex_color_use_as_albedo = true
		_material.albedo_texture = tex
		_material.render_priority = 3
	return _material
