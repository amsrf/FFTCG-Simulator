extends Node3D
## A STRONG CARD LANDS (~/Desktop/Clips/entry frames 43-72): played by CardHologram.play_in() at the moment of contact
## for a card whose Field.slam_tier() is 1+ (cost 5+; tier 2, cost 8+, is bigger and longer). In the card's element
## colour (CardHologram.tint()). Presentation only; lives under the tree root and frees itself.
##
##   0.00        contact: the camera shake starts (CardHologram.power_shake) and the RING opens around the card
##   0.00..0.06  the ring snaps out to ~1.9 card heights, speed lines burst through it, a light COLUMN rises up-screen
##   0.04..      the SHOCKWAVE reaches the neighbouring cards in turn: each is LAUNCHED in a short tipped jump, lands,
##               bounces once (CardDamageFx.play_tremor), each its own way
##   0.05..0.36  flames lick up the card's long edges; the ring keeps drifting outward and fades (0.10..0.30), the
##               lines sooner (0.08..0.22), as in the reference (ring gone by frame 62, lines by 60)
##   ~0.38       gone
##
## Everything is a function of the age (`sample`), so a demo can freeze any moment.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const BURST_SHADER := preload("res://shaders/power_entry_burst.gdshader")
const COLUMN_SHADER := preload("res://shaders/power_entry_column.gdshader")
const FLAMES_SHADER := preload("res://shaders/power_entry_flames.gdshader")

## Per tier (index = slam tier 1 / 2): overall size and length.
const TIER_SIZE := [1.0, 0.9, 1.0]
const TIER_LENGTH := [1.0, 0.95, 1.0]
const LIFETIME := 0.38
## The shockwave's speed across the board (metres per second): when each neighbour feels it. Fast: in the reference
## both neighbours leave the board on the same frame; the next ring out follows a frame or two later.
const WAVE_SPEED := 30.0
## How far it reaches (metres, per tier) and how hard it hits the nearest card.
const WAVE_REACH := [0.0, 2.8, 3.6]
const WAVE_STRENGTH := [0.0, 0.9, 1.0]
const RENDER_PRIORITY := 20

var _age := 0.0
var _length := 1.0
var _tier := 1
var _tint := Color.WHITE
var _burst: MeshInstance3D
var _burst_mat: ShaderMaterial
var _column: MeshInstance3D
var _column_mat: ShaderMaterial
var _flames: MeshInstance3D
var _flames_mat: ShaderMaterial
## Probe hooks: which cards the shockwave reached, and when.
var shaken: Array = []


func _ready() -> void:
	set_process(false)


## `face`: the landed card's face (HandMesh) in world. `neighbours`: the other cards on the field. Call after adding
## to the tree.
func setup(face: Transform3D, tint: Color, tier: int, neighbours: Array = []) -> void:
	_tier = clampi(tier, 1, 2)
	_tint = tint
	_length = TIER_LENGTH[_tier]
	global_transform = Transform3D.IDENTITY
	var face_scale: Vector3 = face.basis.get_scale()
	var card_h: float = 0.6 * absf(face_scale.z)
	var card_w: float = 0.429 * absf(face_scale.x)
	var size: float = TIER_SIZE[_tier]
	var cam := _camera_basis()
	var centre: Vector3 = face.origin + Vector3.UP * 0.02

	_burst_mat = _material(BURST_SHADER)
	_burst = _quad("Burst", Vector2.ONE * card_h * 3.8 * size, _burst_mat)
	_burst.global_transform = Transform3D(cam, centre + cam.z * 0.05)

	_column_mat = _material(COLUMN_SHADER)
	var column_h: float = card_h * 3.0 * size
	_column = _quad("Column", Vector2(card_w * 1.15 * size, column_h), _column_mat)
	_column.global_transform = Transform3D(cam, centre + cam.y * column_h * 0.5 + cam.z * 0.04)

	_flames_mat = _material(FLAMES_SHADER)
	_flames_mat.set_shader_parameter("edge", 1.0 / 1.3)
	_flames_mat.set_shader_parameter("seed", float(get_instance_id() % 97))
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.429 * 1.3, 0.6 * 1.1)
	_flames = MeshInstance3D.new()
	_flames.name = "Flames"
	_flames.mesh = plane
	_flames.material_override = _flames_mat
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flames.extra_cull_margin = 2.0
	add_child(_flames)
	_flames.global_transform = face.translated(Vector3.UP * 0.012)

	_shake_neighbours(face.origin, neighbours)
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age >= LIFETIME * _length:
		queue_free()


## The whole burst at `t` seconds after contact.
func sample(t: float) -> void:
	var u: float = t / _length
	# The ring snaps out in ~3 frames, then drifts on while it fades (reference 45 -> 48 -> 62).
	var snap: float = 1.0 - pow(1.0 - clampf(u / 0.06, 0.0, 1.0), 3.0)
	var ring: float = lerpf(0.20, 0.83, snap) + 0.14 * smoothstep(0.06, 0.40, u)
	var ring_fade: float = 1.0 - smoothstep(0.10, 0.30, u)
	_burst_mat.set_shader_parameter("ring_radius", ring)
	_burst_mat.set_shader_parameter("inner_radius", ring * 0.66)
	_burst_mat.set_shader_parameter("ring_width", lerpf(0.05, 0.035, smoothstep(0.0, 0.3, u)))
	_burst_mat.set_shader_parameter("ring_alpha", ring_fade * smoothstep(0.0, 0.015, u))
	_burst_mat.set_shader_parameter("haze_alpha", 0.16 * (1.0 - smoothstep(0.03, 0.18, u)))
	_burst_mat.set_shader_parameter("streak_inner", lerpf(0.22, 0.45, smoothstep(0.0, 0.3, u)))
	_burst_mat.set_shader_parameter("streak_outer", lerpf(0.55, 1.0, snap))
	_burst_mat.set_shader_parameter("streak_alpha", 1.0 - smoothstep(0.08, 0.22, u))
	# Re-dealt every frame, like hand-drawn impact lines.
	_burst_mat.set_shader_parameter("seed", floorf(t * 60.0))
	_burst.visible = u < 0.32
	# Column: shoots up in ~5 frames, holds, fades.
	_column_mat.set_shader_parameter("rise", smoothstep(0.0, 0.08, u))
	_column_mat.set_shader_parameter("intensity", smoothstep(0.0, 0.03, u) * (1.0 - smoothstep(0.12, 0.30, u)))
	_column.visible = u < 0.30
	# Flames on the long edges, from the moment the white leaves the card.
	_flames_mat.set_shader_parameter("time", t)
	_flames_mat.set_shader_parameter("intensity", smoothstep(0.05, 0.10, u) * (1.0 - smoothstep(0.26, 0.36, u)))
	_flames.visible = u > 0.04 and u < 0.36


func _shake_neighbours(origin: Vector3, neighbours: Array) -> void:
	var reach: float = WAVE_REACH[_tier]
	for other in neighbours:
		if other == null or not is_instance_valid(other) or not other.has_method("is_drawn_on_field") \
				or not other.is_drawn_on_field():
			continue
		var offset: Vector3 = other.global_position - origin
		offset.y = 0.0
		var d: float = offset.length()
		if d < 0.05 or d > reach:
			continue
		# The reference throws BOTH neighbours with the full blow: near cards get (almost) all of it, and it only dies
		# away toward the edge of the reach.
		var strength: float = WAVE_STRENGTH[_tier] * (1.0 - smoothstep(0.35, 1.0, d / reach))
		var fx = other.get("damage_fx")
		if fx == null or not fx.has_method("play_tremor"):
			continue
		fx.play_tremor(origin, strength, d / WAVE_SPEED)
		shaken.append({"card": other, "delay": d / WAVE_SPEED, "strength": strength})


func _material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("tint", _tint)
	return material


func _quad(node_name: String, size: Vector2, material: ShaderMaterial) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	add_child(node)
	return node


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_transform.basis.orthonormalized() if cam != null else Basis.IDENTITY
