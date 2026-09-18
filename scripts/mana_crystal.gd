extends Node3D
class_name ManaCrystal
## One crystal in the mana payment row.
##
## TWO QUESTIONS, TWO COLOURS:
##   `element`       what this crystal is FOR. "1 fire and 3 any" is drawn as one fire crystal and three wild
##                   ones, so this is the element being ASKED for — a white crystal when it is wild.
##   `paid_element`  what actually PAID it, and therefore what it shines in. A white crystal paid by a red source
##                   turns red and lights up: the display is about the payment, not the requirement. Only wild
##                   crystals ever change colour, since an elemental cost can only be paid by its own element.
##
## SURFACE 0 ONLY. The model (Blender/neo_crystal3.glb) carries two surfaces: Material.001 is the body and
## Material.003 is the black edge and outline geometry. The shader here is applied with
## set_surface_override_material(0, ...), so surface 1 keeps exactly the material it was exported with — the edges
## are the model's job, not ours.
##
## As a result there is NO mesh rebuilding here: no flat-normal copy, no inverted hull, no edge detection. That
## machinery existed only because the outline had to be faked in Godot.

## The element being asked for: "" or "any" for wild, otherwise "fire".."dark" or the CJK key ("火").
@export var element: String = "":
	set(value):
		element = value
		_apply()

## The element that paid it. Empty means a wild crystal paid it, so it shines white.
@export var paid_element: String = "":
	set(value):
		paid_element = value
		_apply()

## False while the cost is still owed, true once paid. Paid means a glow in the colour it ended up.
@export var lit: bool = false:
	set(value):
		lit = value
		_apply()

## How tall the crystal stands, in metres. The model is 3.79 units tall, so the scale is derived from this.
@export var height_m: float = 0.15:
	set(value):
		height_m = value
		_fit()

## Degrees per second about the vertical axis. A slow turntable, not a tumbling rock.
@export var spin_deg_per_sec: float = 18.0

const SHADER := preload("res://shaders/mana_crystal.gdshader")
const WILD_COLOUR := Color(0.94, 0.95, 1.0)

## The crystal BODY colours, in ElementBadge.ELEMENTS order. Seven of them are the badge accents, which are
## already tuned per element, so the two displays cannot drift apart. FIRE is deliberately not: the badge accent
## for fire is (1.0, 0.38, 0.18), an orange at hue 12 degrees — right for a thin ring on a dark disc, and wrong
## for a crystal body, which wants the ruby that references/crystal.png shows.
const CRYSTAL_TINT: Array[Color] = [
	Color(0.86, 0.09, 0.17),   # fire — a ruby, NOT the badge's orange
	Color(0.55, 0.87, 0.98),   # ice
	Color(0.36, 0.85, 0.44),   # wind
	Color(0.90, 0.74, 0.26),   # earth
	Color(0.72, 0.45, 1.00),   # lightning
	Color(0.32, 0.58, 1.00),   # water
	Color(1.00, 0.95, 0.78),   # light
	Color(0.58, 0.52, 0.86),   # dark
]

## Set by _fit() from the model's own bounds, and returned by slot_width_m(). Declared beside its accessor rather
## than with the other state vars, because the two belong together — and because an undeclared variable here is
## not a small mistake: the file fails to parse, the script never loads, and every crystal silently degrades to a
## plain Node3D.
var _slot_width: float = 0.0
var _material: ShaderMaterial = null

func _ready() -> void:
	_fit()
	_apply()

func _process(delta: float) -> void:
	if spin_deg_per_sec != 0.0:
		rotate_y(deg_to_rad(spin_deg_per_sec * delta))

## True when this crystal has no element of its own — a wild "any colour" slot, drawn white.
func is_wild() -> bool:
	return element_index(element) < 0

## The colour it is RIGHT NOW: the paying element while lit, the required one while not. White stands for wild at
## both ends — an unpaid wild slot, and one paid by a wild source.
func colour_now() -> Color:
	var idx: int = element_index(paid_element if lit else element)
	return WILD_COLOUR if idx < 0 else CRYSTAL_TINT[idx]

## Index into the element palette, or -1 for wild / an unknown key.
func element_index(key: String) -> int:
	var k: String = key.strip_edges()
	if k.is_empty() or k.to_lower() == "any" or k.to_lower() == "neutral":
		return -1
	var i: int = ElementBadge.ELEMENTS.find(k.to_lower())
	if i >= 0:
		return i
	return ElementBadge.CJK.find(k)

## Scales the model to `height_m` and stands it on this node's origin, and records the scaled width so the row can
## space crystals by what they actually occupy. Measured from the model's own bounds rather than hardcoded, so
## swapping the model cannot silently break either the size or the spacing — and this scene has been swapped
## three times.
func _fit() -> void:
	if not is_inside_tree():
		return
	var mi: MeshInstance3D = _mesh_instance()
	if mi == null or mi.mesh == null:
		return
	var box: AABB = mi.mesh.get_aabb()
	var k: float = height_m / maxf(box.size.y, 0.0001)
	mi.scale = Vector3.ONE * k
	# The model may not be centred on its own origin; lift it so its base sits at y = 0.
	mi.position = Vector3(0.0, -box.position.y * k, 0.0)
	_slot_width = box.size.x * k

## How much horizontal room this crystal takes, in metres, derived from the model's own bounds. The row asks for
## this rather than guessing from the height, because "half the height" was only true of the first model.
func slot_width_m() -> float:
	return _slot_width

## Applies the body shader to SURFACE 0 only. Surface 1 is the model's black edge geometry and is deliberately left
## alone — overriding the whole material rather than one surface would wipe those edges out.
func _apply() -> void:
	if not is_inside_tree():
		return
	var mi: MeshInstance3D = _mesh_instance()
	if mi == null:
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		# Desynchronise the paid breathing across the row, so a set of paid crystals does not pulse in lockstep.
		_material.set_shader_parameter("phase_offset", randf() * TAU)
		mi.set_surface_override_material(0, _material)
	_material.set_shader_parameter("tint", colour_now())
	_material.set_shader_parameter("paid", 1.0 if lit else 0.0)

## The model's mesh node, whatever the file it came from called it. Searched for rather than named, because this
## scene has swapped between an .obj and two .glbs, and they nest their mesh differently.
func _mesh_instance() -> MeshInstance3D:
	for child in get_children():
		var found: MeshInstance3D = _mesh_below(child)
		if found != null:
			return found
	return null

func _mesh_below(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found: MeshInstance3D = _mesh_below(child)
		if found != null:
			return found
	return null
