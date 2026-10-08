extends Node3D
class_name CrystalShards
## One shatter: the crystals' pieces fly apart for ONE SECOND, then vanish.
##
## SETUP IS EXPLICIT — `burst()` — AND NEVER `_ready()`.
##
## `_ready()` runs synchronously INSIDE `add_child()`, which is before the caller can hand this node anything that
## needs a parent. An earlier version did its setup there and got an identity transform: the scale came out as 1.0
## instead of 0.052, so the velocities stayed in a space nineteen times smaller than a metre and the whole burst
## travelled 8 mm. It looked like crystals that were not exploding. Setting everything up in an explicit call, after
## the node is in the tree, removes that whole class of mistake.
##
## THE PIECES ARE NEVER REPARENTED. The model is added as a CHILD of this node and its pieces are animated where they
## sit. This is the third time the same rule has bitten, so it is worth stating plainly:
##
##     A DETACHED NODE HAS NO MEANINGFUL GLOBAL TRANSFORM.
##
## The first version reparented each piece onto this node with `reparent(self, true)` — "keep the global transform".
## But the pieces' parent was the *instantiated model root, which had never been added to the tree*: its global
## transform is just its own, and the pieces' "globals" were therefore their model-local positions. Reparenting then
## divided the node's 0.052 scale back out, to preserve a global that did not mean anything — leaving every piece
## about 19x too large and flung well outside the crystal. Nothing was visible, and the engine had already warned
## about it ("will make owner ... inconsistent", once per piece, 36 times) while the code looked perfectly
## reasonable. Adding the model and leaving it alone sidesteps all of it.
##
## THE SCALE COMES IN AS AN ARGUMENT, never read back off the node, so the placing and the sizing can never disagree.
##
## The pieces are centred and their bounding box matches the crystal's exactly, so this node's transform puts
## crystal-sized pieces precisely onto the crystal. That transform carries the crystal's fit scale (about 0.052 —
## the model is ~4 units tall and drawn at 0.26 m), so a child's `position` is in units nineteen times smaller than
## a metre. `speed` and `gravity` are therefore in WORLD METRES PER SECOND and are divided by that scale once.
##
## THE TRIGGER is Assistant.on_charge_complete(): the mana is spent, the modal is closing, the card is being cast.
##
## USAGE:
##     var shards: Node3D = preload("res://scripts/crystal_shards.gd").new()
##     <any parent>.add_child(shards)
##     shards.burst(<the crystal mesh's global_transform>, <the crystal's colour>)

## The pieces, centred in Blender and matching the crystal's own bounds.
const SHARD_SCENE := preload("res://Blender/neo_crystal_shatter.glb")

## Launch speed in WORLD metres per second and the drag that stops it. A shard travels speed / drag metres in total
## and then stops, so the whole distance question is this one ratio: 0.9 / 9 is 10 cm, about a third of a 0.26 m
## crystal. Brief, and it settles rather than crossing the board.
@export var speed: float = 0.9
@export var drag: float = 9.0

## Downward acceleration in WORLD metres per second squared. Weight, not distance.
@export var gravity: float = 1.2

## Degrees per second of tumble, randomised per shard between the two. Rotation ignores the parent's scale, so these
## are already real numbers.
@export var spin_min: float = 120.0
@export var spin_max: float = 380.0

## The brief: one second, and gone. Shards hold their size for the first `shrink_from` of it, then shrink to nothing
## over the rest — so they vanish completely rather than popping out of existence.
@export var lifetime: float = 1.0
@export var shrink_from: float = 0.3

var _pieces: Array[MeshInstance3D] = []
## LOCAL units per second: the world-metre velocities already divided by this node's scale.
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _bases: Array[Vector3] = []
var _age: float = 0.0
var _scale: float = 1.0
var _running: bool = false

func _process(delta: float) -> void:
	# Nothing happens until burst() is called, including the ageing — otherwise a node that was made and never fired
	# would quietly delete itself.
	if not _running:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var decay: float = exp(-drag * delta)              # frame-rate independent, and scale-free
	var shrink_at: float = lifetime * shrink_from
	var shrink: float = 1.0
	if _age > shrink_at:
		shrink = 1.0 - (_age - shrink_at) / maxf(lifetime - shrink_at, 0.0001)
	var fall: float = (gravity / _scale) * delta
	for i in range(_pieces.size()):
		var piece: MeshInstance3D = _pieces[i]
		if piece == null or not is_instance_valid(piece):
			continue
		var v: Vector3 = _velocities[i]
		v *= decay
		v.y -= fall
		_velocities[i] = v
		# Positions are LOCAL to this node, which is why the velocities were divided by its scale when they were
		# built. The pieces keep their own local transform otherwise, which is what holds them in the crystal's shape.
		piece.position += v * delta
		# Spin about the piece's OWN origin: the Cell Fracture pieces each carry their origin at their own centre,
		# which is what makes this read as tumbling rather than as orbiting.
		piece.rotate(_spins[i].normalized(), deg_to_rad(_spins[i].length() * delta))
		piece.scale = _bases[i] * shrink

## Starts the burst. Call once, after this node is in the tree.
##
## `from` is the crystal mesh's global transform — the pieces are centred and share the crystal's bounds, so this
## both places and sizes them with no arithmetic. `colour` is the crystal's own colour: the crystal gets it from a
## shader override that a copy of the mesh does not inherit, so without it the shards arrive white.
func burst(from: Transform3D, colour: Color) -> void:
	if _running:
		return
	_running = true
	global_transform = from
	_scale = from.basis.get_scale().x
	if _scale < 0.0001:
		_scale = 1.0
	var source: Node = SHARD_SCENE.instantiate()
	# ADDED, NOT DISSECTED — see the class note. As a child of this node the pieces inherit this node's transform,
	# so they already sit exactly where the crystal was and at exactly its size. `source` stays as their parent (it
	# is freed with this node) and nothing cross-scene ever happens to them.
	add_child(source)
	var material: StandardMaterial3D = _build_material(colour)
	_collect(source, _pieces)
	for piece in _pieces:
		# Surface 0 only: surface 1 is the model's black edge geometry, left exactly as exported, so every shard
		# keeps the outline that made the crystal read as a crystal.
		piece.set_surface_override_material(0, material)
		# Outward from the centre, plus scatter so it does not read as a fan.
		var direction: Vector3 = piece.position.normalized()
		if direction.length_squared() < 0.0001:
			direction = Vector3.UP
		direction = (direction + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.35), randf_range(-0.3, 0.3))).normalized()
		# Divided by the scale ONCE, here, so everything in this file is in real metres.
		_velocities.append(direction * (speed / _scale) * randf_range(0.7, 1.15))
		_spins.append(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			* randf_range(spin_min, spin_max))
		_bases.append(piece.scale)

## One tinted body material, shared by every shard.
func _build_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = 0.3
	m.metallic_specular = 0.77
	m.roughness = 0.25
	# A little emission, off the same colour, so the pieces stay readable against the board for their one second.
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 0.55
	return m

## Every MeshInstance3D under `node`, in tree order.
func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_collect(child, out)
