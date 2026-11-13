extends Node3D
## ONE SHIELD TEAR ON ONE CARD: the card can no longer block (the `block_disabled` status). Drawn in the power-up
## swords' fashion (power_up_burst.gd): blue gas blooms over the card, an ethereal blue shield glyph (rasterised at
## runtime from SVG) ARISES out of it to sit near the TOP of the card, holds for a beat, and then it tears
## into two halves that drift apart, tilt outward, drop and fade while a last puff of gas bursts from the tear.
##
##   0 .. ~0.30               blue gas blooms over the upper card, blue streaks shoot up (the power-up's gas shader)
##   RISE_START .. RISE_END   the shield rises from the card's centre to its place, fading in and growing; a soft white
##                            flash as it settles
##   SPLIT_START .. SPLIT_END   the halves separate (a white flash and a puff as it gives way); they fade from FADE_START
##
## Everything is laid out in the CAMERA's screen plane (screen-up, screen-right), measured in card heights, exactly like
## the swords: `top_level`, re-reading the card's position every frame, depth test off. sample(t) is deterministic.
## The cue (shield_tear_cue.gd) holds the presentation queue only until the shield has torn.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const PIECE_SHADER := preload("res://shaders/shield_tear.gdshader")
## The power-up's gas and streaks, recoloured blue through their rim/core uniforms.
const GAS_SHADER := preload("res://shaders/power_up_gas.gdshader")
const GAS_RIM := Color(0.02, 0.10, 0.42)
const GAS_CORE := Color(0.30, 0.66, 1.0)

const RISE_START := 0.08
const RISE_END := 0.42
const SPLIT_START := 0.54
const SPLIT_END := 0.86
const FADE_START := 0.66
const LIFETIME := 1.04
## How long the cue holds the presentation queue: until the halves are visibly apart.
const APPEAR_SECONDS := 0.66

## The build-up gas: puffs over the upper card, born over the first beat; streaks shooting up past the shield; and a
## small burst at the tear.
const BUILD_PUFFS := 11
const TEAR_PUFFS := 4
const STREAKS := 5

## Where the shield sits: its centre this far UP the screen from the card's centre (the top edge is at 0.5), and its
## height. In card heights.
const CENTRE_UP := 0.30
## Where the rise starts: the card's centre.
const RISE_FROM := 0.0
const HEIGHT := 0.46
const ASPECT := 120.0 / 140.0
## How far the halves travel when fully apart: sideways, down, and their outward tilt (degrees).
const SPLIT_X := 0.13
const SPLIT_DROP := 0.10
const SPLIT_ROLL := 17.0

const RENDER_GAS := 18
const RENDER_STREAK := 21
const RENDER_PIECE := 22

static var _textures: Dictionary = {}

var _card: Node3D
var _age := 0.0
var _left: MeshInstance3D
var _right: MeshInstance3D
var _state := {}   # probe view of the last sample
var _puffs: Array = []     # {node, mat, start, life, from, drift, size0, size1, peak}
var _streaks: Array = []   # {node, mat, start, x, y, roll}


func _ready() -> void:
	set_process(false)


## Call after adding to the tree.
func setup(card: Node3D) -> void:
	_card = card
	top_level = true
	_left = _quad("LeftHalf", piece_texture("left"), RENDER_PIECE)
	_right = _quad("RightHalf", piece_texture("right"), RENDER_PIECE)
	var rng := RandomNumberGenerator.new()
	rng.seed = card.get_instance_id()
	for i in BUILD_PUFFS:
		# Over the upper card, biased toward where the shield will stand; they drift up into it.
		var from := Vector2(rng.randf_range(-0.24, 0.24), rng.randf_range(-0.12, 0.30))
		_add_puff(rng, rng.randf_range(0.0, 0.18), rng.randf_range(0.65, 0.85), from,
			Vector2(from.x * 0.20, rng.randf_range(0.14, 0.28)), rng.randf_range(0.28, 0.38),
			rng.randf_range(0.55, 0.72), rng.randf_range(0.40, 0.55))
	for i in TEAR_PUFFS:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var from := Vector2(side * rng.randf_range(0.0, 0.06), CENTRE_UP + rng.randf_range(-0.16, 0.14))
		_add_puff(rng, SPLIT_START + rng.randf_range(0.0, 0.06), rng.randf_range(0.40, 0.50), from,
			Vector2(side * rng.randf_range(0.10, 0.20), rng.randf_range(0.04, 0.12)), rng.randf_range(0.16, 0.22),
			rng.randf_range(0.38, 0.50), rng.randf_range(0.45, 0.60))
	for i in STREAKS:
		var mat := _gas_material(RENDER_STREAK)
		mat.set_shader_parameter("shape", 1.0)
		_streaks.append({"node": _mesh("Streak", mat), "mat": mat, "start": rng.randf_range(0.04, 0.34),
			"x": rng.randf_range(-0.40, 0.40), "y": rng.randf_range(-0.30, 0.05),
			"roll": deg_to_rad(rng.randf_range(-14.0, 14.0))})
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or _card == null or not is_instance_valid(_card):
		queue_free()
		return
	sample(_age)


## The whole tear at `t` seconds (deterministic, so a demo can freeze any moment).
func sample(t: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _card == null or not is_instance_valid(_card):
		return
	var right: Vector3 = cam.global_basis.x.normalized()
	var up: Vector3 = cam.global_basis.y.normalized()
	var back: Vector3 = cam.global_basis.z.normalized()
	var face: Vector2 = _card.call("_card_face_size")
	var h: float = face.y * _card.global_basis.z.length()
	var centre: Vector3 = _card.global_position

	for p in _puffs:
		_sample_puff(p, t, centre, right, up, back, h)
	for st in _streaks:
		_sample_streak(st, t, centre, right, up, back, h)

	# The rise: out of the gas at the card's centre, up to its place, fading in and growing. A steady ease in and out
	# (an overshoot easing covered most of the distance in the first frames, which read as a pop, not a rise).
	var u: float = clampf((t - RISE_START) / (RISE_END - RISE_START), 0.0, 1.0)
	var pop: float = u * u * (3.0 - 2.0 * u)
	var size_k: float = lerpf(0.60, 1.0, pop)
	var lift: float = lerpf(RISE_FROM, CENTRE_UP, pop)
	# A soft white flash as it settles, and a sharper one as it gives way.
	var flash: float = exp(-pow((t - RISE_END) / 0.07, 2.0)) * 0.55
	var s: float = 1.0 - pow(1.0 - clampf((t - SPLIT_START) / (SPLIT_END - SPLIT_START), 0.0, 1.0), 2.2)
	flash = maxf(flash, exp(-pow((t - SPLIT_START) / 0.04, 2.0)) * 0.6)
	var alpha: float = smoothstep(0.0, 0.7, u) * (1.0 - smoothstep(FADE_START, LIFETIME, t))
	var height: float = HEIGHT * h * size_k
	var at: Vector2 = Vector2(0.0, lift)

	for side in [-1.0, 1.0]:
		var node: MeshInstance3D = _left if side < 0.0 else _right
		var where: Vector2 = at + Vector2(side * SPLIT_X * s, -SPLIT_DROP * s * s)
		_place(node, centre + (right * where.x + up * where.y) * h, right, up, back,
			deg_to_rad(-side * SPLIT_ROLL * s), height * ASPECT, height)
		_paint(node, alpha, flash)
	_state = {"lift": lift, "split": s, "alpha": alpha, "flash": flash, "size": size_k}


func _add_puff(rng: RandomNumberGenerator, start: float, life: float, from: Vector2, drift: Vector2,
		size0: float, size1: float, peak: float) -> void:
	var mat := _gas_material(RENDER_GAS)
	mat.set_shader_parameter("shape", 0.0)
	mat.set_shader_parameter("seed", rng.randf_range(0.0, 50.0))
	_puffs.append({"node": _mesh("Gas", mat), "mat": mat, "start": start, "life": life, "from": from,
		"drift": drift, "size0": size0, "size1": size1, "peak": peak})


## A gas puff (power_up_burst.gd _sample_puff): eases along its drift, grows, swells in and thins away.
func _sample_puff(p: Dictionary, t: float, centre: Vector3, right: Vector3, up: Vector3, back: Vector3,
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
	_place(node, centre + (right * where.x + up * where.y) * h, right, up, back, 0.0, size, size)
	mat.set_shader_parameter("intensity", smoothstep(0.0, 0.14, k) * pow(1.0 - k, 1.3) * float(p["peak"]))
	mat.set_shader_parameter("age", k)


## A streak shooting up the screen (power_up_burst.gd _sample_streak).
func _sample_streak(st: Dictionary, t: float, centre: Vector3, right: Vector3, up: Vector3, back: Vector3,
		h: float) -> void:
	var node: MeshInstance3D = st["node"]
	var mat: ShaderMaterial = st["mat"]
	var k: float = (t - float(st["start"])) / 0.32
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var roll: float = st["roll"]
	var dir := Vector2(-sin(roll), cos(roll))
	var where: Vector2 = Vector2(st["x"], st["y"]) + dir * (k * 0.8)
	_place(node, centre + (right * where.x + up * where.y) * h, right, up, back, roll, 0.020 * h, 0.34 * h)
	mat.set_shader_parameter("intensity", sin(k * PI) * 0.85)


func _gas_material(priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GAS_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("rim_color", GAS_RIM)
	mat.set_shader_parameter("core_color", GAS_CORE)
	return mat


func _paint(node: MeshInstance3D, alpha: float, flash: float) -> void:
	var mat := node.material_override as ShaderMaterial
	mat.set_shader_parameter("intensity", alpha)
	mat.set_shader_parameter("flash", flash)
	node.visible = alpha > 0.001


## Probe hooks.
func age() -> float:
	return _age

## How many gas puffs are showing right now.
func visible_puffs() -> int:
	var n := 0
	for p in _puffs:
		if (p["node"] as Node3D).visible:
			n += 1
	return n

## The last sample: lift (card heights up from the centre), split 0..1, alpha, flash, size.
func state() -> Dictionary:
	return _state

## The farthest a half reaches sideways from the card's centre when fully apart, in metres (its outer edge plus the
## outward tilt of its top corner).
func max_visible_half_width() -> float:
	if _card == null:
		return 0.0
	var face: Vector2 = _card.call("_card_face_size")
	var h: float = face.y * _card.global_basis.z.length()
	var half_w: float = HEIGHT * ASPECT * 0.5
	var tilt: float = HEIGHT * 0.5 * sin(deg_to_rad(SPLIT_ROLL))
	return (half_w + SPLIT_X + tilt) * h


## A camera-facing quad, rolled in the screen plane (power_up_burst.gd).
func _place(node: MeshInstance3D, pos: Vector3, right: Vector3, up: Vector3, back: Vector3, roll: float,
		width: float, height: float) -> void:
	var r: Vector3 = right * cos(roll) + up * sin(roll)
	var u: Vector3 = up * cos(roll) - right * sin(roll)
	node.global_transform = Transform3D(Basis(r * width, u * height, back), pos)


func _quad(node_name: String, tex: Texture2D, priority: int) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = PIECE_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("piece_tex", tex)
	mat.set_shader_parameter("intensity", 0.0)
	return _mesh(node_name, mat)


func _mesh(node_name: String, mat: ShaderMaterial) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 1.0
	node.visible = false
	add_child(node)
	return node


static func _ease_out_back(u: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var v: float = u - 1.0
	return 1.0 + c3 * v * v * v + c1 * v * v


## THE SHIELD GLYPH, in the swords' three passes: a wide faint glow stroke, a translucent blue fill with a bright
## outline, and a pale inner line that makes the outline read as lit; plus a faint inset rim. Each half is the whole
## shield CLIPPED to its side of the zigzag tear, so the two halves rejoin exactly.
const SHIELD_PATH := "M14,12 L106,12 L106,60 Q106,106 60,132 Q14,106 14,60 Z"
const INSET_PATH := "M24,21 L96,21 L96,60 Q96,99 60,120 Q24,99 24,60 Z"
const TEAR_POINTS := "60,4 54,22 65,40 55,58 66,76 55,94 64,112 59,136"
const SHIELD_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="120" height="140" viewBox="0 0 120 140">
<defs><clipPath id="side"><polygon points="%s"/></clipPath></defs>
<g clip-path="url(#side)">
<path d="%s" fill="none" stroke="#3aa6ff" stroke-opacity="0.30" stroke-width="14" stroke-linejoin="round"/>
<path d="%s" fill="#2f86ff" fill-opacity="0.42" stroke="#6ccaff" stroke-width="5" stroke-linejoin="round"/>
<path d="%s" fill="none" stroke="#9edcff" stroke-opacity="0.55" stroke-width="2" stroke-linejoin="round"/>
<path d="%s" fill="none" stroke="#e4f6ff" stroke-opacity="0.9" stroke-width="1.3" stroke-linejoin="round"/>
</g>
</svg>"""
static func piece_texture(which: String) -> Texture2D:
	if _textures.has(which):
		return _textures[which]
	# "left" or "right": the shield clipped to that side of the zigzag.
	var edge: String = "0,0" if which == "left" else "120,0"
	var foot: String = "0,140" if which == "left" else "120,140"
	var side: String = "%s %s %s" % [edge, TEAR_POINTS, foot]
	var svg: String = SHIELD_SVG % [side, SHIELD_PATH, SHIELD_PATH, INSET_PATH, SHIELD_PATH]
	var image := Image.new()
	var err: Error = image.load_svg_from_string(svg, 3.0)
	if err != OK or image.is_empty():
		push_error("shield_tear: the %s SVG did not rasterise (%s)" % [which, error_string(err)])
		image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.3, 0.6, 1.0, 0.6))
	image.generate_mipmaps()
	_textures[which] = ImageTexture.create_from_image(image)
	return _textures[which]
