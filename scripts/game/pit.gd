extends Node3D
## A PIT: how the Break Zone and the Removed pile are DRAWN (after Master Duel's graveyard / banish pits,
## ~/Desktop/Clips/pits frame 62). A low dark drum set on the wood, its top a dark well ringed by three neon rings -
## blue for the Break Zone, purple for cards removed from the game.
##
## Presentation only. The pile (scripts/game/graveyard.gd) still owns the rules list; it builds one of these as its
## child and hides the cards it holds, because a card in a pit has gone INTO it. Clicking the pit opens the pile's
## zone view, since there is no card left on top to click.
##
## Everything here is in METRES: the pile node is scaled (1.4), so this node cancels its parent's scale.

const TOP_SHADER := preload("res://shaders/pit_top.gdshader")
const FLARE_SHADER := preload("res://shaders/pit_flare.gdshader")

const COLOURS := {
	"graveyard": {"ring": Color(0.10, 0.30, 1.0), "flare": Color(0.22, 0.78, 1.0)},
	"removed": {"ring": Color(0.75, 0.10, 0.95), "flare": Color(0.95, 0.35, 1.0)},
}

## Default outer radius and drum height, in metres (a card on the board is 0.429 x 0.6). The pile passes its own
## radius (Graveyard.pit_radius): the Removed pit is smaller than the Break Zone one, as in Master Duel.
const RADIUS := 0.21
## The pit's top sits just BELOW the stone housing baked into the board (Blender/build_pit_housing.py, top 0.115 in
## world; the pile is at 0.07), so it reads as set into the stone, inside the housing's metal ring.
const HEIGHT := 0.035
## The flare rides above the housing and its ring, or the stone would hide the crescents that spill past the rim.
const FLARE_LIFT := 0.075
const FLARE_SECONDS := 0.75
## The flare quad's half-size, as a multiple of RADIUS (room for the crescents to spill past the rim).
const FLARE_EXTENT := 1.4
const FLARE_PRIORITY := 20

signal clicked

var kind := "graveyard"
var radius := RADIUS
var _top_mat: ShaderMaterial
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial
var _flare_tween: Tween
var _pulse_tween: Tween
## Probe hook: how many flares have started.
var flare_count := 0


## `removed` picks the purple pit. Call once, after the node is in the tree (it reads its parent's scale).
func setup(removed: bool, pit_radius: float = RADIUS) -> void:
	kind = "removed" if removed else "graveyard"
	radius = pit_radius
	var parent_scale: float = 1.0
	var parent := get_parent() as Node3D
	if parent != null:
		parent_scale = maxf(parent.global_transform.basis.get_scale().x, 0.0001)
	scale = Vector3.ONE / parent_scale
	_build()


func top_y() -> float:
	return global_position.y + HEIGHT


func _build() -> void:
	var colours: Dictionary = COLOURS[kind]
	var drum := MeshInstance3D.new()
	drum.name = "Drum"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 1.05
	cylinder.height = HEIGHT
	cylinder.radial_segments = 64
	cylinder.rings = 1
	drum.mesh = cylinder
	var side := StandardMaterial3D.new()
	side.albedo_color = Color(0.09, 0.10, 0.13)
	side.roughness = 0.55
	side.metallic = 0.3
	drum.material_override = side
	drum.position.y = HEIGHT * 0.5
	add_child(drum)

	var top := MeshInstance3D.new()
	top.name = "Top"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	top.mesh = plane
	_top_mat = ShaderMaterial.new()
	_top_mat.shader = TOP_SHADER
	_top_mat.set_shader_parameter("ring_color", colours["ring"])
	top.material_override = _top_mat
	top.position.y = HEIGHT + 0.0008
	add_child(top)

	_flare = MeshInstance3D.new()
	_flare.name = "Flare"
	var flare_plane := PlaneMesh.new()
	flare_plane.size = Vector2.ONE * radius * 2.0 * FLARE_EXTENT
	_flare.mesh = flare_plane
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = FLARE_SHADER
	_flare_mat.render_priority = FLARE_PRIORITY
	_flare_mat.set_shader_parameter("flare_color", colours["flare"])
	_flare_mat.set_shader_parameter("pit_radius", 1.0 / FLARE_EXTENT)
	_flare.material_override = _flare_mat
	_flare.position.y = HEIGHT + FLARE_LIFT
	_flare.visible = false
	add_child(_flare)

	# CLICK TARGET: the whole drum. A card in a pit is hidden, so this is the only thing left to click.
	var area := Area3D.new()
	area.name = "PitArea"
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = HEIGHT * 2.0
	shape.shape = cyl_shape
	shape.position.y = HEIGHT * 0.5
	area.add_child(shape)
	area.input_event.connect(_on_input_event)
	add_child(area)


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		clicked.emit()


## A card has gone in: crescents whirl round the rim and fade, and the rings flash. Fire-and-forget; it never holds
## the presentation queue.
func flare() -> void:
	if _flare == null:
		return
	flare_count += 1
	if _flare_tween != null and _flare_tween.is_valid():
		_flare_tween.kill()
	_flare.visible = true
	_flare_mat.set_shader_parameter("seed", randf())
	_flare_tween = create_tween()
	_flare_tween.tween_method(func(v: float) -> void: _flare_mat.set_shader_parameter("t", v),
		0.0, 1.0, FLARE_SECONDS)
	_flare_tween.tween_callback(func() -> void: _flare.visible = false)
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(func(v: float) -> void: _top_mat.set_shader_parameter("pulse", v),
		1.0, 0.0, FLARE_SECONDS)

