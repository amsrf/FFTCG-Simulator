extends Node3D
## Runtime presentation of a broken card. Every break goes through this node (Game.break_card, a held break
## released by the Vfx director, the clash's defeated proxy), and `style` decides the look:
##
## DESTROY_BURST (default): the card pops in a white flash and bursts into crystal shards of its element, one wind
## swirl opening into a bubble, and sparkles - scripts/vfx/card_destroy_burst.gd (reference: Clips/destroy, 145-205).
##
## GLASS_SHATTER: Blender owns the ten crack patterns; this node owns the explosion. The
## fractured asset is instantiated at the broken card's transform, the card art
## material is applied only to the CardArt surfaces, and CardShardGlass is used
## for the cut faces and backs.

signal finished

enum Style { DESTROY_BURST, GLASS_SHATTER }

const DESTROY_BURST := preload("res://scripts/vfx/card_destroy_burst.gd")

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
const FLASH_SHADER := preload("res://shaders/card_shatter_flash.gdshader")

@export var style: Style = Style.DESTROY_BURST
@export var free_when_done: bool = true
## 0 = random fracture pattern; 1..10 = a fixed Blender variant (useful while tuning).
@export_range(0, 10, 1) var variant_index: int = 0
@export var speed: float = 2.40
@export var speed_variation: float = 0.55
@export var drag: float = 0.65
@export var gravity: float = 1.20
@export var spin_min: float = 0.0
@export var spin_max: float = 45.0
## How quickly tumbling slows down while airborne. The pieces should fall,
## not behave like spinning tops.
@export var spin_drag: float = 2.5
@export var lifetime: float = 2.20
## Shrink from this fraction of the lifetime onward. Shrinking is tied to TIME,
## not to landing: a fragment that is still bouncing keeps getting smaller
## instead of freezing at full size and then popping out.
@export var shrink_enabled: bool = true
@export_range(0.0, 0.95, 0.01) var shrink_from: float = 0.12
@export var settle_on_floor: bool = false
## Flattening a tumbling piece instantly rotates it about its pivot, which reads
## as a position snap. Settle the rotation over a short time instead.
@export var settle_seconds: float = 0.22
@export var floor_clearance: float = 0.004
@export var impact_jitter: float = 0.075
@export var toward_camera: float = 0.52
## Almost no ramp: the shards leave the card immediately. Raise this if the
## burst needs to read as a slower initial push.
@export var burst_ramp_seconds: float = 0.06
@export var floor_world_y: float = 0.0
## OFF by default: fragments should continue their arc and shrink away, not land
## and then wait to disappear. The floor code remains for the preview/optional tuning.
@export var land_on_floor: bool = false
@export var floor_friction: float = 4.0
@export var floor_spin_damping: float = 5.0
## Vertical energy kept after a floor hit. A small bounce keeps the burst
## alive instead of pinning every fragment to the floor in one frame.
@export_range(0.0, 1.0, 0.01) var floor_bounce: float = 0.28

@export_group("Glass")
@export var glass_tint: Color = Color(0.38, 0.82, 0.96, 1.0)
@export_range(0.0, 1.0, 0.01) var glass_base_alpha: float = 0.38
@export_range(0.0, 1.0, 0.01) var glass_rim_alpha: float = 0.48
@export_range(0.5, 8.0, 0.1) var glass_fresnel_power: float = 2.6
@export_range(0.0, 3.0, 0.01) var glass_rim_emission: float = 0.65

@export_group("Burst Flash")
## The reference burst is a bright white flash with a travelling gold shock ring, not just
## fragments. The Compatibility renderer has no bloom, so the flash is an additive quad.
@export var flash_enabled: bool = true
@export_range(0.05, 1.5, 0.01) var flash_seconds: float = 0.24
## Flash diameter relative to a card height (0.6 m x the card scale).
@export_range(0.2, 4.0, 0.05) var flash_size: float = 1.35
@export_range(0.0, 8.0, 0.1) var flash_core_strength: float = 3.2
@export_range(0.0, 8.0, 0.1) var flash_ring_strength: float = 1.8
## The flash quad sits slightly toward the camera so the card cannot occlude it.
@export_range(0.0, 0.8, 0.01) var flash_offset: float = 0.20

var _running: bool = false
var _age: float = 0.0
var _model: Node3D = null
var _pieces: Array[Node3D] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _base_scales: Array[Vector3] = []
var _floor_local_y: float = -1000.0
var _glass_material: ShaderMaterial = null
var _flash: MeshInstance3D = null
var _flash_material: ShaderMaterial = null
var _flash_age: float = 0.0
var _flash_base_size: float = 1.0
var _destroy: Node3D = null


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
func burst_from_card(card: Card, inherited_velocity := Vector3.ZERO, inherited_spin := Vector3.ZERO) -> void:
	if card == null or not is_instance_valid(card) or not is_inside_tree():
		return
	var art: Material = null
	if card.mat != null:
		art = card.mat.duplicate()
		if art is ShaderMaterial:
			for prefix in ["shadow_", "shadow2_", "shadow3_", "shadow4_"]:
				art.set_shader_parameter(prefix + "strength", 0.0)
	if style == Style.DESTROY_BURST:
		# The mesh's own pose, not the Card's: HandMesh may be lifted/scaled relative to the Card.
		var face: MeshInstance3D = card.hand_mesh
		var pose: Transform3D = face.global_transform if face != null else card.global_transform
		burst_destroy(card.global_transform, pose, art, face.mesh if face != null else null, inherited_velocity,
			_crystal_tint(card))
		return
	burst(card.global_transform, art)
	var local_velocity := global_basis.inverse() * inherited_velocity
	var local_spin := global_basis.orthonormalized().inverse() * inherited_spin
	for i in range(_pieces.size()):
		_velocities[i] += local_velocity + local_spin.cross(_pieces[i].position)
		_spins[i] += local_spin


## The DESTROY_BURST look. `from` is where this node sits (the card), `face_pose` the card face mesh's pose.
func burst_destroy(from: Transform3D, face_pose: Transform3D, art_material: Material, face_mesh: Mesh,
		drift := Vector3.ZERO, tint: Color = DESTROY_BURST.DEFAULT_TINT) -> void:
	_clear()
	global_transform = from
	_running = true
	_age = 0.0
	_destroy = DESTROY_BURST.new()
	_destroy.name = "DestroyBurst"
	add_child(_destroy)
	_destroy.connect("finished", _finish)
	_destroy.call("setup", face_pose, art_material, face_mesh, randi(), drift, tint)
	# Nothing to move here: the burst runs itself and reports back.
	set_process(false)


## The shards are crystal of the card's ELEMENT (its live element, so an override counts): a Fire card breaks into
## ruby, Ice into pale blue. No element -> clear pale-blue crystal.
func _crystal_tint(card: Card) -> Color:
	var elements: Array[String] = card.current_elements()
	if elements.is_empty():
		return DESTROY_BURST.DEFAULT_TINT
	return Card.ELEMENT_COLOURS.get(elements[0], DESTROY_BURST.DEFAULT_TINT)


func burst(from: Transform3D, art_material: Material) -> void:
	_clear()
	# Rebuild from the current exports so Inspector changes apply to the NEXT
	# burst without reloading the preview scene.
	_make_glass_material()
	global_transform = from
	_running = true
	_age = 0.0
	_spawn_flash()
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

	set_process(true)


## A camera-facing additive quad. It grows and fades over flash_seconds while its
## shader draws the white core and the expanding shock ring.
func _spawn_flash() -> void:
	if not flash_enabled:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	_flash_material.set_shader_parameter("core_strength", flash_core_strength)
	_flash_material.set_shader_parameter("ring_strength", flash_ring_strength)
	_flash_material.set_shader_parameter("ring_radius", 0.22)
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = _flash_material
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader expands the quad beyond its mesh AABB.
	_flash.extra_cull_margin = 8.0
	add_child(_flash)
	var card_scale: float = maxf(global_transform.basis.get_scale().x, 0.0001)
	_flash_base_size = 0.60 * card_scale * flash_size
	_flash.scale = Vector3.ONE * _flash_base_size
	_flash_age = 0.0
	_update_flash_transform()


func _update_flash_transform() -> void:
	if _flash == null or not is_instance_valid(_flash):
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var pos: Vector3 = global_transform.origin + Vector3.UP * 0.04
	pos += cam.global_transform.basis.z.normalized() * flash_offset
	var size: float = _flash.scale.x
	_flash.global_transform = Transform3D(
		cam.global_transform.basis.scaled(Vector3.ONE * size), pos)


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
	if _flash != null and is_instance_valid(_flash):
		_flash_age += delta
		var flash_t: float = clampf(_flash_age / maxf(flash_seconds, 0.001), 0.0, 1.0)
		var grow: float = lerpf(0.85, 1.70, sqrt(flash_t))
		_flash.scale = Vector3.ONE * _flash_base_size * grow
		if _flash_material != null:
			_flash_material.set_shader_parameter("fade", pow(1.0 - flash_t, 2.0))
			_flash_material.set_shader_parameter("ring_radius", lerpf(0.22, 1.18, sqrt(flash_t)))
		_update_flash_transform()
		if flash_t >= 1.0:
			remove_child(_flash)
			_flash.queue_free()
			_flash = null
			_flash_material = null
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
			# DO NOT ZERO EVERYTHING ON CONTACT. A floor hit bounces a little,
			# keeps sliding, and loses spin/velocity through damping. That keeps
			# the fragments alive until they shrink away instead of stopping dead.
			if _velocities[i].y < -0.05:
				_velocities[i].y = -_velocities[i].y * floor_bounce
			else:
				_velocities[i].y = 0.0
			_velocities[i].x *= exp(-floor_friction * delta)
			_velocities[i].z *= exp(-floor_friction * delta)
			_spins[i] *= exp(-floor_spin_damping * delta)
			if settle_on_floor:
				var flat: Vector3 = Vector3(0.0, piece.rotation.y, 0.0)
				var settle_step: float = 1.0
				if settle_seconds > 0.0001:
					settle_step = clampf(delta / settle_seconds, 0.0, 1.0)
				piece.rotation = piece.rotation.lerp(flat, settle_step)
		piece.rotation += _spins[i] * delta
		var shrink: float = 1.0
		if shrink_enabled and lifetime > 0.0001:
			var shrink_start: float = lifetime * clampf(shrink_from, 0.0, 0.95)
			var shrink_t: float = clampf((_age - shrink_start) / maxf(lifetime - shrink_start, 0.001), 0.0, 1.0)
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
	if _model != null and is_instance_valid(_model):
		remove_child(_model)
		_model.queue_free()
	_model = null
	if _flash != null and is_instance_valid(_flash):
		remove_child(_flash)
		_flash.queue_free()
	_flash = null
	_flash_material = null
	if _destroy != null and is_instance_valid(_destroy):
		# No remove_child: _finish runs from inside the burst's own `finished` emission (its _process).
		if _destroy.is_connected("finished", _finish):
			_destroy.disconnect("finished", _finish)
		_destroy.queue_free()
	_destroy = null


func _finish() -> void:
	if not _running:
		return
	_clear()
	finished.emit()
	if free_when_done:
		queue_free()
