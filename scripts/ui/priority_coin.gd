extends RefCounted
## Geometry for the large priority sockets. The gold trim belongs to the moving cap.

const METAL := preload("res://shaders/priority_coin.gdshader")
const BRASS_NORMAL := preload("res://assets/board/genpbr_brushed_brass_normal.res")
const BRASS_ROUGHNESS := preload("res://assets/board/genpbr_brushed_brass_roughness.res")
const LEATHER_ALBEDO := preload("res://assets/board/genpbr_black_leather_albedo.res")
const LEATHER_NORMAL := preload("res://assets/board/genpbr_black_leather_normal.res")
const LEATHER_ROUGHNESS := preload("res://assets/board/genpbr_black_leather_roughness.res")
const SECOND_MAIN_IMPRINT := "II"
const ATTACK_PHASE_IMPRINT := "⚔"

# Matches the stamp values in priority_coin.gdshader.
enum Stamp { CRYSTAL, SECOND_MAIN, CROSSED_SWORDS, CROSS }

const AXLE_Y := 0.027
const TURN_LIFT := 0.083
const BORE_RADIUS := 0.279
const WELL_FLOOR_Y := -0.195  # Baked floor at -0.110, relative to the socket origin at 0.085.
const COLLAR_OUTER_RADIUS := 0.313
const RUBY_INNER_RADIUS := COLLAR_OUTER_RADIUS - 0.001
const SOCKET_FOOTPRINT := 0.380
const SOCKET_SPHERE_RADIUS := 0.580
const SOCKET_EDGE_Y := 0.013

const COIN_SCALE := Vector3(0.870, 1.012, 0.870)
const CAP_RADIUS := 0.284
const CAP_EDGE_Y := 0.018
const FRONT_RISE := 0.088
const BACK_RISE := 0.036
const CAP_STEPS := 24
const SEGMENTS := 128
const RIM_INNER_RADIUS := 0.229
const RIM_THICKNESS := 0.0045
const RIM_BEVEL_DEPTH := 0.0012
const EDGE_LIGHT_RADIUS := CAP_RADIUS * COIN_SCALE.x
const EDGE_LIGHT_Y := AXLE_Y + (CAP_EDGE_Y + RIM_THICKNESS - RIM_BEVEL_DEPTH) * COIN_SCALE.y

static var _meshes: Dictionary[StringName, Mesh] = {}


static func stamp_for_imprint(imprint: String) -> Stamp:
	match imprint:
		SECOND_MAIN_IMPRINT:
			return Stamp.SECOND_MAIN
		ATTACK_PHASE_IMPRINT:
			return Stamp.CROSSED_SWORDS
	return Stamp.CRYSTAL


## `cosmos`: the same coin in the Cosmos colours (wood rim, cream stone, slate centre, jade ring, light-wood stamps);
## see `cosmos` in priority_coin.gdshader.
static func build_cap(pivot: Node3D, imprint: Texture2D, cosmos := false) -> ShaderMaterial:
	pivot.scale = COIN_SCALE
	var copper := _material(0, cosmos)
	copper.set_shader_parameter("cap_crown_y", _front_height(0.0))
	copper.set_shader_parameter("brass_inner_radius", RIM_INNER_RADIUS)
	copper.set_shader_parameter("leather_albedo", LEATHER_ALBEDO)
	copper.set_shader_parameter("leather_normal", LEATHER_NORMAL)
	copper.set_shader_parameter("leather_roughness", LEATHER_ROUGHNESS)
	if imprint != null:
		copper.set_shader_parameter("imprint", imprint)
	_add_part(pivot, &"CopperCap", copper, _cap_profile())
	var brass := _material(2, cosmos)
	brass.set_shader_parameter("brass_inner_radius", RIM_INNER_RADIUS)
	_add_part(pivot, &"GoldRim", brass, _rim_profile())
	return copper


static func build_socket(socket: Node3D, cosmos := false) -> ShaderMaterial:
	var ruby := _material(1, cosmos)
	ruby.set_shader_parameter("ruby_glow", 0.0)
	ruby.set_shader_parameter("ruby_radial_range", Vector2(BORE_RADIUS, SOCKET_FOOTPRINT))
	_add_part(socket, &"CopperSocket", ruby, _socket_profile())
	var bronze := _material(3, cosmos)
	_add_part(socket, &"RecessWall", bronze, _collar_profile())
	var lip: Array[Vector2] = []
	for offset: float in [0.0, 0.002, 0.008, 0.010]:
		var r := SOCKET_FOOTPRINT - offset
		var lift := 0.004 if offset > 0.0 and offset < 0.010 else 0.001
		lip.append(Vector2(r, _socket_height(r) + lift))
	_add_part(socket, &"OuterBezel", bronze, lip)
	return ruby


static func _collar_profile() -> Array[Vector2]:
	var outer := COLLAR_OUTER_RADIUS
	var top := _socket_height(BORE_RADIUS) + 0.005
	var profile: Array[Vector2] = [
		Vector2(outer, _socket_height(outer) - 0.003),
		Vector2(outer, _socket_height(outer) + 0.002),
		Vector2(outer - 0.004, _socket_height(outer - 0.004) + 0.006),
	]
	for j in range(7, -1, -1):
		var r := lerpf(BORE_RADIUS + 0.003, outer - 0.008, float(j) / 7.0)
		profile.append(Vector2(r, _socket_height(r) + 0.005))
	profile.append_array([Vector2(BORE_RADIUS, top - 0.002), Vector2(BORE_RADIUS, WELL_FLOOR_Y),
		Vector2(outer, WELL_FLOOR_Y), profile[0]])
	return profile


static func axle_height(angle: float) -> float:
	# Lift off the seat as the disc turns edge-on, clearing the floor of the recess.
	var upright := sin(angle)
	return AXLE_Y + TURN_LIFT * upright * upright


static func _cap_profile() -> Array[Vector2]:
	var profile: Array[Vector2] = []
	for i in range(CAP_STEPS + 1):
		var r := CAP_RADIUS * float(i) / CAP_STEPS
		profile.append(Vector2(r, -0.023 - _spherical_rise(r, CAP_RADIUS, BACK_RISE)))
	profile.append_array([
		Vector2(0.290, -0.017), Vector2(0.292, -0.009), Vector2(0.292, 0.009),
		Vector2(0.289, 0.015),
	])
	for i in range(CAP_STEPS, -1, -1):
		var r := CAP_RADIUS * float(i) / CAP_STEPS
		profile.append(Vector2(r, _front_height(r)))
	return profile


static func _rim_profile() -> Array[Vector2]:
	# The brass is a thin strip pressed to the sphere, including across its width.
	var profile: Array[Vector2] = [
		Vector2(RIM_INNER_RADIUS, _front_height(RIM_INNER_RADIUS) - 0.001),
		Vector2(CAP_RADIUS, _front_height(CAP_RADIUS) - 0.001),
		Vector2(CAP_RADIUS, _front_height(CAP_RADIUS) + RIM_THICKNESS - RIM_BEVEL_DEPTH),
	]
	const BEVEL_WIDTH := 0.0025
	const BAND_STEPS := 8
	for i in range(BAND_STEPS, -1, -1):
		var fraction := float(i) / BAND_STEPS
		var r := lerpf(RIM_INNER_RADIUS + BEVEL_WIDTH, CAP_RADIUS - BEVEL_WIDTH, fraction)
		profile.append(Vector2(r, _front_height(r) + RIM_THICKNESS))
	profile.append(Vector2(RIM_INNER_RADIUS, _front_height(RIM_INNER_RADIUS) + RIM_THICKNESS - RIM_BEVEL_DEPTH))
	profile.append(profile[0])
	return profile


static func _front_height(r: float) -> float:
	return CAP_EDGE_Y + _spherical_rise(r, CAP_RADIUS, FRONT_RISE)


static func _socket_profile() -> Array[Vector2]:
	# Only the spherical surface between the footprint and the circular opening.
	var profile: Array[Vector2] = []
	for i in range(CAP_STEPS + 1):
		var r := lerpf(SOCKET_FOOTPRINT, RUBY_INNER_RADIUS, float(i) / CAP_STEPS)
		profile.append(Vector2(r, _socket_height(r)))
	return profile


static func _socket_height(r: float) -> float:
	return _socket_center_height() + sqrt(SOCKET_SPHERE_RADIUS * SOCKET_SPHERE_RADIUS - r * r)


static func _socket_center_height() -> float:
	return SOCKET_EDGE_Y - sqrt(SOCKET_SPHERE_RADIUS * SOCKET_SPHERE_RADIUS - SOCKET_FOOTPRINT * SOCKET_FOOTPRINT)


static func _spherical_rise(r: float, edge_radius: float, rise: float) -> float:
	var sphere_radius := (edge_radius * edge_radius + rise * rise) / (2.0 * rise)
	return sqrt(sphere_radius * sphere_radius - r * r) - (sphere_radius - rise)


static func _material(component: int, cosmos := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = METAL
	material.set_shader_parameter("component", component)
	material.set_shader_parameter("cosmos", cosmos)
	if component == 2:
		material.set_shader_parameter("brushed_normal", BRASS_NORMAL)
		material.set_shader_parameter("brushed_roughness", BRASS_ROUGHNESS)
	return material


static func _add_part(parent: Node3D, part: StringName, material: Material, profile: Array[Vector2]) -> void:
	if not _meshes.has(part):
		_meshes[part] = _lathe(profile)
	var mesh := MeshInstance3D.new()
	mesh.name = part
	mesh.mesh = _meshes[part]
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


static func _lathe(profile: Array[Vector2]) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(profile.size() - 1):
		var inner := profile[j]
		var outer := profile[j + 1]
		var delta := outer - inner
		var normal := Vector2(delta.y, -delta.x).normalized()
		for i in SEGMENTS:
			var angle := TAU * float(i) / SEGMENTS
			var step := angle + TAU / SEGMENTS
			var u := Vector2(cos(angle), sin(angle))
			var v := Vector2(cos(step), sin(step))
			var left_normal := _around(normal, u)
			var right_normal := _around(normal, v)
			var a := _around(inner, u)
			var b := _around(inner, v)
			var c := _around(outer, v)
			var d := _around(outer, u)
			if inner.x > 0.0:
				_add_triangle(surface, a, b, c, left_normal, right_normal, right_normal)
			if outer.x > 0.0:
				_add_triangle(surface, a, c, d, left_normal, right_normal, left_normal)
	surface.index()
	return surface.commit()


static func _around(point: Vector2, radial: Vector2) -> Vector3:
	return Vector3(point.x * radial.x, point.y, point.x * radial.y)


static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		normal_a: Vector3, normal_b: Vector3, normal_c: Vector3) -> void:
	surface.set_normal(normal_a)
	surface.add_vertex(a)
	surface.set_normal(normal_b)
	surface.add_vertex(b)
	surface.set_normal(normal_c)
	surface.add_vertex(c)
