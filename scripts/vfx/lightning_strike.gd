extends Node3D
## One lightning strike into one card.
##
## The cue owns the lifetime; this node owns the visual beat. The bolt is a
## camera-facing quad that descends from above the screen into the card, while
## a horizontal quad on the card carries the impact flare and circular shock
## wave. There is deliberately no card-rim effect: the hit should not redraw
## the target's border. Everything is procedural, so there are no copied art
## assets.
##
## Timing follows Artifact's Thundergod's Wrath per-card damage composite with
## one deliberate change: the strike lands almost immediately. The source bolt
## fades in over 0.1 s, lives 0.4 s and fades out over 0.2 s; here the descent
## is 0.09 s, the hold is 0.10 s and the tail is 0.28 s.

const BOLT_SHADER := preload("res://shaders/lightning_bolt.gdshader")
const IMPACT_SHADER := preload("res://shaders/lightning_impact.gdshader")

const BOLT_WIDTH := 1.28
const BOLT_HEIGHT := 2.95
const REVEAL_SECONDS := 0.09
const HOLD_SECONDS := 0.10
const FADE_SECONDS := 0.28
const LIFETIME := REVEAL_SECONDS + HOLD_SECONDS + FADE_SECONDS

## Per-tier presentation. Index 0 = <=3000, 1 = up to 6000, 2 = up to 8999,
## 3 = 9000+. Only the strike's own properties scale here; the semantic tier
## itself lives on VfxEvent so every future element cue can use the same bands.
const TIER_BOLT_WIDTH := [0.62, 1.0, 1.30, 1.62]
const TIER_BOLT_GLOW := [0.62, 1.0, 1.28, 1.55]
const TIER_BOLT_INTENSITY := [0.76, 1.0, 1.14, 1.30]
const TIER_BOLT_SPAN := [0.90, 1.0, 1.08, 1.16]
const TIER_BOLT_HEIGHT := [0.94, 1.0, 1.05, 1.10]
const TIER_BRANCH := [0.62, 1.0, 1.18, 1.38]
const TIER_IMPACT_EXTENT := [0.84, 1.0, 1.24, 1.52]
const TIER_IMPACT_INTENSITY := [0.70, 1.0, 1.22, 1.48]

var _target_position: Vector3 = Vector3.ZERO
var _target_basis: Basis = Basis.IDENTITY
var _card_face: Vector2 = Vector2(0.411, 0.595)
var _card_scale: float = 1.0
var _tint: Color = Color(0.72, 0.45, 1.0, 1.0)
var _seed: float = 0.0
var _delay: float = 0.0
var _age: float = 0.0
var _tier: int = 1

var _bolt: MeshInstance3D = null
var _bolt_material: ShaderMaterial = null
var _impact: MeshInstance3D = null
var _impact_material: ShaderMaterial = null


func _ready() -> void:
	visible = false
	set_process(false)


## Called once by the cue, after the node is in the tree.
func setup(target: Node3D, tint: Color, strike_seed: int, delay: float,
		damage_tier: int = 1) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	# Use the card's own face-centre helper when it has one. The card root is
	# already centred, but this keeps the strike tied to the documented world
	# point instead of a private assumption.
	if target.has_method("get_global_face_centre"):
		_target_position = target.call("get_global_face_centre")
	else:
		_target_position = target.global_position
	_target_basis = target.global_transform.basis.orthonormalized()
	var basis_scale: Vector3 = target.global_transform.basis.get_scale()
	_card_scale = maxf((absf(basis_scale.x) + absf(basis_scale.z)) * 0.5, 0.01)
	if target.has_method("_card_face_size"):
		var size = target.call("_card_face_size")
		if size is Vector2 and size.x > 0.0 and size.y > 0.0:
			_card_face = size
	_tint = tint
	_seed = float(strike_seed % 9973)
	_delay = maxf(delay, 0.0)
	_tier = clampi(damage_tier, 0, 3)
	_age = 0.0
	_build()
	set_process(true)


func _build() -> void:
	var tier_span: float = TIER_BOLT_SPAN[_tier]
	var tier_height: float = TIER_BOLT_HEIGHT[_tier]
	# --- bolt -------------------------------------------------------------
	# QuadMesh is in the XY plane and its local +Y is screen-up once the cue
	# rotates it to the camera basis.
	var bolt_quad := QuadMesh.new()
	bolt_quad.size = Vector2(BOLT_WIDTH * tier_span, BOLT_HEIGHT * tier_height)
	_bolt_material = ShaderMaterial.new()
	_bolt_material.shader = BOLT_SHADER
	_bolt_material.set_shader_parameter("tint", _tint)
	_bolt_material.set_shader_parameter("core_color", Color(0.93, 0.87, 1.0, 1.0))
	_bolt_material.set_shader_parameter("arc_color", _arc_colour())
	_bolt_material.set_shader_parameter("seed", _seed)
	_bolt_material.set_shader_parameter("reveal", 0.0)
	_bolt_material.set_shader_parameter("fade", 1.0)
	_bolt_material.set_shader_parameter("intensity", 1.45 * TIER_BOLT_INTENSITY[_tier])
	_bolt_material.set_shader_parameter("bolt_width", 0.0042 * TIER_BOLT_WIDTH[_tier])
	_bolt_material.set_shader_parameter("glow_width", 0.060 * TIER_BOLT_GLOW[_tier])
	_bolt_material.set_shader_parameter("branch_strength", 1.0 * TIER_BRANCH[_tier])
	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.mesh = bolt_quad
	_bolt.material_override = _bolt_material
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.extra_cull_margin = 8.0
	add_child(_bolt)

	# Anchor the bottom edge on the card's face centre, then extend up the
	# camera's screen-up axis. Do NOT push the whole quad back along camera Z:
	# that changes the projected position of an off-centre target, which made
	# the strike land above/left of the card. The shaders disable depth testing,
	# so the bolt still draws over the card without a depth offset.
	var cam_basis: Basis = _camera_basis()
	var bottom: Vector3 = _target_position
	var centre: Vector3 = bottom + cam_basis.y * (BOLT_HEIGHT * tier_height * 0.5)
	_bolt.global_transform = Transform3D(cam_basis, centre)

	# --- impact flare and ring -------------------------------------------
	var impact_plane := PlaneMesh.new()
	impact_plane.size = Vector2(_card_face.x * 3.20, _card_face.y * 2.35) \
		* _card_scale * TIER_IMPACT_EXTENT[_tier]
	_impact_material = ShaderMaterial.new()
	_impact_material.shader = IMPACT_SHADER
	_impact_material.set_shader_parameter("tint", _tint)
	_impact_material.set_shader_parameter("arc_color", _arc_colour())
	_impact_material.set_shader_parameter("seed", _seed)
	_impact_material.set_shader_parameter("fade", 0.0)
	_impact_material.set_shader_parameter("flash", 0.0)
	_impact_material.set_shader_parameter("ring_radius", 0.08)
	_impact_material.set_shader_parameter("intensity", 2.15 * TIER_IMPACT_INTENSITY[_tier])
	_impact = MeshInstance3D.new()
	_impact.name = "Impact"
	_impact.mesh = impact_plane
	_impact.material_override = _impact_material
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact.extra_cull_margin = 4.0 * TIER_IMPACT_EXTENT[_tier]
	add_child(_impact)
	_impact.global_transform = Transform3D(_target_basis,
		_target_position + Vector3.UP * 0.006)


func _process(delta: float) -> void:
	_age += delta
	var t: float = _age - _delay
	if t < 0.0:
		visible = false
		return
	visible = true

	# Descend from the top edge to the card. The power curve starts slowly and
	# accelerates into the hit, which is what makes it read as falling rather
	# than as a wipe.
	var reveal_t: float = clampf(t / REVEAL_SECONDS, 0.0, 1.0)
	var reveal: float = pow(reveal_t, 1.55)

	var fade: float = 1.0
	var fade_start: float = REVEAL_SECONDS + HOLD_SECONDS
	if t > fade_start:
		fade = 1.0 - clampf((t - fade_start) / FADE_SECONDS, 0.0, 1.0)
		fade = fade * fade * (3.0 - 2.0 * fade)
	_bolt_material.set_shader_parameter("reveal", reveal)
	_bolt_material.set_shader_parameter("fade", fade)

	# The flare and shockwave only start once the head reaches the card. They
	# are allowed to outlive the bolt, so the card keeps crackling after the
	# flash.
	var hit_t: float = t - REVEAL_SECONDS
	if hit_t < 0.0:
		_impact_material.set_shader_parameter("fade", 0.0)
		_impact_material.set_shader_parameter("flash", 0.0)
	else:
		var impact_t: float = clampf(hit_t / 0.38, 0.0, 1.0)
		var impact_fade: float = pow(1.0 - impact_t, 1.55)
		var flash: float = exp(-hit_t * 13.0)
		var ring_radius: float = lerpf(0.08, 0.84, sqrt(impact_t))
		_impact_material.set_shader_parameter("fade", impact_fade)
		_impact_material.set_shader_parameter("flash", flash)
		_impact_material.set_shader_parameter("ring_radius", ring_radius)
		_impact_material.set_shader_parameter("ring_width", lerpf(0.050, 0.018, impact_t))

	if t >= LIFETIME:
		queue_free()


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	# The headless probe has no meaningful camera; a fixed basis still gives
	# the shader a valid transform without changing any asserted state.
	return Basis.IDENTITY


func _arc_colour() -> Color:
	# Match references/violet_thunder.jpg: the white-hot core is deliberately
	# kept, while the inner glow is magenta-violet and the outer halo is the
	# deeper element violet. This is not a flat violet bolt.
	return _tint.lerp(Color(0.42, 0.06, 1.0, 1.0), 0.72)
