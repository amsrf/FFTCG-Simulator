extends Node3D
## EARTH BREAK: a long golden crystal of light rises up out of the ground through the card, sinks back, and the card
## breaks once it has gone back down. Presentation only.
##
## The card shown is the HELD stand-in (Vfx.hold_card): the rules already put the real card in the Break Zone. The
## card stays where it is (it is not carried); when the descent ends this node calls
## Vfx.release_hold(..., shatter = true).
##
##   0.00  RISE      the crystal slides up out of the ground, through the card, until EXPOSED (80%) of it is out -
##                   the rest stays below ground; a flare of light where it comes through
##   RISE  HOLD      it stands blazing, the card trembling
##   HOLD  DESCENT   it slides back down (slowly); FADE_DELAY into the descent it starts VANISHING from the top down,
##                   faster than it sinks, mist coming off the vanishing front; the card shatters when the descent ends
## The ground is the card's face (shader `cut_y`): nothing of the crystal is drawn below it, so its foot never shows.
##
## The board camera looks almost straight down, so a vertical crystal is seen end-on and its length is invisible. Its
## axis LEANS toward the camera's screen-up (LEAN): that is what shows it rising.
## Preloaded by PATH (no class_name).

const SHADER := preload("res://shaders/earth_break_crystal.gdshader")
const GLOW_SHADER := preload("res://shaders/orb_halo.gdshader")
const BURST_SHADER := preload("res://shaders/earth_break_burst.gdshader")
## The explosion of light at the base, blasting up the spike: its width, and its height as a fraction of the spike.
const BURST_WIDTH := 1.05
const BURST_HEIGHT := 0.80

## The light gathers under the card before the spike erupts: it swells, flickering faster and faster, then the
## spike bursts out of it at full blaze.
const BUILDUP := 0.40
const GROW := 0.32
const HOLD := 0.40
## The descent (sinking back to below ground) is the slower of the two and starts first; the top-down fade starts
## FADE_DELAY into it and is done in FADE, before the sinking ends.
const DESCENT := 0.75
const FADE_DELAY := 0.12
const FADE := 0.45
## How much of the crystal comes out above the ground at its highest (the rest stays below).
const EXPOSED := 0.80
const DURATION := BUILDUP + GROW + HOLD + DESCENT + 0.10
## Mist puffs released along the vanishing front during the descent, and how long each lasts.
const MIST_PUFFS := 16
const MIST_SECONDS := 0.55
## Crystal length (metres) and radius, per damage tier. A break by effect uses the top tier.
const TIER_LENGTH: Array[float] = [1.60, 1.85, 2.10, 2.40]
## Half-width of the spike's square base (the bottom fifth of it is below the ground).
const RADIUS := 0.24
const SIDES := 4
## How far the crystal's axis leans toward screen-up (0 = vertical).
const LEAN := 0.55
const TREMBLE := 0.008
## The crystal is hidden up to this height above the card face and fades in over FADE_IN above that, so where it
## comes through the card there is no visible end: it seems to pour out of the card.
const CUT_ABOVE_FACE := 0.0
const FADE_IN := 0.34

var _crystal: MeshInstance3D
var _material: ShaderMaterial
var _glow: MeshInstance3D
## The explosion of light at the spike's base, blasting upward along it: it buries the base.
var _core: MeshInstance3D
var _core_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _axis := Vector3.UP
var _foot := Vector3.ZERO
var _length := 1.4
var _card: Card = null
var _stand_in: Node3D = null
var _visual: Dictionary = {}
var _card_home := Transform3D.IDENTITY
var _age := 0.0
var _broken := false
var _mist: Array = []   # [{node, material, age, drift}]
var _mist_released := 0
var _rng := RandomNumberGenerator.new()

## `card` is the real (held) card, `visual` its target_visuals entry carrying the stand-in.
func play(card: Card, visual: Dictionary, tier: int, seed_value: int) -> void:
	_card = card
	_visual = visual
	_stand_in = visual.get("stand_in", null)
	_card_home = visual.get("transform", Transform3D.IDENTITY)
	_length = TIER_LENGTH[clampi(tier, 0, 3)]
	# The GROUND it rises out of is the card's face (the shader cuts there), so EXPOSED is measured from it - not from
	# the Field node, which sits well below the face and would bury far more than the bottom fifth.
	_foot = _card_home.origin
	var screen_up := Vector3.BACK
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		screen_up = camera.global_basis.y
	screen_up.y = 0.0
	screen_up = screen_up.normalized() if screen_up.length() > 0.001 else Vector3.BACK
	_axis = (Vector3.UP + screen_up * LEAN).normalized()
	_rng.seed = seed_value
	_build(seed_value)
	_material.set_shader_parameter("cut_y", _card_home.origin.y + CUT_ABOVE_FACE)
	_sample(0.0)
	set_process(true)

func _process(delta: float) -> void:
	_age += delta
	_sample(_age)
	_update_mist(delta)
	if _age >= DURATION + MIST_SECONDS:
		queue_free()

## Everything at `t` seconds.
func _sample(t: float) -> void:
	# Build-up: `b` 0..1 over BUILDUP, eased in so the light accelerates into the eruption; `t` is then the spike's own
	# clock, starting when the build-up ends (the crystal is fully below the ground until then).
	var b := clampf(t / BUILDUP, 0.0, 1.0)
	var build := b * b * b
	var flicker := 1.0 + 0.22 * b * sin(t * (16.0 + 48.0 * b))
	var raw_t := t
	t = maxf(t - BUILDUP, 0.0)
	var erupted := raw_t >= BUILDUP
	# How much of the crystal is out above the ground: up to EXPOSED on the rise (fast, easing out), back to nothing on
	# the descent (slow, easing in). It SLIDES; the shader's ground cut (`cut_y`) hides whatever is below.
	var d := clampf((t - GROW - HOLD) / DESCENT, 0.0, 1.0)
	var out: float
	if t < GROW + HOLD:
		out = EXPOSED * (1.0 - pow(1.0 - clampf(t / GROW, 0.0, 1.0), 3.0))
	else:
		out = EXPOSED * (1.0 - d * d)
	var f := clampf((t - GROW - HOLD - FADE_DELAY) / FADE, 0.0, 1.0)
	var vanish := smoothstep(0.0, 1.0, f)
	var origin := _foot + _axis * _length * (out - 1.0)
	_crystal.global_transform = Transform3D(_basis(), origin)
	_crystal.visible = out > 0.005 and vanish < 0.999
	_material.set_shader_parameter("reach", 1.0)
	_material.set_shader_parameter("vanish", vanish)
	var pulse := 1.0 + 0.08 * sin(t * 30.0) if t > GROW and t < GROW + HOLD else 1.0
	_material.set_shader_parameter("intensity", pulse)
	# The flare where it comes through the card: hot as it bursts out, a steady glow while it stands, gone as the
	# vanishing front passes the card.
	# Down with the spike as it sinks. During the build-up both glows swell from nothing and arrive exactly at the
	# eruption's values, so there is no jump when the spike breaks through.
	var present := 1.0 - smoothstep(0.55, 1.0, d)
	if erupted:
		_glow_material.set_shader_parameter("intensity", (exp(-t * 6.0) * 0.6 + 0.25) * present)
		_glow.scale = Vector3.ONE * (0.8 + 0.4 * (1.0 - exp(-t * 8.0)))
		# The burst shoots up ahead of the spike, flares hard at the eruption and settles to a steady blaze.
		var shot := 1.0 - pow(1.0 - clampf(t / (GROW * 0.7), 0.0, 1.0), 3.0)
		_core_material.set_shader_parameter("reach", lerpf(0.30, 1.0, shot))
		_core_material.set_shader_parameter("intensity", (exp(-t * 5.0) * 1.2 + 1.05) * present)
	else:
		_glow_material.set_shader_parameter("intensity", 0.85 * build * flicker)
		_glow.scale = Vector3.ONE * (0.45 + 0.35 * b)
		# A pool of light low on the card, its plume only starting to lift.
		_core_material.set_shader_parameter("reach", lerpf(0.12, 0.30, build))
		_core_material.set_shader_parameter("intensity", 2.25 * build * flicker)
	# Mist off the vanishing front (it eats the crystal from the top down), released evenly through the fade.
	if f > 0.0:
		while _mist_released < MIST_PUFFS and float(_mist_released) / MIST_PUFFS <= f:
			_release_mist(origin + _axis * _length * clampf(1.06 - vanish * 1.12, 0.0, 1.0))
			_mist_released += 1
	if _broken or not is_instance_valid(_stand_in):
		return
	# The card breaks only once the crystal has gone back down.
	if d >= 1.0:
		_broken = true
		Vfx.release_hold(_card, _visual, true)
		return
	# The card is not carried: it stays on its slot, trembling once the crystal is through it.
	# It starts to quiver as the light gathers beneath it.
	var shake := Vector3(sin(raw_t * 83.0), 0.0, cos(raw_t * 71.0)) * TREMBLE * (1.0 if erupted else 0.6 * build)
	_stand_in.global_transform = Transform3D(_card_home.basis, _card_home.origin + shake)

func _release_mist(at: Vector3) -> void:
	if not is_inside_tree() or at.y < _card_home.origin.y:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * _rng.randf_range(0.16, 0.26)
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("halo_color", Color(1.0, 0.88, 0.62, 1.0))
	material.set_shader_parameter("falloff", 1.6)
	material.set_shader_parameter("skirt_amount", 0.9)
	material.set_shader_parameter("intensity", 0.0)
	var puff := MeshInstance3D.new()
	puff.mesh = quad
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	var camera := get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera != null else Basis.IDENTITY
	var side := facing.x * _rng.randf_range(-1.0, 1.0) * RADIUS * 1.2
	puff.global_transform = Transform3D(facing, at + side)
	var drift := (facing.x * _rng.randf_range(-1.0, 1.0) * 0.25 + _axis * _rng.randf_range(0.10, 0.30))
	_mist.append({"node": puff, "material": material, "age": 0.0, "drift": drift})

func _update_mist(delta: float) -> void:
	for i in range(_mist.size() - 1, -1, -1):
		var m: Dictionary = _mist[i]
		m.age += delta
		var u: float = m.age / MIST_SECONDS
		var puff: MeshInstance3D = m.node
		if u >= 1.0 or not is_instance_valid(puff):
			if is_instance_valid(puff):
				puff.queue_free()
			_mist.remove_at(i)
			continue
		puff.global_position += (m.drift as Vector3) * delta
		puff.scale = Vector3.ONE * (1.0 + u * 1.6)
		# Swells in quickly, then thins away.
		(m.material as ShaderMaterial).set_shader_parameter("intensity", 1.3 * smoothstep(0.0, 0.15, u) * pow(1.0 - u, 1.5))

func _basis() -> Basis:
	var x := _axis.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, _axis, x.cross(_axis).normalized())

## A tall, thin, square-based pyramid, `_length` from base to tip, tapering all the way (reference: Clips/impale2).
## Its base is open: it is always below the ground (the shader's `cut_y`). Corners jittered a little, the tip slightly
## off centre.
func _build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ring: Array[Vector3] = []
	for k in SIDES:
		var angle := TAU * (float(k) + 0.5) / SIDES + rng.randf_range(-0.08, 0.08)
		var r := RADIUS * sqrt(2.0) * rng.randf_range(0.92, 1.06)
		ring.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var tip := Vector3(rng.randf_range(-0.015, 0.015), _length, rng.randf_range(-0.015, 0.015))
	for k in SIDES:
		_tri(tool, ring[k], ring[(k + 1) % SIDES], tip)
	tool.generate_normals()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("seed", float(seed_value % 997))
	_material.set_shader_parameter("fade_in", FADE_IN)
	_crystal = MeshInstance3D.new()
	_crystal.name = "Crystal"
	_crystal.mesh = tool.commit()
	_crystal.material_override = _material
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crystal.extra_cull_margin = 2.0
	add_child(_crystal)
	# A camera-facing glow at the foot (the Compatibility renderer has no bloom).
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.0
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	# The blaze at the spike's base (the reference's brightest part).
	_glow_material.set_shader_parameter("halo_color", Color(1.0, 0.82, 0.45, 1.0))
	_glow_material.set_shader_parameter("falloff", 2.0)
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	_glow.mesh = quad
	_glow.material_override = _glow_material
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	var camera := get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera != null else Basis.IDENTITY
	# Both glows are camera-facing quads; lifted toward the camera so the board does not slice them along a hard line.
	var toward_camera := facing.z * 0.35
	_glow.global_transform = Transform3D(facing, _card_home.origin + _axis * 0.05 + toward_camera)
	var burst_height := _length * BURST_HEIGHT
	var core_quad := QuadMesh.new()
	core_quad.size = Vector2(BURST_WIDTH, burst_height)
	_core_material = ShaderMaterial.new()
	_core_material.shader = BURST_SHADER
	_core_material.set_shader_parameter("seed", float(seed_value % 97))
	_core = MeshInstance3D.new()
	_core.name = "BaseBlaze"
	_core.mesh = core_quad
	_core.extra_cull_margin = 2.0
	_core.material_override = _core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	# Drawn after the spike, so the blaze sits over its base.
	_core_material.render_priority = 1
	_glow_material.render_priority = 1
	# Facing the camera, its +Y running up the spike AS SEEN ON SCREEN; its hot core (16% up the quad, see the
	# shader) sits right on the spike's base.
	var up_on_screen := (_axis - facing.z * _axis.dot(facing.z)).normalized()
	var across := up_on_screen.cross(facing.z).normalized()
	var burst_basis := Basis(-across, up_on_screen, facing.z)
	if burst_basis.determinant() < 0.0:
		burst_basis = Basis(across, up_on_screen, facing.z)
	_core.global_transform = Transform3D(burst_basis,
		_card_home.origin + toward_camera + up_on_screen * burst_height * (0.5 - 0.16))

## UV.y carries the height along the crystal (0 base, 1 tip) for the shader.
func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for p: Vector3 in [a, b, c]:
		tool.set_uv(Vector2(0.0, p.y / _length))
		tool.add_vertex(p)
