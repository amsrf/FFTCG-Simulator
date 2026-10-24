extends Node3D
class_name LightOrb
## An orb of light that leaves a comet trail behind it.
##
## THREE LAYERS MAKE THE LIGHT READ AS A SOURCE, not as a ball:
##   * a small emissive sphere — the core;
##   * a camera-facing halo quad with a soft radial falloff (`shaders/orb_halo.gdshader`) — the atmosphere;
##   * an OmniLight3D — the light that lands on the board.
##
## The halo is doing the work bloom would normally do. gl_compatibility ignores Environment glow, so nothing here
## BLOOMS, and an emissive sphere on its own only ever makes the sphere brighter — it still has a hard silhouette and
## reads as a ball. A soft falloff around it is what makes the same shape look like it is radiating
## outwards. The OmniLight3D matters for the same reason from the other side: it lights the SURROUNDINGS, so an orb
## with nothing near it looks inert no matter how bright it is. Light it without giving it something to fall on and
## the effect is invisible.
##
## THE TRAIL IS A RIBBON REBUILT IN CODE, NOT A PARTICLE TRAIL.
##
## The obvious implementation is Godot's built-in trail feature — a GPUParticles3D with `trail_enabled` and a
## RibbonTrailMesh draw pass. **That does not work on this project's renderer.** Running it prints, twice, from
## drivers/gles3/storage/particles_storage.cpp:
##
##     "The Compatibility renderer does not support particle trails."
##
## so the ribbon is built by hand instead: the orb's world position is pushed into a short history, and every frame an
## ArrayMesh is rebuilt as a triangle strip through those points, tapering from `trail_width` at the head to nothing at
## the tail. The look is the same one the particle version was reaching for — billboarded, tapering to a point,
## additive and unshaded, fading out with vertex colour.
##
## THE HISTORY IS IN WORLD SPACE, which is the whole trick. Nothing here tracks a path or knows how the orb is moved:
## the orb is simply sampled as it goes, so a script, a tween, an animation or a physics body all leave the same
## trail. The ribbon node is `top_level`, so it ignores this node's transform — it is drawing in the world, not
## relative to the orb.
##
## ...and that is why teleport_to() exists. A world-space trail joins whatever was left behind to wherever the orb is
## now, so a teleport would draw one long streak across the board. It clears the history instead.
##
## EVERYTHING IS BUILT IN CODE, not in a .tres, and that is deliberate: orb_color has to reach the orb, the halo, the
## light, the ribbon, the sparks and their ramps, and a shared resource would leak that between instances — the same
## trap the gem button hit, where every button on the screen turned grey together.

const HALO_SHADER := preload("res://shaders/orb_halo.gdshader")

@export var orb_color: Color = Color(0.72, 0.94, 1.0, 1.0):
	set(value):
		orb_color = value
		_apply_colour()

@export var orb_radius: float = 0.25:
	set(value):
		orb_radius = value
		_apply_radius()

@export var emission_energy: float = 4.0:
	set(value):
		emission_energy = value
		_apply_colour()

## How solid the core sphere looks: 1.0 is an opaque ball, lower lets the halo and the background show through it.
##
## A little transparency is what stops the core reading as a solid disc. An unshaded surface has no shading to soften
## its edge and no headroom to keep its colour at the centre, so the only thing that can break up the silhouette is
## letting what is behind it through. The halo sits behind, so at 0.78 the glow shows *inside* the sphere rather than
## only around it.
@export var orb_core_alpha: float = 0.78:
	set(value):
		orb_core_alpha = value
		_apply_colour()

## How bright the halo around the orb is. This is the "diffuse light" dial — it is what bloom would otherwise do.
@export var halo_intensity: float = 1.8:
	set(value):
		halo_intensity = value
		_apply_colour()

## How many orb radii across the halo is. 3 makes a halo that reaches well past the sphere's silhouette.
@export var halo_scale: float = 3.0:
	set(value):
		halo_scale = value
		_apply_radius()

@export var light_energy: float = 4.0:
	set(value):
		light_energy = value
		_apply_light()

## How far the light reaches, as a multiple of the orb radius. Generous by default: the pool it throws is the clearest
## sign that this thing is a light source rather than a bright object.
@export var light_range_multiplier: float = 14.0:
	set(value):
		light_range_multiplier = value
		_apply_light()

## How long the trail lives, in seconds. The history is trimmed to this, so it is the trail's length in time.
@export var trail_lifetime: float = 0.4:
	set(value):
		trail_lifetime = value

## Width of the ribbon where it leaves the orb, in metres. By default this is the orb's own DIAMETER (2 x 0.25), so the
## trail starts flush with the sphere and tapers from there to a point at the tail.
@export var trail_width: float = 0.50:
	set(value):
		trail_width = value

## How far the orb must move before another point is recorded, in metres. Small makes a smoother ribbon; too small and
## a slow-moving orb piles up hundreds of coincident points.
@export var trail_sample_step: float = 0.02

@export var spark_amount: int = 24:
	set(value):
		spark_amount = value
		_apply_sparks()

@onready var orb_node: MeshInstance3D = $Orb
@onready var light_node: OmniLight3D = $Light
@onready var sparks_node: GPUParticles3D = $Sparks

var _orb_mesh: SphereMesh = null
var _orb_material: StandardMaterial3D = null
var _halo: MeshInstance3D = null
var _halo_mesh: QuadMesh = null
var _halo_material: ShaderMaterial = null
var _spark_material: StandardMaterial3D = null
var _spark_ramp: Gradient = null
var _ribbon: MeshInstance3D = null
var _ribbon_material: StandardMaterial3D = null
## World positions, newest last, with the age of each in seconds. Two parallel arrays because both get trimmed and
## walked together and a Dictionary per point would be the slowest way to do something this small.
var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _surface := SurfaceTool.new()

func _ready() -> void:
	_build()
	_apply_radius()
	_apply_colour()
	_apply_light()
	_apply_sparks()

func _process(delta: float) -> void:
	_face_camera()
	_advance_history(delta)
	_rebuild_ribbon()

## Keeps the halo facing the camera: take the camera's whole basis, so the quad ends up parallel to the screen rather
## than merely pointing at a position.
##
## THE PARENT CHECK IS NOT DEFENSIVE NOISE. The orb is queue_freed the moment it arrives, and a node on its way out
## can be asked to render one more frame with a freed (zero) parent basis — setting `global_transform` then inverts
## that basis and Godot prints "Condition det == 0 is true". There is nothing to face in that case, so leave it.
func _face_camera() -> void:
	if _halo == null or not is_instance_valid(_halo) or not _halo.is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var parent_node: Node3D = _halo.get_parent() as Node3D
	if parent_node == null or not parent_node.is_inside_tree():
		return
	if absf(parent_node.global_transform.basis.determinant()) < 0.000001:
		return
	_halo.global_transform = Transform3D(cam.global_transform.basis, _halo.global_position)

## Records where the orb is now and forgets anything older than the trail's lifetime.
func _advance_history(delta: float) -> void:
	for i in range(_ages.size()):
		_ages[i] += delta
	while _points.size() > 0 and _ages[0] > trail_lifetime:
		_points.remove_at(0)
		_ages.remove_at(0)
	var here: Vector3 = global_position
	if _points.is_empty() or here.distance_to(_points[_points.size() - 1]) >= trail_sample_step:
		_points.append(here)
		_ages.append(0.0)

## Builds the ribbon as a triangle strip through the history: two vertices per point, offset either side of the path,
## tapering to nothing at the tail and fading out with vertex colour.
func _rebuild_ribbon() -> void:
	if _ribbon == null:
		return
	var n: int = _points.size()
	if n < 2:
		_ribbon.mesh = null
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	_surface.clear()
	# TRIANGLES, not a strip, because the ribbon is feathered ACROSS its width: four vertices per point, with the outer
	# pair fully transparent. A two-vertex strip has hard long edges by construction — it is a flat wedge — and that is
	# what made the trail read as a paper dart sitting next to a soft, volumetric orb.
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across: PackedFloat32Array = PackedFloat32Array([-1.0, -0.45, 0.45, 1.0])
	var across_alpha: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 1.0, 0.0])
	var sides: Array[Vector3] = []
	var halves: Array[float] = []
	var alphas: Array[float] = []
	for i in range(n):
		# 0 at the oldest point (a point), 1 at the orb (full width).
		var t: float = float(i) / float(n - 1)
		var ahead: Vector3 = _points[mini(i + 1, n - 1)]
		var behind: Vector3 = _points[maxi(i - 1, 0)]
		var along: Vector3 = ahead - behind
		if along.length_squared() < 0.0000001:
			along = Vector3.FORWARD
		along = along.normalized()
		# Face the camera: the ribbon is one flat sheet, so a fixed orientation would vanish whenever it turned
		# edge-on to the view.
		var facing: Vector3 = (cam.global_position - _points[i]).normalized() if cam != null else Vector3.UP
		var side: Vector3 = along.cross(facing)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		sides.append(side.normalized())
		halves.append(trail_width * 0.5 * t)
		# Fade BOTH ends. The tail fades because that is the trail dying. The head fades because the newest point sits
		# at the orb's CENTRE, so the ribbon stops dead inside the sphere — hidden while the core was opaque, but
		# through a translucent core that ending shows as a hard vertical seam splitting the orb into a bright half and
		# a dim one. Fading towards the centre makes the trail dissolve into the orb instead of being clipped by it.
		alphas.append(t * 0.9 * (1.0 - smoothstep(0.6, 1.0, t)))
	for i in range(n - 1):
		for c in range(3):
			_emit_quad(i, c, i + 1, c + 1, across, across_alpha, sides, halves, alphas)
	_ribbon.mesh = _surface.commit()

## Two triangles for the quad between (row_a, column_a) and (row_b, column_b). Written out rather than indexed
## because SurfaceTool wants the vertices in emission order and there are only a few hundred of them.
func _emit_quad(row_a: int, col_a: int, row_b: int, col_b: int,
		across: PackedFloat32Array, across_alpha: PackedFloat32Array,
		sides: Array[Vector3], halves: Array[float], alphas: Array[float]) -> void:
	var p00: Vector3 = _points[row_a] + sides[row_a] * (halves[row_a] * across[col_a])
	var p01: Vector3 = _points[row_a] + sides[row_a] * (halves[row_a] * across[col_b])
	var p10: Vector3 = _points[row_b] + sides[row_b] * (halves[row_b] * across[col_a])
	var p11: Vector3 = _points[row_b] + sides[row_b] * (halves[row_b] * across[col_b])
	var a00: float = alphas[row_a] * across_alpha[col_a]
	var a01: float = alphas[row_a] * across_alpha[col_b]
	var a10: float = alphas[row_b] * across_alpha[col_a]
	var a11: float = alphas[row_b] * across_alpha[col_b]
	_emit_vertex(p00, a00)
	_emit_vertex(p10, a10)
	_emit_vertex(p11, a11)
	_emit_vertex(p00, a00)
	_emit_vertex(p11, a11)
	_emit_vertex(p01, a01)

func _emit_vertex(at: Vector3, alpha: float) -> void:
	var shade: Color = orb_color
	shade.a = alpha
	_surface.set_color(shade)
	_surface.add_vertex(at)

## Creates every resource this node owns. Called once, from _ready().
func _build() -> void:
	# ---- the core: a bright unshaded sphere -------------------------------------------------------------------
	_orb_mesh = SphereMesh.new()
	_orb_mesh.radial_segments = 32
	_orb_mesh.rings = 16
	_orb_material = StandardMaterial3D.new()
	_orb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_material.emission_enabled = true
	_orb_material.emission_energy_multiplier = emission_energy
	orb_node.mesh = _orb_mesh
	orb_node.material_override = _orb_material

	# ---- the halo: a camera-facing quad with a radial falloff, i.e. the diffuse light -------------------------
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = HALO_SHADER
	_halo_mesh = QuadMesh.new()
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = _halo_mesh
	_halo.material_override = _halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Behind the core, so the sphere sits inside its own glow rather than on top of it. Additive blending would hide
	# the difference either way, but draw order still decides which is occluded.
	_halo.position = Vector3(0.0, 0.0, -0.05)
	add_child(_halo)

	# ---- the ribbon: a node of our own, top_level so it works in WORLD space -----------------------------------
	_ribbon_material = StandardMaterial3D.new()
	_ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# The per-vertex alpha above is the fade; without this it would be ignored and the tail would end in a hard edge.
	_ribbon_material.vertex_color_use_as_albedo = true
	# A strip is single-sided, so from behind it would be invisible.
	_ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_material.emission_enabled = true
	_ribbon = MeshInstance3D.new()
	_ribbon.name = "TrailRibbon"
	_ribbon.material_override = _ribbon_material
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# WORLD SPACE: the history is absolute positions, so this must not inherit the orb's transform.
	_ribbon.top_level = true
	add_child(_ribbon)

	# ---- the sparks: ordinary particles, which the Compatibility renderer does support -------------------------
	_spark_ramp = Gradient.new()
	_spark_ramp.set_color(0, Color(1, 1, 1, 1.0))
	_spark_ramp.set_color(1, Color(1, 1, 1, 0.0))
	var spark_process := ParticleProcessMaterial.new()
	spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_process.emission_sphere_radius = 0.12
	spark_process.direction = Vector3(0, 1, 0)
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = 0.10
	spark_process.initial_velocity_max = 0.45
	spark_process.gravity = Vector3.ZERO
	spark_process.damping_min = 1.0
	spark_process.damping_max = 2.5
	# The ramp and the curve are TEXTURES here, not raw Gradient/Curve: the inspector shows a gradient editor for
	# color_ramp, which is exactly why assigning a Gradient to it looks right and fails to parse.
	var spark_ramp_tex := GradientTexture1D.new()
	spark_ramp_tex.gradient = _spark_ramp
	spark_process.color_ramp = spark_ramp_tex
	var spark_scale := Curve.new()
	spark_scale.add_point(Vector2(0.0, 1.0))
	spark_scale.add_point(Vector2(1.0, 0.0))
	var spark_scale_tex := CurveTexture.new()
	spark_scale_tex.curve = spark_scale
	spark_process.scale_curve = spark_scale_tex
	sparks_node.process_material = spark_process
	# World space, so the sparks are left behind rather than dragged along.
	sparks_node.local_coords = false
	sparks_node.lifetime = 0.35
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.018
	spark_mesh.height = 0.036
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	sparks_node.draw_pass_1 = spark_mesh
	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.vertex_color_use_as_albedo = true
	spark_mesh.material = _spark_material

## Moves the orb and clears the trail behind it.
##
## A world-space trail draws a line from wherever it was left to wherever the orb is now, so moving it any real distance
## without this leaves one long streak across the board. The trail is doing exactly what it was told, which is why the
## fix is to clear the history rather than to fight it.
func teleport_to(pos: Vector3) -> void:
	global_position = pos
	_points.clear()
	_ages.clear()
	if _ribbon != null:
		_ribbon.mesh = null
	if sparks_node != null:
		sparks_node.restart()

func _apply_radius() -> void:
	if _orb_mesh != null:
		_orb_mesh.radius = orb_radius
		_orb_mesh.height = orb_radius * 2.0
	if _halo_mesh != null:
		var across: float = orb_radius * 2.0 * halo_scale
		_halo_mesh.size = Vector2(across, across)
	_apply_light()

## orb_color reaches the core, the halo, the light, the ribbon, the sparks AND their ramps. Anything keyed off the
## colour belongs here, or a recoloured orb would leave a trail of the old one.
func _apply_colour() -> void:
	if _orb_material != null:
		# The alpha is folded in HERE rather than set once in _build(), because this is also what a colour change runs:
		# assigning orb_color straight to albedo_color would silently put the core back to fully opaque.
		_orb_material.albedo_color = Color(orb_color.r, orb_color.g, orb_color.b, orb_core_alpha)
		# Only turn the transparent pass on when it is asked for, so an opaque orb still sorts against the board the
		# way an opaque surface should.
		_orb_material.transparency = (BaseMaterial3D.TRANSPARENCY_ALPHA if orb_core_alpha < 1.0
			else BaseMaterial3D.TRANSPARENCY_DISABLED)
		_orb_material.emission = orb_color
		_orb_material.emission_energy_multiplier = emission_energy
	if _halo_material != null:
		_halo_material.set_shader_parameter("halo_color", orb_color)
		_halo_material.set_shader_parameter("intensity", halo_intensity)
	if _ribbon_material != null:
		_ribbon_material.albedo_color = orb_color
		_ribbon_material.emission = orb_color
		_ribbon_material.emission_energy_multiplier = emission_energy
	if _spark_material != null:
		_spark_material.albedo_color = orb_color
		_spark_material.emission = orb_color
		_spark_material.emission_energy_multiplier = emission_energy
	var bright: Color = orb_color
	bright.a = 0.9
	var gone: Color = orb_color
	gone.a = 0.0
	if _spark_ramp != null:
		_spark_ramp.set_color(0, bright)
		_spark_ramp.set_color(1, gone)
	if light_node != null:
		light_node.light_color = orb_color
		light_node.light_energy = light_energy

func _apply_light() -> void:
	if light_node == null:
		return
	light_node.light_color = orb_color
	light_node.light_energy = light_energy
	light_node.omni_range = orb_radius * light_range_multiplier
	light_node.shadow_enabled = false

func _apply_sparks() -> void:
	if sparks_node == null:
		return
	sparks_node.amount = maxi(spark_amount, 1)
	sparks_node.emitting = spark_amount > 0
