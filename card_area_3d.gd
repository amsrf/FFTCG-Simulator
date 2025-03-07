extends Area3D

var is_dragging = false
var offset = Vector3.ZERO
var camera: Camera3D

func _ready():
	input_event.connect(_on_input_event)
	camera = get_viewport().get_camera_3d()

func _on_input_event(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton:
		if event.pressed:
			is_dragging = true
			offset = get_parent().global_transform.origin - _get_mouse_3d_position_on_card_plane()
			var tween = create_tween()
			tween.tween_property(get_parent(), "scale", Vector3(1.1, 1.1, 1.1), 0.1)
			print("Card clicked!", _get_mouse_3d_position_on_card_plane())
		else:
			is_dragging = false
			var tween = create_tween()
			tween.tween_property(get_parent(), "scale", Vector3.ONE, 0.1)
			print("Card released!")
	#elif event is InputEventMouseMotion:
		#print("Mouse hovering over card!")

func _process(_delta):
	if is_dragging:
		# Update object position to mouse position
		get_parent().global_transform.origin = _get_mouse_3d_position_on_card_plane() + offset

func _get_mouse_3d_position_on_card_plane() -> Vector3:
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Create a ray from camera through mouse position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Define the card's plane using its normal and a point on the plane
	var card_global_transform = get_parent().global_transform
	var card_normal = card_global_transform.basis.y  # Assuming the card's "up" vector defines the plane normal
	var card_center = card_global_transform.origin  # A point on the card's plane
	
	# Create a plane using the card's normal and a point on the plane
	var card_plane = Plane(card_normal, card_center)
	
	# Calculate intersection of the ray with the card's plane
	var intersection = card_plane.intersects_ray(ray_origin, ray_normal)
	
	if intersection:
		return intersection
	else:
		# Fallback: Return the card's current position if no intersection is found
		return card_center
