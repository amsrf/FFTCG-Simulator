extends MeshInstance3D
## THE SHADOW A FIELD CARD CASTS ON THE WOOD. Field cards rest on the slab, but with the scene light's shadows off
## nothing tied them to it: they read as pasted on. This is a soft dark rounded rectangle lying ON
## the wood straight under the card (offset by FALL, see there), following the card's x/z and yaw every frame
## (taps, attacks, party moves, the slam's drop), so it needs no hooks into any of them.
##
## It is a child of the Card, so it inherits the card's visibility (a hidden card / clash stand-in casts nothing),
## but `top_level`, so its height stays on the wood whatever the card does. HEIGHT IS READ FROM THE SHADOW: above its
## resting height (the clash lift, the slam drop) it slides away along LIGHT_FALL and gets a little lighter and softer,
## like a low light over the table (Artifact's clash, ~/Desktop/Clips/damage 633-656: hard dark shadows landing far
## from a lifted card). A leaning card casts a shorter shadow (its long axis projected on the wood). Reuses the damage reaction's
## shader (card_lift_shadow.gdshader); `Card.enter_zone()` is the single switch (`set_active`).

const SHADER := preload("res://shaders/card_lift_shadow.gdshader")
## The slab top (field_drop_zone.gd SLAB_TOP_Y), plus a lift so the quad never z-fights the wood.
const WOOD_Y := 0.065 + 0.004
const STRENGTH := 0.6
const SOFTNESS := 0.022
## Lighter and softer per metre ABOVE the card's resting height. Kept small: a lifted card's shadow stays dark, and
## the DISTANCE (LIGHT_FALL) is what tells the height.
const FADE_PER_METRE := 0.2
const SPREAD_PER_METRE := 0.02
## How far the shadow slides away per metre above rest, and which way (world x, z): toward the camera (-z) and to
## screen-LEFT (+x: the board camera looks down +z, so its right is -x), i.e. down-left on screen, as in the clip.
## Both seats share it: one light over the table.
const LIGHT_FALL := Vector2(0.45, -0.89)
const OFFSET_PER_METRE := 0.25
## Resting height of a field card's face over the wood: row markers at Field-local y 0.0846 (x 1.005), minus WOOD_Y.
const REST_HEIGHT := 0.016
const MARGIN := 0.16
## Where the shadow falls, in WORLD metres on the wood: toward the camera (-z) and a little right, so it shows below
## the card on screen (Artifact's board does the same). Straight down, the card hid it completely. Fixed in the
## world, so both seats' cards cast the same way, like one light over the table.
const FALL := Vector2(0.01, -0.03)

var _card: Node3D = null
## The card transform the shadow was last placed for: an unmoved card (almost always) costs one comparison a frame.
var _placed_for := Transform3D()
var _placed := false
var _material: ShaderMaterial = null
var active := false

func setup(card: Node3D, face: Vector2) -> void:
	_card = card
	name = "FieldShadow"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# The board is drawn in the transparent pass; without this, distance sorting draws the wood over the shadow.
	_material.render_priority = 1
	_material.set_shader_parameter("card_size", face)
	_material.set_shader_parameter("margin", MARGIN)
	_material.set_shader_parameter("softness", SOFTNESS)
	_material.set_shader_parameter("strength", 0.0)
	material_override = _material
	var plane := PlaneMesh.new()
	plane.size = face + Vector2.ONE * (2.0 * MARGIN)
	mesh = plane
	visible = false
	# Its OWN process mode: the clash proxies are PROCESS_MODE_DISABLED, and inheriting that froze the shadow on the
	# slot as a black slab while the card flew off.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

## TWO HOOKS. `_process` keeps it right wherever nothing is drawn (headless probes). `frame_pre_draw` fixes the DRAWN
## frame: tweens move the card after every node's `_process`, so a `_process`-only shadow was drawn a frame behind
## (2-3 frames off during the clash's 2-frame charge). An unmoved card costs one comparison per hook.
func set_active(value: bool) -> void:
	active = value
	visible = value
	_placed = false
	set_process(value)
	var hooked: bool = RenderingServer.frame_pre_draw.is_connected(_follow)
	if value and not hooked:
		RenderingServer.frame_pre_draw.connect(_follow)
	elif not value and hooked:
		RenderingServer.frame_pre_draw.disconnect(_follow)
	if value:
		_follow()

func _process(_delta: float) -> void:
	_follow()

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_follow):
		RenderingServer.frame_pre_draw.disconnect(_follow)

func _enter_tree() -> void:
	if active and not RenderingServer.frame_pre_draw.is_connected(_follow):
		RenderingServer.frame_pre_draw.connect(_follow)

func _follow() -> void:
	if _card == null or not is_instance_valid(_card) or not _card.is_inside_tree():
		return
	var card_xf: Transform3D = _card.global_transform
	if _placed and card_xf.is_equal_approx(_placed_for):
		return
	_placed_for = card_xf
	_placed = true
	var height: float = card_xf.origin.y - WOOD_Y
	var above: float = maxf(0.0, height - REST_HEIGHT)
	# Only the card's YAW and size: the shadow lies flat whatever tilt the card has.
	var basis_scale: Vector3 = card_xf.basis.get_scale()
	var forward: Vector3 = card_xf.basis.z
	forward.y = 0.0
	var yaw_basis := Basis.IDENTITY
	if forward.length_squared() > 1e-8:
		yaw_basis = Basis.looking_at(-forward.normalized(), Vector3.UP)
	var s: float = basis_scale.x
	# A leaning card's long axis lands shorter on the wood: cos of its pitch, from its own long axis.
	var long_axis: Vector3 = card_xf.basis.z
	var reach: float = 1.0
	if long_axis.length_squared() > 1e-8:
		reach = clampf(Vector2(long_axis.x, long_axis.z).length() / long_axis.length(), 0.2, 1.0)
	var shaped := Basis(yaw_basis.x * s, yaw_basis.y, yaw_basis.z * s * reach)
	var fall: Vector2 = FALL + LIGHT_FALL * above * OFFSET_PER_METRE
	var placed := Transform3D(shaped, Vector3(card_xf.origin.x + fall.x, WOOD_Y, card_xf.origin.z + fall.y))
	global_transform = placed
	# A node's transform reaches the renderer at the scene tree's transform flush, which has already run by
	# frame_pre_draw: without this the shadow is drawn where the card was LAST frame.
	if is_inside_tree():
		RenderingServer.instance_set_transform(get_instance(), placed)
	_material.set_shader_parameter("strength", STRENGTH / (1.0 + above * FADE_PER_METRE))
	_material.set_shader_parameter("softness", minf(MARGIN, SOFTNESS + above * SPREAD_PER_METRE))

## Probe hook.
func strength() -> float:
	if not active or _material == null:
		return 0.0
	var v = _material.get_shader_parameter("strength")
	return float(v) if v is float else 0.0
