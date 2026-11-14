extends Node3D
class_name ManaCrystal
## One crystal in the mana payment row.
##
## TWO QUESTIONS, TWO COLOURS:
##   `element`       what this crystal is FOR. "1 fire and 3 any" is drawn as one fire crystal and three wild
##                   ones, so this is the element being ASKED for — a white crystal when it is wild.
##   `paid_element`  what PAID it. A WILD (white) crystal takes this colour while paid - a blue card discarded for
##                   2 CP turns two white crystals blue - and keeps it while it drains, so it fades out blue rather
##                   than flashing white. An elemental crystal keeps its own colour (only that element can pay it),
##                   and "any" (any-colour mana) has no colour of its own, so it stays white. See display_colour().
##
## OWED = AN EMPTY SOCKET, PAID = THE FILLED GEM. Three cues, chosen because "paid" used to be only a slightly
## brighter, faster version of "owed", which a still frame could not tell apart (a red crystal paid by red stayed red):
##   1. STATE: owed crystals are dark, matte and only faintly tinted (black edges kept); paid ones are the full
##      saturated, glowing gem.
##      `_fill` eases 0..1, so paying FILLS the crystal and taking the source back DRAINS it.
##   2. MOMENT: filling POPS it (scale 1 -> 1 + pop_scale -> 1) with a short white flash; the eye catches change.
##   3. MOTION: only paid crystals turn (idle speed 0), so movement itself means "paid". An owed crystal RESTS at
##      `rest_angle_deg` (30: a flat face front-on, the side faces symmetric; 0 puts a corner and a seam down the
##      middle). Unpaid again, it glides FORWARD onto the next rest pose rather than freezing mid-turn - see below.
## A crystal takes its state SILENTLY in the frame it is created (the row's rebuild, the colour picker's buttons), so
## nothing pops just for appearing.
##
## THE ANGLE IS ONLY EVER ADVANCED, from wherever it already is, so changing your mind about a mana source cannot
## make it jump. Settling onto the rest pose keeps that rule: the target is chosen ONCE, at the moment the crystal
## becomes unpaid (the next rest pose at least SETTLE_MIN_AHEAD degrees forward), and is never re-aimed, so it cannot
## flip mid-turn - which is exactly how an earlier "settle onto the nearest pose" lurched.
##
## That replaced a worse design, and the failure is worth recording because it looked like a rotation bug and was
## not. The first version had unpaid crystals come to rest and SETTLE onto the nearest symmetric pose, which meant
## writing the angle toward a target; as the angle crossed a 60-degree boundary mid-spin-down the target flipped to
## the next multiple and the crystal lurched. On top of that, the ROW was rebuilding its crystals on every payment
## change — destroying and reinstantiating them — so each new crystal began at angle 0 and the visual result was a
## crystal snapping from mid-spin to a completely different pose, which is precisely what was reported. Two causes,
## one symptom, and only one of them was in this file.
##
## No shell, no ring, no second mesh. Two approaches were tried and both are gone, and the reason is worth
## recording: the body shader already had an emissive term, so the simplest place to put a glow on an object is on
## the object.
##   * the cards' selection ring, a rounded RECTANGLE on a billboard quad, whose top edge kept landing inside the
##     faceted crystal — only the bottom and sides ever showed, because a rectangle is not the shape it outlines;
##   * a Fresnel shell, a copy of the mesh scaled 8% and lit additively, which its own runtime output proved was
##     built, visible, lit and correctly coloured — and which still drew nothing on screen.
##
## SURFACE 0 ONLY. The model (Blender/neo_crystal3.glb) has two surfaces: Material.001 is the body and
## Material.003 is the black edge and outline geometry, so the body shader is applied with
## set_surface_override_material(0, ...) and surface 1 keeps exactly the material it was exported with.

## The element being asked for: "" or "any" for wild, otherwise "fire".."dark" or the CJK key ("火").
@export var element: String = "":
	set(value):
		element = value
		_apply()

## The element that paid it ("water", "fire", ... or "any"; "" while owed). Colours a WILD crystal: display_colour().
@export var paid_element: String = "":
	set(value):
		paid_element = value
		if not value.is_empty():
			_last_payer = value
		_apply()

## False while the cost is still owed (empty, still). True once paid (filled, glowing, turning).
@export var lit: bool = false:
	set(value):
		var was: bool = lit
		lit = value
		if not _settled():
			# Created this frame: take the state, no animation.
			_fill = 1.0 if lit else 0.0
		elif lit and not was:
			_pop_age = 0.0
			_settle_to = -1.0
		elif was and not lit:
			# Chosen ONCE, forward of where it is now; never re-aimed.
			var ahead: float = _angle + SETTLE_MIN_AHEAD - rest_angle_deg
			_settle_to = fposmod(rest_angle_deg + SYMMETRY * ceilf(ahead / SYMMETRY), 360.0)
		_apply()

## How tall the crystal should stand, in metres, measured in THIS node's space. See _fit().
@export var height_m: float = 0.15:
	set(value):
		height_m = value
		_fit()

## SPIN SPEED once paid, in degrees per second. 150 is about two and a half turns a second — brisk, and still slow
## enough per frame (2.5 degrees at 60 fps) to read as spinning rather than strobing.
@export var spin_deg_per_sec: float = 150.0
## SPIN SPEED while the cost is still owed. ZERO since owed and paid were made distinct: only paid crystals move. That
## is safe because the angle is only ever advanced from where it is, so starting from rest cannot jump.
@export var idle_spin_deg_per_sec: float = 0.0
## Where an owed crystal rests, degrees. The hexagonal model repeats every 60, so this is 30 + any multiple of 60.
@export var rest_angle_deg: float = 30.0
## How long the change between the two speeds takes. Small on purpose — selecting a source should feel immediate —
## but ramped rather than slammed, so there is no visible jerk at the moment of the click.
@export var spin_up_seconds: float = 0.10

## THE GLOW. Emission is added on top of an already-lit surface, so pushing this too far clips a bright colour's
## channels and turns it white — the ice crystal did exactly that at 1.7 and stopped being cyan. 0.9 keeps every
## element recognisable while still reading as lit.
@export var glow_energy: float = 0.9
## How much the glow breathes, and how fast. The pulse is what makes it read as alive rather than as a tint.
@export var glow_pulse: float = 0.22
@export var glow_pulse_speed: float = 2.1
## How long filling (or draining) takes, seconds.
@export var fill_seconds: float = 0.14
## The pop when it fills: extra scale at the peak, how long it lasts, and how long the white flash lasts.
@export var pop_scale: float = 0.22
@export var pop_seconds: float = 0.24
@export var flash_seconds: float = 0.16

const SHADER := preload("res://shaders/mana_crystal.gdshader")
const ELEMENTS := preload("res://scripts/core/elements.gd")
const WILD_COLOUR := Color(0.94, 0.95, 1.0)

## The crystal BODY colours, in ELEMENTS.NAMES order. Seven of them are the badge accents, which are already
## tuned per element, so the two displays cannot drift apart. FIRE is deliberately not: the badge accent for fire is
## (1.0, 0.38, 0.18), an orange at hue 12 degrees — right for a thin ring on a dark disc, and wrong for a crystal
## body, which wants the ruby that references/crystal.png shows.
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

## Measured in _fit() IN THIS NODE'S SPACE, and used by the row for spacing. Measuring beats assuming: "half the
## height" was true of the first crystal model and wrong for the second, which fused the whole row into one
## silhouette.
var _slot_width: float = 0.0
var _material: ShaderMaterial = null
var _spin_node: MeshInstance3D = null
## Degrees, kept wrapped to [0, 360). The single source of truth for where the crystal is pointing, and only ever
## advanced — see _process().
var _angle: float = 0.0
## Degrees per second, eased toward whichever of the two target speeds applies.
var _spin_speed: float = 0.0
## 0 owed .. 1 paid, as drawn (eased toward `lit`).
var _fill: float = 0.0
## Seconds since the last fill started its pop; < 0 when no pop is playing.
var _pop_age: float = -1.0
## The frame this crystal entered the tree: a state set in that frame is taken without animation.
var _born_frame: int = -1
## The last element that paid this crystal; kept while it drains so a wild crystal fades out in that colour.
var _last_payer: String = ""
## The rest pose an unpaid crystal is gliding onto (degrees, wrapped), or < 0 when it is not settling.
var _settle_to: float = -1.0
## Settling: a rest pose is only ever chosen at least this far ahead; speed eases down with the distance left
## (SETTLE_GAIN per second) but never below SETTLE_MIN_SPEED, so it arrives rather than crawling.
const SETTLE_MIN_AHEAD := 20.0
const SETTLE_GAIN := 5.0
const SETTLE_MIN_SPEED := 25.0
const SYMMETRY := 60.0

func _ready() -> void:
	_born_frame = Engine.get_process_frames()
	_angle = fposmod(rest_angle_deg, 360.0)
	_fill = 1.0 if lit else 0.0
	_fit()
	_apply()

func _settled() -> bool:
	return is_inside_tree() and _born_frame >= 0 and Engine.get_process_frames() > _born_frame

func _process(delta: float) -> void:
	_animate_fill(delta)
	if _spin_node == null:
		return
	if not lit and _settle_to >= 0.0:
		# GLIDING ONTO THE REST POSE, forward only: slow down with the distance left, and land exactly.
		var left: float = fposmod(_settle_to - _angle, 360.0)
		_spin_speed = minf(_spin_speed, maxf(left * SETTLE_GAIN, SETTLE_MIN_SPEED))
		var step: float = _spin_speed * delta
		if step >= left:
			_angle = _settle_to
			_settle_to = -1.0
			_spin_speed = 0.0
		else:
			_angle = fposmod(_angle + step, 360.0)
		_spin_node.rotation.y = deg_to_rad(_angle)
		return
	var target: float = spin_deg_per_sec if lit else idle_spin_deg_per_sec
	var rate: float = (spin_deg_per_sec / maxf(spin_up_seconds, 0.01)) * delta
	_spin_speed = move_toward(_spin_speed, target, rate)
	# Advance, always. Nothing here can assign an angle, so no state change can move the crystal anywhere except
	# by turning it. Wrapped so a long payment cannot accumulate float error.
	_angle = fposmod(_angle + _spin_speed * delta, 360.0)
	_spin_node.rotation.y = deg_to_rad(_angle)

## Fill/drain and the pop. Writes the shader only while something is changing.
func _animate_fill(delta: float) -> void:
	var target: float = 1.0 if lit else 0.0
	var changed: bool = false
	if not is_equal_approx(_fill, target):
		_fill = move_toward(_fill, target, delta / maxf(fill_seconds, 0.01))
		changed = true
	var flash: float = 0.0
	if _pop_age >= 0.0:
		_pop_age += delta
		var k: float = clampf(_pop_age / maxf(pop_seconds, 0.01), 0.0, 1.0)
		scale = Vector3.ONE * (1.0 + pop_scale * sin(PI * k))
		flash = 1.0 - clampf(_pop_age / maxf(flash_seconds, 0.01), 0.0, 1.0)
		if k >= 1.0:
			_pop_age = -1.0
			scale = Vector3.ONE
		changed = true
	if changed and _material != null:
		_material.set_shader_parameter("paid", _fill)
		_material.set_shader_parameter("flash", flash)
		# A drained wild crystal goes back to white only once it is EMPTY (display_colour reads _fill).
		_material.set_shader_parameter("tint", display_colour())

## Probe hooks: the drawn fill (0 owed .. 1 paid) and whether a pop is playing.
func fill_amount() -> float:
	return _fill

func is_popping() -> bool:
	return _pop_age >= 0.0

## Place the crystal at a specific orientation. The picker uses this to start its buttons at 60 degrees; the
## payment row keeps advancing from wherever it already is.
func set_spin_angle(degrees: float) -> void:
	_angle = fposmod(degrees, 360.0)
	if _spin_node != null:
		_spin_node.rotation.y = deg_to_rad(_angle)


func spin_angle_degrees() -> float:
	return _angle

## True when this crystal has no element of its own — a wild "any colour" slot, drawn white.
func is_wild() -> bool:
	return element_index(element) < 0

## The colour ON SCREEN: the paying element's for a wild crystal that is paid (or still draining), otherwise the
## colour asked for. The shader tint and the shatter shards both use it.
func display_colour() -> Color:
	if is_wild() and (lit or _fill > 0.0):
		var idx: int = element_index(_last_payer if paid_element.is_empty() else paid_element)
		if idx >= 0:
			return CRYSTAL_TINT[idx]
	return colour_now()

## The colour the crystal ASKS for (white for wild), whatever paid it. display_colour() is what is drawn.
func colour_now() -> Color:
	var idx: int = element_index(element)
	return WILD_COLOUR if idx < 0 else CRYSTAL_TINT[idx]

## Index into the element palette, or -1 for wild / an unknown key.
func element_index(key: String) -> int:
	var k: String = key.strip_edges()
	if k.is_empty() or k.to_lower() == "any" or k.to_lower() == "neutral":
		return -1
	var i: int = ELEMENTS.NAMES.find(k.to_lower())
	if i >= 0:
		return i
	return ELEMENTS.CJK.find(k)

## Sizes the model so it really stands `height_m` tall IN THIS NODE'S SPACE, lifts its base to y = 0, and measures
## what it occupies.
##
## IT ITERATES, and that is the fix for a real bug rather than defensive padding. The obvious version —
## `mi.scale = height_m / aabb.y` — is only right when nothing between this node and the mesh rotates or scales it.
## This mesh sits inside an imported glb, whose nodes carry transforms of their own, and a rotation in that chain
## makes a single correction land on the wrong axis: the model then renders at a fraction of the size asked for,
## while everything computed from `height_m` assumes the full size. That is exactly what was happening — a crystal
## asked for 0.26 m was drawing at about 0.11 m — and it was found by printing one number, not by reasoning.
##
## Re-measuring and correcting again converges whatever the chain is doing, and costs one AABB lookup per pass. If
## it ever fails to converge, that is a loud warning rather than a silently wrong size.
func _fit() -> void:
	if not is_inside_tree():
		return
	var mi: MeshInstance3D = _mesh_instance()
	if mi == null or mi.mesh == null:
		return
	for _pass in range(4):
		var now: AABB = _bounds_here(mi)
		if absf(now.size.y - height_m) <= height_m * 0.005:
			break
		mi.scale *= height_m / maxf(now.size.y, 0.0001)
	var final: AABB = _bounds_here(mi)
	if absf(final.size.y - height_m) > height_m * 0.05:
		push_warning("[ManaCrystal] could not size the model to %.3f m (got %.3f m) — something between this node and the mesh is fighting the scale" % [height_m, final.size.y])
	# Stand it on this node's origin.
	mi.position += Vector3(0.0, -_bounds_here(mi).position.y, 0.0)
	var here: AABB = _bounds_here(mi)
	_slot_width = here.size.x
	# The node that turns is the MESH, not this one: the row keeps this node camera-aligned.
	_spin_node = mi

## The mesh's bounds expressed in THIS node's space, including any transforms on the nodes between the two.
func _bounds_here(mi: MeshInstance3D) -> AABB:
	var world_box: AABB = mi.global_transform * mi.mesh.get_aabb()
	return global_transform.affine_inverse() * world_box

## How much horizontal room this crystal takes, in metres, measured rather than derived.
func slot_width_m() -> float:
	return _slot_width

## Applies the body shader to SURFACE 0 only, and sets how the crystal looks right now.
## Bursts this crystal into shards around its current pose, and hides it.
##
## The shards take the MESH's whole transform — fit scale, spin and all — so they assemble exactly where the crystal
## was, with no arithmetic. See CrystalShards for why the burst is deliberately weak.
##
## The crystal is HIDDEN rather than freed: the row owns its lifetime and takes it down with everything else when
## the payment modal closes, which happens the same frame.
func shatter(world_parent: Node) -> void:
	if world_parent == null or _spin_node == null:
		return
	var shards: Node3D = preload("res://scripts/vfx/crystal_shards.gd").new()
	# ADD FIRST: `burst()` takes the crystal's GLOBAL transform, and that needs a parent to be global to.
	#
	# Everything else — placing, sizing, the tint, the velocities — happens inside that one call, deliberately not
	# in `_ready()`, which runs inside this `add_child()` and would therefore see an identity transform and no colour.
	# The pieces are centred and share the crystal's bounds, so handing over this transform both places and sizes them.
	world_parent.add_child(shards)
	shards.call("burst", _spin_node.global_transform, display_colour())
	_spin_node.visible = false

## Surface 1 is the model's black edge geometry and is deliberately left alone — overriding the whole material
## rather than one surface would wipe those edges out.
func _apply() -> void:
	if not is_inside_tree():
		return
	var mi: MeshInstance3D = _mesh_instance()
	if mi == null:
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		# Desynchronise the breathing across the row, so a set of paid crystals does not pulse in lockstep.
		_material.set_shader_parameter("phase_offset", randf() * TAU)
		mi.set_surface_override_material(0, _material)
	_material.set_shader_parameter("tint", display_colour())
	# 0 owed .. 1 paid, as currently drawn (eased in _animate_fill); everything the look does keys off it.
	_material.set_shader_parameter("paid", _fill)
	_material.set_shader_parameter("emission_energy", glow_energy)
	_material.set_shader_parameter("pulse", glow_pulse)
	_material.set_shader_parameter("pulse_speed", glow_pulse_speed)


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
