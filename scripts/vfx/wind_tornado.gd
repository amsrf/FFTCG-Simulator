@tool
extends Node3D
## Wind tornado, rebuilt from the "how to cook a tornado" reference (Desktop/Clips/tornado_4.mp4).
## Two copies of one swept, flared mesh, as in the tutorial's step 3: "Body" is translucent smoke
## (shaders/wind_tornado.gdshader) and "Core" is the same mesh drawn additively (wind_tornado_core.gdshader).
## Both share the deformation in wind_tornado.gdshaderinc, so the sections bulge and the axis snakes
## identically. From the second reference (Desktop/Clips/green_tornado_3.mp4): the funnel widens toward the
## top, its surface is cut by texture-driven voids and drawn two-sided, and bowl-shaped "base waves" keep
## spawning at the floor. A few debris pebbles orbit near the floor.
##
## Timeline: the ground swirl starts first, then the funnel grows up from the floor as torn wisps (`reveal`)
## while it fills in; it holds, then tears apart, widens and loses its spin. Driven by `sample(seconds)`, so the
## demo can scrub any moment and the cue only needs `play()`. wind_card_motion.gd times the card from these constants.

@export var autoplay := false
## Overall scale of the funnel (1.0 = base rim radius BASE_RADIUS, height HEIGHT).
@export var size := 1.0
## Lean the column toward the active camera's screen-up so it reads from a top-down view. The column is
## tilted until it makes at least `min_view_angle` degrees with the view direction (max `max_lean`).
@export var camera_lean := true
@export_range(0.0, 90.0) var min_view_angle := 58.0
@export_range(0.0, 80.0) var max_lean := 55.0
## 0 weak .. 3 maximum; set by the cue from the damage amount (set_damage_tier).
@export_range(0, 3) var damage_tier := 1:
	set = set_damage_tier

var length := length_for(1)
var _fade_start := length_for(1) - FADE
var _height := height_for(1)

const GROW_START := 0.18        # the ground swirl has this long to itself before the funnel rises
const BUILDUP := 1.2            # funnel fully grown
const LENGTH := 3.2             # base length; the damage tier adds or removes hold time (length_for)
const FADE := 1.0               # the last FADE seconds: the layers go transparent, inner first (_layer_fade)

## Damage scaling (VfxEvent.damage_tier_for: <=3000 / <=6000 / <9000 / 9000+). A bigger hit makes a taller
## column (vertical scale only; the mouth keeps its width) that holds at full strength for longer.
const TIER_HEIGHT := [0.72, 0.90, 1.10, 1.35]
const TIER_HOLD := [-0.4, 0.2, 0.9, 1.6]     # seconds added to LENGTH
## Fraction of the column's height the card is lifted to (wind_card_motion.gd).
const CARD_LIFT := 0.55

const HEIGHT := 1.45
const BASE_RADIUS := 0.52      # floor rim of the trumpet
const WAIST := 0.13            # narrowest column radius, just above the flare
const TOP := 0.90              # radius at the top: a funnel opening upward, as in green_tornado_3
const FLARE_HEIGHT := 0.09     # how quickly the trumpet closes into the column
const SEGMENTS := 72
const ROWS := 56
const DEBRIS := 12
## The three funnel shells, inner to outer: radius scale, voids cut away, texture phase and speed. Close
## together; the further out, the emptier, until the outermost is just a few stripes.
const LAYERS := [
	{"scale": 0.90, "voids": 0.16, "phase": 0.00, "speed": 1.00, "density": 0.95, "two_sided": true},
	{"scale": 1.00, "voids": 0.30, "phase": 0.41, "speed": 1.12, "density": 0.85, "two_sided": false},
	{"scale": 1.11, "voids": 0.50, "phase": 0.77, "speed": 1.28, "density": 0.80, "two_sided": false},
]
const WAVES := 5               # base-wave rings alive at once
const WAVE_LIFE := 0.95

const BODY_SHADER := preload("res://shaders/wind_tornado.gdshader")
const CORE_SHADER := preload("res://shaders/wind_tornado_core.gdshader")
const WAVE_SHADER := preload("res://shaders/wind_base_wave.gdshader")
const TEXTURES := "res://assets/effects/wind/textures/"

var _body: MeshInstance3D
var _material: ShaderMaterial          # the innermost layer (on Body itself)
var _layer_materials: Array[ShaderMaterial] = []
var _core_material: ShaderMaterial
var _debris: Array[MeshInstance3D] = []
var _waves: Array[MeshInstance3D] = []
var _age := 0.0
var _playing := false

func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = build_mesh()
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_body.material_override = _material
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader sways and wobbles the column beyond its bind-pose bounds.
	_body.extra_cull_margin = 1.5
	add_child(_body)
	for i in LAYERS.size():
		var layer: Dictionary = LAYERS[i]
		var material := _material
		if i > 0:
			var shell := MeshInstance3D.new()
			shell.name = "Layer%d" % i
			shell.mesh = _body.mesh
			material = ShaderMaterial.new()
			material.shader = BODY_SHADER
			shell.material_override = material
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shell.extra_cull_margin = 1.5
			_body.add_child(shell)
		material.render_priority = 0 if i == 0 else i + 1   # inner, core (1), then the outer shells over them
		material.set_shader_parameter("layer_scale", layer.scale)
		material.set_shader_parameter("void_amount", layer.voids)
		material.set_shader_parameter("layer_phase", layer.phase)
		material.set_shader_parameter("layer_speed", layer.speed)
		material.set_shader_parameter("density", layer.density)
		material.set_shader_parameter("two_sided", layer.two_sided)
		_layer_materials.append(material)

	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = _body.mesh
	_core_material = ShaderMaterial.new()
	_core_material.shader = CORE_SHADER
	_core_material.render_priority = 1     # glows through the inner layer; inside the outer shells
	_core_material.set_shader_parameter("layer_scale", LAYERS[0].scale)
	_core_material.set_shader_parameter("void_amount", LAYERS[0].voids)
	core.material_override = _core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.extra_cull_margin = 1.5
	_body.add_child(core)

	for material in _layer_materials + [_core_material]:
		material.set_shader_parameter("wind_tex", _texture("T_VFX_WindNoise1.png"))
		material.set_shader_parameter("distort_tex", _texture("T_Noise1_nk.png"))
		material.set_shader_parameter("cells_tex", _texture("T_Noise_HU85k.png"))

	var bowl := _bowl_mesh()
	var wisps := _texture("T_FirePanningCyl45.png")
	for i in WAVES:
		var wave := MeshInstance3D.new()
		wave.name = "BaseWave%d" % i
		wave.mesh = bowl
		var material := ShaderMaterial.new()
		material.shader = WAVE_SHADER
		material.set_shader_parameter("wisp_tex", wisps)
		material.set_shader_parameter("seed", float(i) * 0.31)
		wave.material_override = material
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wave)
		_waves.append(wave)

	var pebble := SphereMesh.new()
	pebble.radius = 0.014
	pebble.height = 0.022
	pebble.radial_segments = 5
	pebble.rings = 3
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.22, 0.24, 0.18)
	rock.roughness = 1.0
	for i in DEBRIS:
		var piece := MeshInstance3D.new()
		piece.mesh = pebble
		piece.material_override = rock
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)   # not under Body: it is squashed vertically while the funnel grows
		_debris.append(piece)

	reset()
	if Engine.is_editor_hint():
		visible = true
		sample(BUILDUP + 0.5)
	elif autoplay:
		play()

static func radius_at(y: float) -> float:
	var column := lerpf(WAIST, TOP, pow(clampf(y / HEIGHT, 0.0, 1.0), 1.45))
	var flare := (BASE_RADIUS - WAIST) * exp(-y / FLARE_HEIGHT)
	return column + flare

## Surface of revolution of radius_at(). Rows are packed toward the floor so the flare is smooth.
## UV.x = around, UV.y = arc length fraction from the floor rim (so streaks keep their density on the
## flare), UV2.x = height fraction. Normals and tangents are analytic, so the seam has no crease.
static func build_mesh() -> ArrayMesh:
	var heights := PackedFloat32Array()
	var arc := PackedFloat32Array()
	var length := 0.0
	for row in ROWS + 1:
		var y := HEIGHT * pow(float(row) / ROWS, 1.8)
		if row > 0:
			var dy := y - heights[row - 1]
			var dr := radius_at(y) - radius_at(heights[row - 1])
			length += sqrt(dy * dy + dr * dr)
		heights.append(y)
		arc.append(length)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in ROWS + 1:
		var y := heights[row]
		var r := radius_at(y)
		var slope := (radius_at(y + 0.001) - radius_at(maxf(y - 0.001, 0.0))) / (0.002 if y > 0.001 else 0.001)
		for seg in SEGMENTS + 1:
			var u := float(seg) / SEGMENTS
			var a := u * TAU
			var radial := Vector3(cos(a), 0.0, sin(a))
			var normal := Vector3(radial.x, -slope, radial.z).normalized()
			var around := Vector3(-sin(a), 0.0, cos(a))
			st.set_normal(normal)
			st.set_tangent(Plane(around, 1.0))
			st.set_uv(Vector2(u, arc[row] / length))
			st.set_uv2(Vector2(y / HEIGHT, 0.0))
			st.add_vertex(radial * r + Vector3(0.0, y, 0.0))
	var stride := SEGMENTS + 1
	for row in ROWS:
		for seg in SEGMENTS:
			var i0 := row * stride + seg
			var i1 := i0 + 1
			var i2 := i0 + stride
			var i3 := i2 + 1
			# Godot's front faces wind CLOCKWISE: seen from outside, so cull_back keeps the outer surface.
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)
	return st.commit()

## A shallow bowl ring (green_tornado_3's sm_waves_tornado): UV.x around, UV.y from inner to outer rim.
static func _bowl_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var segments := 64
	for row in rings + 1:
		var v := float(row) / rings
		var r := lerpf(0.20, 0.60, v)
		var y := 0.11 * pow(v, 1.6)
		for seg in segments + 1:
			var u := float(seg) / segments
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(cos(u * TAU) * r, y, sin(u * TAU) * r))
	for row in rings:
		for seg in segments:
			var i0 := row * (segments + 1) + seg
			var i2 := i0 + segments + 1
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i2)
			st.add_index(i0 + 1)
			st.add_index(i2 + 1)
			st.add_index(i2)
	return st.commit()

## The imported texture when the editor has imported it; otherwise the raw PNG (headless runs, or before the
## project has been opened since the textures were added).
static func _texture(file: String) -> Texture2D:
	var path := TEXTURES + file
	if ResourceLoader.exists(path):
		return load(path)
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("wind_tornado: cannot load %s" % path)
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func set_damage_tier(tier: int) -> void:
	damage_tier = clampi(tier, 0, 3)
	length = length_for(damage_tier)
	_fade_start = length - FADE
	_height = height_for(damage_tier)

static func length_for(tier: int) -> float:
	return LENGTH + float(TIER_HOLD[clampi(tier, 0, 3)])

static func height_for(tier: int) -> float:
	return float(TIER_HEIGHT[clampi(tier, 0, 3)])

## World height the card is lifted to for this tier (at size 1).
static func card_height_for(tier: int) -> float:
	return HEIGHT * height_for(tier) * CARD_LIFT

func play() -> void:
	_age = 0.0
	_playing = true
	set_process(true)
	sample(0.0)

func reset() -> void:
	_playing = false
	set_process(false)
	hide()

func _process(delta: float) -> void:
	if not _playing or Engine.is_editor_hint():
		return
	_age += delta
	sample(_age)
	if _age >= length:
		reset()

func sample(seconds: float) -> void:
	visible = seconds >= 0.0 and seconds < length
	if _material == null:
		return
	var appear := smoothstep(0.0, 0.3, seconds)
	var ending := smoothstep(_fade_start, length, seconds)
	# Growth: the funnel's front climbs from the floor (ease-out), the body widens and fills in behind it.
	var grow := ease(clampf((seconds - GROW_START) / (BUILDUP - GROW_START), 0.0, 1.0), 0.45)
	var reveal := lerpf(0.0, 1.2, grow)
	var widen := lerpf(0.55, 1.0, ease(clampf(seconds / BUILDUP, 0.0, 1.0), 0.5))
	var dissolve := lerpf(0.55, 0.0, smoothstep(GROW_START, BUILDUP, seconds))
	_body.scale = Vector3(widen, lerpf(0.75, 1.0, grow) * _height, widen) * size
	var spin_time := seconds - maxf(0.0, seconds - _fade_start) * ending * 0.5
	_param("age", spin_time)
	_apply_camera_lean()
	_param("reveal", reveal)
	# Fade from the inside out: the inner shell (and its core glow) goes transparent first, then the middle,
	# and the stripe-like outer shell is the last wind left. Each layer also frays a little as it goes, so it
	# thins into strands rather than dimming evenly.
	for i in _layer_materials.size():
		var gone := _layer_fade(ending, i)
		_layer_materials[i].set_shader_parameter("dissolve", clampf(dissolve + gone * 0.3, 0.0, 1.0))
		_layer_materials[i].set_shader_parameter("opacity", appear * (1.0 - gone))
	var core_gone := _layer_fade(ending, 0)
	_core_material.set_shader_parameter("dissolve", clampf(dissolve + core_gone * 0.3, 0.0, 1.0))
	_core_material.set_shader_parameter("opacity", appear * (1.0 - core_gone))

	# Base waves: a new ring every WAVE_LIFE / WAVES seconds from the very start; none are born once the
	# tornado starts tearing apart, but the ones already alive finish.
	var spacing := WAVE_LIFE / WAVES
	for i in _waves.size():
		var wave := _waves[i]
		var since := seconds - float(i) * spacing
		var cycle := floorf(since / WAVE_LIFE)
		var born := cycle * WAVE_LIFE + float(i) * spacing
		var life := (since - cycle * WAVE_LIFE) / WAVE_LIFE
		wave.visible = since >= 0.0 and born < _fade_start + 0.2
		if not wave.visible:
			continue
		var spread := lerpf(0.55, 1.15, ease(life, 0.6)) * lerpf(0.75, 1.0, appear)
		wave.scale = Vector3(spread, lerpf(0.5, 1.6, life), spread) * size
		wave.rotation.y = seconds * 4.2 + float(i)   # same way as the funnel
		var material := wave.material_override as ShaderMaterial
		material.set_shader_parameter("life", life)
		material.set_shader_parameter("spin", seconds * 0.55)
		material.set_shader_parameter("opacity", 1.0 - ending)

	var debris_on := appear * (1.0 - ending)
	for i in _debris.size():
		var phase := fmod(seconds * 0.55 + float(i) / DEBRIS, 1.0)
		var y := 0.03 + phase * 0.55 * maxf(grow, 0.25) * _height
		var angle := float(i) * 2.399 - seconds * (8.0 - phase * 3.0)   # with the funnel (positive turn about +Y)
		var radius := radius_at(y / _height) * 1.15 + 0.03 + sin(float(i) * 4.1) * 0.02
		_debris[i].position = Vector3(cos(angle) * radius, y, sin(angle) * radius) * size
		_debris[i].rotation = Vector3(seconds * 3.0 + i, angle, 0.4 * i)
		_debris[i].scale = Vector3.ONE * (0.6 + 0.5 * fmod(i * 0.37, 1.0)) * sin(phase * PI) * debris_on * size

## Points the bend at the camera's screen-up, in the body's own frame. Re-read every sample, so a camera that
## moves (seat swap, zoom) is followed.
func _apply_camera_lean() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not camera_lean or camera == null:
		_param("lean_angle", 0.0)
		return
	var to_camera := camera.global_basis.z.normalized()
	var up := Vector3.UP
	var from_vertical := rad_to_deg(acos(clampf(to_camera.dot(up), -1.0, 1.0)))
	var tilt := clampf(min_view_angle - from_vertical, 0.0, max_lean)
	# Screen-up flattened onto the floor: the direction the column's top travels.
	var screen_up := camera.global_basis.y
	var toward := Vector3(screen_up.x, 0.0, screen_up.z)
	if tilt <= 0.0 or toward.length_squared() < 1e-6:
		_param("lean_angle", 0.0)
		return
	var axis_world := up.cross(toward.normalized())
	var axis_local := (_body.global_basis.inverse() * axis_world).normalized()
	_param("lean_axis", axis_local)
	_param("lean_angle", deg_to_rad(tilt))

## How far layer `index` has faded (0 = whole, 1 = gone) at `ending` (0..1 over the last FADE seconds). Staggered
## windows, inner first: 0.00-0.50, 0.25-0.75, 0.50-1.00.
static func _layer_fade(ending: float, index: int) -> float:
	var start := float(index) * 0.25
	return smoothstep(start, start + 0.5, ending)

func _param(parameter: String, value: Variant) -> void:
	for material in _layer_materials:
		material.set_shader_parameter(parameter, value)
	_core_material.set_shader_parameter(parameter, value)
