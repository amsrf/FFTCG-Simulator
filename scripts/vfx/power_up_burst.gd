extends Node3D
## ONE POWER-UP BURST (reference: Desktop/Clips/powerup.mp4), spawned by Card.power_fx under the card it celebrates.
##
##   0.00 s  a red haze blooms and three outlined red swords pop out from the card, fanned: one above the top edge,
##           two at the upper corners leaning outward. Each is born white-hot and cools to red.
##   0.16 s  the swords hold and drift up while red streaks shoot past them.
##   0.62 s  the swords rise away and fade; the haze thins into wisps.
##   0.80 s  NUMBER_START: a second, smaller puff of gas behind the power readout as it counts up and swells
##           (power_display.gd animate_power_up).
##
## Everything is laid out in the CAMERA's screen plane (screen-up, screen-right), measured in card heights: the board
## camera looks almost straight down, so anything built along world Y would collapse to a dot. `top_level` keeps the
## card's own (zone-scaled, half-turned) transform out of it; the card's position is re-read every frame, so the burst
## follows a card that moves. Frees itself after LIFETIME.

const SWORD_SHADER := preload("res://shaders/power_up_sword.gdshader")
const GAS_SHADER := preload("res://shaders/power_up_gas.gdshader")

const NUMBER_START := 0.80
const LIFETIME := 1.95

## Swords: [screen offset of the centre (x, y) in card heights, roll in degrees (+ = leaning left), height, delay].
const SWORDS := [
	[Vector2(0.0, 0.66), 0.0, 0.84, 0.0],
	[Vector2(-0.56, 0.22), 36.0, 0.72, 0.05],
	[Vector2(0.56, 0.22), -36.0, 0.72, 0.05],
]
const SWORD_ASPECT := 120.0 / 220.0
const SWORD_APPEAR := 0.16
const SWORD_EXIT_AT := 0.62
const SWORD_EXIT := 0.30
const SWORD_TINT := Color(1.0, 1.0, 1.0)

const HAZE_PUFFS := 14
const NUMBER_PUFFS := 8
const STREAKS := 6

const RENDER_GAS := 18
const RENDER_STREAK := 21
const RENDER_SWORD := 22

static var _sword_texture: Texture2D = null

var _card: Node3D
var _t := 0.0
var _swords: Array = []      # {node, mat, offset, roll, height, delay}
var _puffs: Array = []       # {node, mat, start, life, from, drift, size0, size1, peak, at_label}
var _streaks: Array = []     # {node, mat, start, x, y, roll}


func setup(card: Node3D, burst_seed: int) -> void:
	_card = card
	top_level = true
	var rng := RandomNumberGenerator.new()
	rng.seed = burst_seed
	var tex: Texture2D = sword_texture()
	for spec in SWORDS:
		var mat := _material(SWORD_SHADER, RENDER_SWORD)
		mat.set_shader_parameter("sword_tex", tex)
		mat.set_shader_parameter("tint", SWORD_TINT)
		_swords.append({"node": _quad("Sword", mat), "mat": mat, "offset": spec[0], "roll": deg_to_rad(spec[1]),
			"height": spec[2], "delay": spec[3]})
	for i in HAZE_PUFFS:
		# Around the card, biased upward (where the swords are), born over the first beat.
		var ang: float = rng.randf_range(-PI * 0.15, PI * 1.15)
		var r: float = rng.randf_range(0.18, 0.58)
		var from := Vector2(cos(ang) * r * 1.2, sin(ang) * r - 0.05)
		_add_puff(rng, rng.randf_range(0.0, 0.12), rng.randf_range(0.85, 1.15), from,
			from.normalized() * rng.randf_range(0.12, 0.30) + Vector2(0.0, rng.randf_range(0.15, 0.32)),
			rng.randf_range(0.40, 0.55), rng.randf_range(0.85, 1.20), rng.randf_range(0.42, 0.62), false)
	for i in NUMBER_PUFFS:
		var from := Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.06, 0.08))
		_add_puff(rng, NUMBER_START + rng.randf_range(0.0, 0.10), rng.randf_range(0.80, 1.05), from,
			Vector2(from.x * 0.6, rng.randf_range(0.10, 0.22)),
			rng.randf_range(0.22, 0.30), rng.randf_range(0.55, 0.75), rng.randf_range(0.45, 0.60), true)
	for i in STREAKS:
		var mat := _material(GAS_SHADER, RENDER_STREAK)
		mat.set_shader_parameter("shape", 1.0)
		_streaks.append({"node": _quad("Streak", mat), "mat": mat, "start": rng.randf_range(0.08, 0.50),
			"x": rng.randf_range(-0.62, 0.62), "y": rng.randf_range(-0.35, 0.25),
			"roll": deg_to_rad(rng.randf_range(-18.0, 18.0))})
	sample(0.0)


func _add_puff(rng: RandomNumberGenerator, start: float, life: float, from: Vector2, drift: Vector2,
		size0: float, size1: float, peak: float, at_label: bool) -> void:
	var mat := _material(GAS_SHADER, RENDER_GAS)
	mat.set_shader_parameter("shape", 0.0)
	mat.set_shader_parameter("seed", rng.randf_range(0.0, 50.0))
	_puffs.append({"node": _quad("Gas", mat), "mat": mat, "start": start, "life": life, "from": from,
		"drift": drift, "size0": size0, "size1": size1, "peak": peak, "at_label": at_label})


func elapsed() -> float:
	return _t


func sword_count() -> int:
	return _swords.size()


func puff_count() -> int:
	return _puffs.size()


## Alpha of each sword right now (probes: they pop in, hold, then go).
func sword_alphas() -> Array:
	var out: Array = []
	for s in _swords:
		out.append(float((s["mat"] as ShaderMaterial).get_shader_parameter("intensity")))
	return out


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME or _card == null or not is_instance_valid(_card):
		queue_free()
		return
	sample(_t)


func sample(t: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _card == null or not is_instance_valid(_card):
		return
	var right: Vector3 = cam.global_basis.x.normalized()
	var up: Vector3 = cam.global_basis.y.normalized()
	var back: Vector3 = cam.global_basis.z.normalized()
	var face: Vector2 = _card.call("_card_face_size")
	var card_basis: Basis = _card.global_basis
	var h: float = face.y * card_basis.z.length()
	var centre: Vector3 = _card.global_position
	var label: Node3D = _card.get("power_label")
	var label_pos: Vector3 = label.global_position if label != null else centre - up * h * 0.6

	for s in _swords:
		_sample_sword(s, t - float(s["delay"]), centre, right, up, back, h)
	for p in _puffs:
		_sample_puff(p, t, label_pos if p["at_label"] else centre, right, up, back, h)
	for s in _streaks:
		_sample_streak(s, t, centre, right, up, back, h)


func _sample_sword(s: Dictionary, t: float, centre: Vector3, right: Vector3, up: Vector3, back: Vector3,
		h: float) -> void:
	var node: MeshInstance3D = s["node"]
	var mat: ShaderMaterial = s["mat"]
	if t <= 0.0:
		node.visible = false
		return
	node.visible = true
	var offset: Vector2 = s["offset"]
	var pos_k := 1.0
	var size_k := 1.0
	var alpha := 1.0
	var flash := 0.0
	var rise := 0.0
	if t < SWORD_APPEAR:
		var u: float = t / SWORD_APPEAR
		var pop: float = _ease_out_back(u)
		pos_k = lerpf(0.35, 1.0, pop)
		size_k = lerpf(0.40, 1.0, pop)
		alpha = smoothstep(0.0, 0.6, u)
		flash = 1.0 - u
	else:
		var held: float = minf(t, SWORD_EXIT_AT) - SWORD_APPEAR
		rise = held * 0.10
		if t > SWORD_EXIT_AT:
			var e: float = clampf((t - SWORD_EXIT_AT) / SWORD_EXIT, 0.0, 1.0)
			rise += 0.40 * e * e
			size_k = 1.0 + 0.08 * e
			alpha = 1.0 - e * e
	var height: float = float(s["height"]) * h * size_k
	var where: Vector2 = offset * pos_k + Vector2(0.0, rise)
	_place(node, centre + (right * where.x + up * where.y) * h, right, up, back, float(s["roll"]),
		height * SWORD_ASPECT, height)
	mat.set_shader_parameter("intensity", alpha)
	mat.set_shader_parameter("flash", flash)
	if alpha <= 0.001:
		node.visible = false


func _sample_puff(p: Dictionary, t: float, origin: Vector3, right: Vector3, up: Vector3, back: Vector3,
		h: float) -> void:
	var node: MeshInstance3D = p["node"]
	var mat: ShaderMaterial = p["mat"]
	var k: float = (t - float(p["start"])) / float(p["life"])
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var ease_k: float = 1.0 - pow(1.0 - k, 2.0)
	var where: Vector2 = Vector2(p["from"]) + Vector2(p["drift"]) * ease_k
	var size: float = lerpf(float(p["size0"]), float(p["size1"]), ease_k) * h
	_place(node, origin + (right * where.x + up * where.y) * h, right, up, back, 0.0, size, size)
	var env: float = smoothstep(0.0, 0.14, k) * pow(1.0 - k, 1.3)
	# The haze is thinner than the number's puff: it must redden the card art, not paint over it.
	var gain: float = 1.25 if p["at_label"] else 0.95
	mat.set_shader_parameter("intensity", env * float(p["peak"]) * gain)
	mat.set_shader_parameter("age", k)


func _sample_streak(s: Dictionary, t: float, centre: Vector3, right: Vector3, up: Vector3, back: Vector3,
		h: float) -> void:
	var node: MeshInstance3D = s["node"]
	var mat: ShaderMaterial = s["mat"]
	var k: float = (t - float(s["start"])) / 0.34
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var roll: float = s["roll"]
	var dir := Vector2(-sin(roll), cos(roll))
	var where: Vector2 = Vector2(s["x"], s["y"]) + dir * (k * 1.0)
	_place(node, centre + (right * where.x + up * where.y) * h, right, up, back, roll, 0.022 * h, 0.40 * h)
	mat.set_shader_parameter("intensity", sin(k * PI) * 0.9)


## A camera-facing quad, rolled in the screen plane.
func _place(node: MeshInstance3D, pos: Vector3, right: Vector3, up: Vector3, back: Vector3, roll: float,
		width: float, height: float) -> void:
	var r: Vector3 = right * cos(roll) + up * sin(roll)
	var u: Vector3 = up * cos(roll) - right * sin(roll)
	node.global_transform = Transform3D(Basis(r * width, u * height, back), pos)


func _material(shader: Shader, priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = priority
	mat.set_shader_parameter("intensity", 0.0)
	return mat


func _quad(node_name: String, mat: ShaderMaterial) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader draws past nothing, but the quad is re-scaled every frame; keep it from being culled mid-flight.
	node.extra_cull_margin = 1.0
	node.visible = false
	add_child(node)
	return node


static func _ease_out_back(u: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var v: float = u - 1.0
	return 1.0 + c3 * v * v * v + c1 * v * v


## The sword glyph, rasterised once from SVG at runtime (no import step, so a headless run never meets a missing
## .import). Blade up; a wide guard whose ends hook down; grip; round pommel. Three passes: a wide faint stroke for
## the glow, a translucent red fill with a red outline, and a thin pale inner line that makes the outline read as lit.
const SWORD_SHAPES := """<path d="M60,8 L82,38 L77,138 L43,138 L38,38 Z"/>
<path d="M9,153 Q9,137 26,138 L94,138 Q111,137 111,153 L111,170 Q105,159 94,159 L26,159 Q15,159 9,170 Z"/>
<rect x="51" y="159" width="18" height="34" rx="3"/>
<circle cx="60" cy="203" r="11"/>"""
const SWORD_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="120" height="220" viewBox="0 0 120 220">
<g fill="none" stroke="#ff2a1a" stroke-opacity="0.28" stroke-width="15" stroke-linejoin="round">%s</g>
<g fill="#e0141a" fill-opacity="0.58" stroke="#ff3826" stroke-width="6" stroke-linejoin="round">%s</g>
<g fill="none" stroke="#ffd2c4" stroke-opacity="0.9" stroke-width="1.4" stroke-linejoin="round">%s</g>
<path d="M60,30 L60,128" stroke="#ff8a70" stroke-opacity="0.8" stroke-width="2.5" stroke-linecap="round"/>
</svg>"""


static func sword_texture() -> Texture2D:
	if _sword_texture != null:
		return _sword_texture
	var image := Image.new()
	var err: Error = image.load_svg_from_string(SWORD_SVG % [SWORD_SHAPES, SWORD_SHAPES, SWORD_SHAPES], 2.0)
	if err != OK or image.is_empty():
		push_error("power_up_burst: the sword SVG did not rasterise (%s)" % error_string(err))
		image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(1, 0.2, 0.15, 0.7))
	image.generate_mipmaps()
	_sword_texture = ImageTexture.create_from_image(image)
	return _sword_texture
