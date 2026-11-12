extends Node3D
## WHAT A LIGHTNING STRIKE LEAVES BEHIND: a burst of sparks at the hit, and a fissure burnt into the ground that
## outlives the bolt. Presentation only.
##
## Spawned by lightning_strike.gd, but NOT its child: the strike and its cue are freed after ~0.6 s (the presentation
## queue must move on), while the scar stays for a few seconds. So this node lives under the tree root, drives itself
## and frees itself.
##
##   sparks   streaks thrown outward along the board from the impact, arcing, bouncing once and dying - the board
##            camera looks almost straight down, so the outward travel is what reads, not the height
##   scar     jagged cracks (shaders/lightning_scar.gdshader) that open outward at the hit, glow with crawling current
##            while they cool, stay as charred lines, then fade
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const SCAR_SHADER := preload("res://shaders/lightning_scar.gdshader")
const SPARK_SHADER := preload("res://shaders/lightning_spark.gdshader")

## Scar timeline, seconds after the hit: the cracks open, the glow cools (exponential, per second), the charred lines
## hold, then fade out.
const SCAR_OPEN := 0.10
const SCAR_COOLING := 2.2
const SCAR_HOLD := 1.2
const SCAR_FADE := 0.6
## Scar radius in metres at card scale 1, before the tier factor.
const SCAR_RADIUS := 0.50
const SPARK_SECONDS := 0.65
const GRAVITY := 5.5

## Per damage tier (<=3000, <=6000, <9000, 9000+).
const TIER_EXTENT := [0.80, 1.0, 1.22, 1.48]
const TIER_SPARKS := [18, 28, 40, 54]
const TIER_SPARK_SPEED := [0.80, 1.0, 1.18, 1.38]

var _delay := 0.0
var _age := 0.0
var _floor_y := 0.0
var _scar_material: ShaderMaterial
var _spark_mesh: MultiMesh
## Per spark: start, velocity, life (seconds), width, flicker phase.
var _sparks: Array = []
var _hot := Color(0.93, 0.87, 1.0)
var _arc := Color(0.42, 0.10, 1.0)

## `hit` is the impact point on the card face; `floor_y` the board surface under it; `delay` the time until the bolt
## lands. Call after adding to the tree.
func setup(hit: Vector3, floor_y: float, card_scale: float, arc: Color, strike_seed: int, delay: float,
		damage_tier: int) -> void:
	var tier := clampi(damage_tier, 0, 3)
	_delay = maxf(delay, 0.0)
	_floor_y = floor_y
	_arc = arc
	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	global_position = Vector3(hit.x, floor_y, hit.z)

	var radius: float = SCAR_RADIUS * card_scale * TIER_EXTENT[tier]
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	_scar_material = ShaderMaterial.new()
	_scar_material.shader = SCAR_SHADER
	_scar_material.set_shader_parameter("arc_color", arc)
	_scar_material.set_shader_parameter("seed", float(strike_seed % 997))
	_scar_material.set_shader_parameter("grow", 0.0)
	_scar_material.set_shader_parameter("heat", 0.0)
	_scar_material.set_shader_parameter("opacity", 0.0)
	var scar := MeshInstance3D.new()
	scar.name = "Scar"
	scar.mesh = plane
	scar.material_override = _scar_material
	scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scar.rotation.y = rng.randf() * TAU
	add_child(scar)

	var height := hit.y - floor_y + 0.02
	for i in int(TIER_SPARKS[tier]):
		var angle := rng.randf() * TAU
		var speed: float = rng.randf_range(0.5, 1.9) * TIER_SPARK_SPEED[tier] * card_scale
		_sparks.append({
			"start": Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.02, 0.10) * card_scale + Vector3.UP * height,
			"velocity": Vector3(cos(angle) * speed, rng.randf_range(0.5, 1.9), sin(angle) * speed),
			"life": rng.randf_range(0.28, SPARK_SECONDS),
			"width": rng.randf_range(0.022, 0.040) * card_scale,
			"phase": rng.randf() * 40.0,
		})
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_spark_mesh = MultiMesh.new()
	_spark_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_spark_mesh.use_colors = true
	_spark_mesh.mesh = quad
	_spark_mesh.instance_count = _sparks.size()
	var spark_material := ShaderMaterial.new()
	spark_material.shader = SPARK_SHADER
	var sparks := MultiMeshInstance3D.new()
	sparks.name = "Sparks"
	sparks.multimesh = _spark_mesh
	sparks.material_override = spark_material
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.extra_cull_margin = 6.0
	add_child(sparks)
	sample(0.0)

func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age - _delay >= SCAR_OPEN + SCAR_HOLD + SCAR_FADE:
		queue_free()

## The whole aftermath at `seconds` since setup (the demo freezes it for screenshots).
func sample(seconds: float) -> void:
	var t := seconds - _delay
	visible = t >= 0.0
	if t < 0.0:
		return
	_scar_material.set_shader_parameter("grow", clampf(t / SCAR_OPEN, 0.0, 1.0))
	_scar_material.set_shader_parameter("heat", exp(-t * SCAR_COOLING))
	_scar_material.set_shader_parameter("opacity",
		1.0 - smoothstep(0.0, 1.0, (t - SCAR_OPEN - SCAR_HOLD) / SCAR_FADE))
	_sample_sparks(t)

func _sample_sparks(t: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var toward_camera := camera.global_transform.basis.z if camera != null else Vector3.UP
	for i in _sparks.size():
		var s: Dictionary = _sparks[i]
		var life: float = s.life
		if t >= life:
			_spark_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3.ZERO))
			_spark_mesh.set_instance_color(i, Color(0, 0, 0, 0))
			continue
		var state := _ballistic(s, t)
		var at: Vector3 = state[0]
		var velocity: Vector3 = state[1]
		var u := t / life
		# A streak along the velocity, turned to face the camera; longer the faster it flies.
		var along := velocity.normalized() if velocity.length() > 0.01 else Vector3.RIGHT
		var side := toward_camera.cross(along)
		side = side.normalized() if side.length() > 0.001 else Vector3.FORWARD
		var normal := along.cross(side).normalized()
		var length := clampf(velocity.length() * 0.085, 0.045, 0.30) * (1.0 - 0.5 * u)
		var basis := Basis(along * length, side * float(s.width), normal)
		_spark_mesh.set_instance_transform(i, Transform3D(basis, at))
		# White-hot, cooling to the arc violet; every spark twinkles on its own beat and dies out.
		var twinkle := 0.65 + 0.35 * sin(t * 55.0 + float(s.phase))
		var color := _hot.lerp(_arc, smoothstep(0.15, 0.85, u))
		color.a = pow(1.0 - u, 0.8) * twinkle
		_spark_mesh.set_instance_color(i, color)

## Position and velocity of a spark after `t` seconds, local to this node (whose origin is ON the floor): a throw
## under gravity with air drag, and one dull bounce off the board.
static func _ballistic(s: Dictionary, t: float) -> Array:
	var start: Vector3 = s.start
	var velocity: Vector3 = s.velocity
	var drag := exp(-t * 1.6)
	var travelled := (1.0 - drag) / 1.6
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var at := start + flat * travelled
	# Height: solve the landing time, then replay the rest as a bounce at a third of the speed.
	var vy := velocity.y
	var landing := (vy + sqrt(vy * vy + 2.0 * GRAVITY * start.y)) / GRAVITY
	var y: float
	var y_speed: float
	if t <= landing:
		y = start.y + vy * t - 0.5 * GRAVITY * t * t
		y_speed = vy - GRAVITY * t
	else:
		var rebound := (GRAVITY * landing - vy) * 0.32
		var after := t - landing
		y = maxf(rebound * after - 0.5 * GRAVITY * after * after, 0.0)
		y_speed = rebound - GRAVITY * after if y > 0.0 else 0.0
	at.y = y + 0.01
	return [at, Vector3(flat.x * drag, y_speed, flat.z * drag)]
