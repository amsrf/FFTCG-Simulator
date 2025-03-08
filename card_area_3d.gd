extends Area3D

var is_dragging = false
var offset = Vector3.ZERO
var camera: Camera3D
var parent
signal card_released(card)
signal card_grabbed(card)

func _ready():
	input_event.connect(_on_input_event)
	camera = get_viewport().get_camera_3d()
	parent = get_parent()

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var focus_card = get_tree().get_nodes_in_group("focus_card")[0]
			focus_card.visible = true
			focus_card.initialize(parent.id)
			get_viewport().set_input_as_handled()
			

func dragging(event):
	if( not parent.get_parent() is Hand ):
		return
	if event.pressed:
		is_dragging = true
		emit_signal("card_grabbed", parent)  # Notify the manager
		get_parent().position +=  Vector3(0, 0.1,-0.1)
		offset = parent.global_transform.origin - _get_mouse_3d_position_on_card_plane()
		print("Card clicked!", _get_mouse_3d_position_on_card_plane())
	else:
		is_dragging = false
		emit_signal("card_released", parent)  # Notify the manager
		print("Card released!")
func _process(_delta):
	if is_dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_dragging = false
			print("Process Dragging")
			emit_signal("card_released", parent) 
		else:
			# Update object position to mouse position
			parent.global_transform.origin = _get_mouse_3d_position_on_card_plane() + offset

func _get_mouse_3d_position_on_card_plane() -> Vector3:
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Create a ray from camera through mouse position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Define the card's plane using its normal and a point on the plane
	var card_global_transform = parent.global_transform
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
