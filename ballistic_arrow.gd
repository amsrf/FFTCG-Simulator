extends Node3D

# Exported parameters for easy tuning in the editor
@export var max_height: float = 1.0
@export var sphere_count: int = 20
@export var sphere_radius: float = 0.025
@export var sphere_material: StandardMaterial3D
@export var min_distance: float = 1.0  # Minimum distance to show arc
@export var arc_color: Color = Color(1, 0.5, 0, 1)  # Orange color
@export var is_aiming =  false
var start_pos
var arrow
@onready var camera = get_node("/root/Game/Camera3D")

# Internal variables
var spheres: Array[MeshInstance3D] = []
var is_active: bool = false

func _process(delta):
	if is_aiming:  # Your aiming condition
		
		var target_pos = get_mouse_target_position() 
		set_target_position(start_pos, target_pos)
	else:
		hide_arc()

func get_mouse_target_position() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	
	# Define your game board plane (adjust these values to match your board)
	var plane_origin = Vector3(0, 0, 0)  # Point on the plane
	var plane_normal = Vector3(0, 1, 0)   # Normal vector (up for horizontal board)
	
	# Create a plane for intersection
	var plane = Plane(plane_normal, plane_origin.dot(plane_normal))
	
	# Get mouse ray
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	
	# Find intersection with plane
	var intersection = plane.intersects_ray(from, dir)
	
	if intersection:
		return intersection
	else:
		# Fallback: project onto plane using camera distance
		var distance_to_plane = 10.0  # Default distance if no intersection
		var point_on_plane = from + dir * distance_to_plane
		return plane.project(point_on_plane)

func _ready():
	# Initialize all spheres upfront for better performance
	create_sphere_pool()
	hide_arc()  # Start hidden
	
	# Set material properties
	if sphere_material == null:
		sphere_material = StandardMaterial3D.new()
	sphere_material.albedo_color = arc_color

func create_sphere_pool():
	# Create shared material
	var material = StandardMaterial3D.new()
	material.albedo_color = arc_color
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED  # For bright colors
	material.flags_no_depth_test = true  # Make visible through objects
	
	# Create all spheres with the shared material
	for i in range(sphere_count):
		var sphere = MeshInstance3D.new()
		sphere.mesh = SphereMesh.new()
		sphere.mesh.radius = sphere_radius
		sphere.mesh.height = sphere_radius * 2
		sphere.mesh.material = material  # Assign the shared material
		add_child(sphere)
		spheres.append(sphere)
		sphere.visible = false


func update_arc(start: Vector3, end: Vector3):
	var distance = start.distance_to(end)
	
	if distance < min_distance:
		hide_arc()
		return
	
	show_arc()
	
	var horizontal_vec = end - start
	var direction = horizontal_vec.normalized()
	
	# Calculate dynamic height based on distance (optional)
	var dynamic_height = min(max_height, distance * 0.5)
	
	for i in range(sphere_count):
		var t = float(i) / float(sphere_count - 1)
		var base_pos = start.lerp(end, t)
		
		# Calculate vertical offset (unchanged)
		var vertical_offset = 4 * dynamic_height * t * (1 - t)
		
		var lateral_offset = sin(t * PI)  * 1.4
		
		# Apply offsets
		spheres[i].position = (
			base_pos + 
			Vector3.UP * vertical_offset + 
			Vector3.RIGHT * lateral_offset  # Tilt along world X-axis
		)
		spheres[i].visible = true
		
	
	# Point the pyramid's UP direction toward the target
	#var dir = (end - arrow.global_position).normalized()
	#print(dir, 'oskaposka')
	
	#arrow.point_y_axis_to(end)

	# Now rotate -90° around X-axis to make +Y (tip) point where -Z was pointing
	#arrow.rotate_object_local(Vector3.RIGHT, -PI/2)


func show_arc():
	if !is_active:
		is_active = true
		for sphere in spheres:
			sphere.visible = true

func hide_arc():
	if is_active:
		is_active = false
		for sphere in spheres:
			sphere.visible = false

# Call this from your player script when target moves
func set_target_position(start_pos: Vector3, target_pos: Vector3):
	update_arc(start_pos, target_pos)
	
func set_is_aiming(value: bool, source: Vector3 = Vector3.ZERO):
	is_aiming = value
	start_pos = source
	show_arc()
	
func set_arc_color(new_color: Color):
	arc_color = new_color
	for sphere in spheres:
		if sphere.mesh != null and sphere.mesh.material != null:
			sphere.mesh.material.albedo_color = new_color
