extends Node3D
## Runtime shatter for a broken card.
##
## Blender owns the ten crack patterns; this node owns the explosion. The
## fractured asset is instantiated at the broken card's transform, the card art
## material is applied only to the CardArt surfaces, and CardShardGlass is used
## for the cut faces and backs.

signal finished

const VARIANTS: Array[PackedScene] = [
	preload("res://Blender/card_shatter_01.glb"),
	preload("res://Blender/card_shatter_02.glb"),
	preload("res://Blender/card_shatter_03.glb"),
	preload("res://Blender/card_shatter_04.glb"),
	preload("res://Blender/card_shatter_05.glb"),
	preload("res://Blender/card_shatter_06.glb"),
	preload("res://Blender/card_shatter_07.glb"),
	preload("res://Blender/card_shatter_08.glb"),
	preload("res://Blender/card_shatter_09.glb"),
	preload("res://Blender/card_shatter_10.glb"),
]
const GLASS_SHADER := preload("res://shaders/card_shard_glass.gdshader")

@export var free_when_done: bool = true
## 0 = random fracture pattern; 1..10 = a fixed Blender variant (useful while tuning).
@export_range(0, 10, 1) var variant_index: int = 0
@export var speed: float = 1.55
@export var speed_variation: float = 0.55
@export var drag: float = 1.1
@export var gravity: float = 2.0
@export var spin_min: float = 0.0
@export var spin_max: float = 45.0
## How quickly tumbling slows down while airborne. The pieces should fall,
## not behave like spinning tops.
@export var spin_drag: float = 2.5
@export var lifetime: float = 2.2
## Shrink only AFTER the piece has landed and rested for landing_hold_seconds.
@export var shrink_enabled: bool = true
@export_range(0.0, 3.0, 0.01) var landing_hold_seconds: float = 0.35
@export var settle_on_floor: bool = false
## Flattening a tumbling piece instantly rotates it about its pivot, which reads
## as a position snap. Settle the rotation over a short time instead.
@export var settle_seconds: float = 0.22
@export var floor_clearance: float = 0.004
@export var impact_jitter: float = 0.075
@export var toward_camera: float = 0.38
## Almost no ramp: the shards leave the card immediately. Raise this if the
## burst needs to read as a slower initial push.
@export var burst_ramp_seconds: float = 0.06
@export var floor_world_y: float = 0.0
@export var land_on_floor: bool = true
@export var floor_friction: float = 5.5
@export var floor_spin_damping: float = 12.0

@export_group("Glass")
@export var glass_tint: Color = Color(0.38, 0.82, 0.96, 1.0)
@export_range(0.0, 1.0, 0.01) var glass_base_alpha: float = 0.38
@export_range(0.0, 1.0, 0.01) var glass_rim_alpha: float = 0.48
@export_range(0.5, 8.0, 0.1) var glass_fresnel_power: float = 2.6
@export_range(0.0, 3.0, 0.01) var glass_rim_emission: float = 0.65

var _running: bool = false
var _age: float = 0.0
var _model: Node3D = null
var _pieces: Array[Node3D] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _base_scales: Array[Vector3] = []
var _floor_local_y: float = -1000.0
var _landed: Array[bool] = []
var _landed_at: Array[float] = []
var _glass_material: ShaderMaterial = null


func _ready() -> void:
	_make_glass_material()


func _make_glass_material() -> void:
	_glass_material = ShaderMaterial.new()
	_glass_material.shader = GLASS_SHADER
	_glass_material.set_shader_parameter("glass_tint", glass_tint)
	_glass_material.set_shader_parameter("base_alpha", glass_base_alpha)
	_glass_material.set_shader_parameter("rim_alpha", glass_rim_alpha)
	_glass_material.set_shader_parameter("fresnel_power", glass_fresnel_power)
	_glass_material.set_shader_parameter("rim_emission", glass_rim_emission)


## Break `card` visually. The caller should add this node to the tree first, so
## the shard scene can inherit a valid world transform.
func burst_from_card(card: Card) -> void:
	if card == null or not is_instance_valid(card) or not is_inside_tree():
		return
	var art: Material = null
	if card.mat != null:
		art = card.mat.duplicate()
		if art is ShaderMaterial:
			art.set_shader_parameter("shadow_strength", 0.0)
	burst(card.global_transform, art)


func burst(from: Transform3D, art_material: Material) -> void:
	_clear()
	# Rebuild from the current exports so Inspector changes apply to the NEXT
	# burst without reloading the preview scene.
	_make_glass_material()
	global_transform = from
	_running = true
	_age = 0.0
	var world_scale_y: float = maxf(global_transform.basis.get_scale().y, 0.0001)
	_floor_local_y = (floor_world_y - global_position.y) / world_scale_y

	var index: int = variant_index
	if index < 1 or index > VARIANTS.size():
		index = (randi() % VARIANTS.size()) + 1
	var variant: PackedScene = VARIANTS[index - 1]
	_model = variant.instantiate() as Node3D
	if _model == null:
		_finish()
		return
	add_child(_model)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	for mesh in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = true
		_assign_materials(mesh, art_material)
		var direction: Vector3 = mesh.position
		var impact: Vector3 = Vector3(
			randf_range(-impact_jitter, impact_jitter), 0.0,
			randf_range(-impact_jitter, impact_jitter))
		direction = (direction - impact).normalized()
		direction += Vector3(
			randf_range(-0.24, 0.24),
			randf_range(-0.08, toward_camera),
			randf_range(-0.24, 0.24))
		if direction.length_squared() < 0.0001:
			direction = Vector3.UP
		direction = direction.normalized()
		_pieces.append(mesh)
		_velocities.append(direction * speed * randf_range(1.0 - speed_variation, 1.0 + speed_variation))
		_spins.append(Vector3(
			_spin_component(), _spin_component(), _spin_component()))
		_base_scales.append(mesh.scale)
		_landed.append(false)
		_landed_at.append(-1.0)

	set_process(true)


func _spin_component() -> float:
	var magnitude: float = randf_range(spin_min, spin_max)
	return magnitude if randi() % 2 == 0 else -magnitude


func _assign_materials(mesh: MeshInstance3D, art_material: Material) -> void:
	if mesh.mesh == null:
		return
	for surface in range(mesh.mesh.get_surface_count()):
		var imported_material: Material = mesh.mesh.surface_get_material(surface)
		var mat_name: String = ""
		if imported_material != null:
			mat_name = imported_material.resource_name
		# Surface 0 is CardArt by construction. The name check keeps this safe
		# if the importer reorders surfaces.
		if mat_name == "CardArt" or (mat_name.is_empty() and surface == 0):
			mesh.set_surface_override_material(surface, art_material)
		else:
			mesh.set_surface_override_material(surface, _glass_material)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _process(delta: float) -> void:
	if not _running:
		return
	_age += delta
	var decay: float = exp(-drag * delta)
	var ramp_t: float = clampf(_age / maxf(burst_ramp_seconds, 0.001), 0.0, 1.0)
	var burst_ramp: float = ramp_t * ramp_t * (3.0 - 2.0 * ramp_t)
	for i in range(_pieces.size()):
		var piece: Node3D = _pieces[i]
		if piece == null or not is_instance_valid(piece):
			continue
		_velocities[i] *= decay
		_velocities[i].y -= gravity * delta
		piece.position += _velocities[i] * delta * burst_ramp
		_spins[i] *= exp(-spin_drag * delta)
		var landing_y: float = _floor_local_y + floor_clearance
		if land_on_floor and piece.position.y <= landing_y:
			piece.position.y = landing_y
			if not _landed[i]:
				_landed[i] = true
				_landed_at[i] = _age
			# STOP DEAD ON CONTACT. Damping still lets a piece slide and rotate
			# after it has landed, which reads as the shards gaining momentum
			# again. Resting means no velocity and no angular velocity.
			_velocities[i] = Vector3.ZERO
			_spins[i] = Vector3.ZERO
			if settle_on_floor:
				# Optional: ease the fragment flat. Disabled for the rest test,
				# because any rotation after landing looks like movement.
				var flat: Vector3 = Vector3(0.0, piece.rotation.y, 0.0)
				var settle_step: float = 1.0
				if settle_seconds > 0.0001:
					settle_step = clampf(delta / settle_seconds, 0.0, 1.0)
				piece.rotation = piece.rotation.lerp(flat, settle_step)
		else:
			piece.rotation += _spins[i] * delta
		var shrink: float = 1.0
		if shrink_enabled and _landed[i]:
			var on_floor: float = _age - _landed_at[i]
			if on_floor > landing_hold_seconds:
				var ramp: float = maxf(lifetime - landing_hold_seconds, 0.01)
				var shrink_t: float = clampf((on_floor - landing_hold_seconds) / ramp, 0.0, 1.0)
				shrink = 1.0 - shrink_t * shrink_t
		piece.scale = _base_scales[i] * shrink
	if _age >= lifetime:
		_finish()


func _clear() -> void:
	_running = false
	_pieces.clear()
	_velocities.clear()
	_spins.clear()
	_base_scales.clear()
	_landed.clear()
	_landed_at.clear()
	if _model != null and is_instance_valid(_model):
		remove_child(_model)
		_model.queue_free()
	_model = null


func _finish() -> void:
	if not _running:
		return
	_clear()
	finished.emit()
	if free_when_done:
		queue_free()
