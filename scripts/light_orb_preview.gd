extends Node3D
## Moves a LightOrb around so its trail can be seen — F6 on LightOrbPreview.tscn.
##
## A comet trail is made of particles left behind in world space, so a stationary orb shows a dot and nothing else. This
## orbits it, and teleports it once per lap so you can see teleport_to() clear the streak rather than draw one across
## the circle.
##
## IT BUILDS A FLOOR, and that is not decoration. The orb's OmniLight3D throws a pool of light onto whatever is beneath
## it, and with nothing to fall on, "this emits light" is invisible no matter how bright the orb is — the light lands
## nowhere. The floor sits well below the orb so it reads as a surface the orb is floating above, and it is mid-grey so
## the pool has something to brighten.

## The orb scene to spawn. Defaults to the one this preview ships with; set as a scene property so the preview can be
## pointed at a variant without editing code.
@export var orb_scene: PackedScene = null

## Orbit radius and speed, in metres and degrees per second.
@export var orbit_radius: float = 1.1
@export var orbit_speed: float = 150.0

## How far below the orbit the floor sits, in metres.
@export var floor_drop: float = 0.45

## Seconds between teleports. The orb jumps to the opposite side of the circle; without this the trail would draw one
## long streak straight through the middle, which is the bug teleport_to() exists to prevent.
@export var teleport_every_seconds: float = 2.6

var _orb: Node3D = null
var _angle: float = 0.0
var _since_teleport: float = 0.0

func _ready() -> void:
	_build_floor()
	if orb_scene == null:
		orb_scene = preload("res://light_orb.tscn")
	_orb = orb_scene.instantiate()
	add_child(_orb)
	_orb.position = Vector3(orbit_radius, 0.132, 0.0)

## A plain lit surface for the orb's light to land on.
func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	var floor_material := StandardMaterial3D.new()
	# Mid-grey and matte: the orb's light needs something with headroom to brighten, and a dark or glossy surface would
	# either swallow the pool or mirror the orb instead of showing it.
	floor_material.albedo_color = Color(0.34, 0.35, 0.38, 1.0)
	floor_material.roughness = 0.95
	floor_material.metallic = 0.0
	var mesh := MeshInstance3D.new()
	mesh.name = "Floor"
	mesh.mesh = plane
	mesh.material_override = floor_material
	mesh.position = Vector3(0.0, -floor_drop, 0.0)
	add_child(mesh)

func _process(delta: float) -> void:
	if _orb == null:
		return
	_angle = fmod(_angle + orbit_speed * delta, 360.0)
	_orb.position = Vector3(cos(deg_to_rad(_angle)), 0.132, sin(deg_to_rad(_angle))) * orbit_radius
	_since_teleport += delta
	if _since_teleport >= teleport_every_seconds:
		_since_teleport = 0.0
		# Half a lap away, which is far enough that an uncleared trail would be unmissable.
		_angle = fmod(_angle + 180.0, 360.0)
		_orb.position = Vector3(cos(deg_to_rad(_angle)), 0.132, sin(deg_to_rad(_angle))) * orbit_radius
		_orb.call("teleport_to", _orb.position)
