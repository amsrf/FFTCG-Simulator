extends Node3D

class_name Card
const CRYSTAL_SCENE_PATH = "res://crystal.tscn"
@export var id: int = 0  # Make this editable in the Inspector
var string_id: String = '0'
var hand_center = GlobalVariables.get_hand_center();
# Scale factor when hovered
# Original scale of the card
var original_scale: Vector3
var original_position: Vector3
var code: String
@export var power: int
@export var life: int
var crystal_scene
var crystal_instance
var current_state
@export var tapped = false;
@export var text = '';
@export var is_valid_target = false;
@export var is_target = false;
@export var cost: int
@export var is_dragging = false
@export var selected = false
@export var type: String
@export var card_name: String
@export var index = 0
@export var controller = 'player'
@export var element = ''
@export var field_actions : Array = []
@export var status_effects = {}
@export var card_effects : Dictionary

var offset = Vector3.ZERO
var camera: Camera3D
var action_buttons = []
signal card_dragged(card)
signal focus_card(card)
signal execute_instructions(instructions, card)
signal on_target(card)

func create_instruction_from_json(array: Array) -> Array[Instruction]:
	# Extract fields from JSON
	var ans: Array[Instruction] = []
	for json_instruction in array:
		var action: String = json_instruction.get("name", "")
		var executor: String = json_instruction.get("author", "")
		var value = json_instruction.get("argument", null)
		ans.append(Instruction.new(action, executor, value))
	
	# Create and return the Instruction
	return ans

func _ready():
	camera = get_viewport().get_camera_3d()
	crystal_scene = load(CRYSTAL_SCENE_PATH)
	
func initialize(card_id: int, card_controller: String):
	id = card_id
	string_id = str(card_id)
	controller = card_controller
	load_card_data()
	loard_card_effects()
	assign_card_texture()
		
func load_card_data():
	var card_data = CardDatabase.card_database[id-1]
	if card_data:
		type = card_data.get('type_en','Unknown type')
		card_name = card_data.get("name_en", "Unknown")
		power = int(card_data.get("power", 0))
		cost = int(card_data.get("cost", 0))
		code = card_data.get("code", "Unknown")
		text = card_data.get("text_en", "invalid")
		life = power
		element = card_data.get("element",'invalid')[0]
		
	else:
		print("Card with ID '%s' not found in database." % id)
		

func loard_card_effects():
	if string_id in CardDatabase.card_effects:
		card_effects = CardDatabase.card_effects[string_id]
		
	
func assign_card_texture():
	
	var texture_path = "res://assets/cards/%s.jpg" % code
	var texture = load(texture_path)
	if texture:
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		if has_node("MeshInstance3D"):  # Check if the node exists
			$MeshInstance3D.set_surface_override_material(0, material)
		else:
			print("No MeshInstance3D for card class.")
	else:
		print("Failed to load texture for card: ", code)
		
func _process(_delta):
	if is_dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_dragging = false
		else:
			# Update object position to mouse position
			emit_signal("card_dragged", self)
			global_transform.origin = _get_mouse_3d_position_on_card_plane() + offset
			

		
func _get_mouse_3d_position_on_card_plane() -> Vector3:
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Create a ray from camera through mouse position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Define the card's plane using its normal and a point on the plane
	var card_global_transform = global_transform
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


	
func scale_card(target_scale: Vector3):
	# Use a Tween for smooth scaling
	var tween = create_tween()
	tween.tween_property(self, "transform:basis", Basis().scaled(target_scale), 0.05) 


# Called when the node enters the scene tree or is reparented
func _notification(what):
	if what == NOTIFICATION_PARENTED:
		_update_state()  # Re-check parent when moved
		
func _update_state():
	# Assign the new state based on current parent
	var parent = get_parent()
	#print('state updated')
	if parent is Hand:
		current_state = HandCardState.new(self)
	elif parent is Field:
		current_state = FieldCardState.new(self)
	else:
		current_state = null
		pass
		
func set_state_based_on_parent():
	if get_parent() is Hand:
		current_state = HandCardState.new(self)
	elif get_parent() is Field:
		current_state = FieldCardState.new(self)
	else:
		current_state = null
			
func _on_card_area_3d_card_grabbed(_card: Variant):
	if current_state :
		current_state.handle_grabbed()

func build_card_effects():
	pass
	
func can_be_played():
	var player_mode = GlobalVariables.get_player_mode()
	if player_mode == GlobalVariables.Player_Mode.INSTANT_SPEED_RESPONSE:
		return type == 'Summon'
	if player_mode == GlobalVariables.Player_Mode.FREE:
		return true
	return false
func show_actions():
	if(not tapped and type == 'Forward'):
		var card_button_scene = preload("res://card_button.tscn")
		var card_button = card_button_scene.instantiate()
		action_buttons.append(card_button)
		
		card_button.position = Vector3(0.5, 0.1, -0.25)
		card_button.rotation_degrees = Vector3(0, 180, 0)
		card_button.set_on_press_callback(func(): 
			attack()
			hide_actions()
		)
		
		add_child(card_button)


func hide_actions():
	for button in action_buttons:
		button.queue_free()
	action_buttons = []
		
func tap():
	tapped = true
	rotation_degrees += Vector3(0,-90,0)

func untap():
	tapped = false
	rotation_degrees -= Vector3(0,-90,0)	
func suffer_damage(damage):
	life =  max(life - damage,0)
func add_status_effect(status,duration):
	status_effects[status] = duration
	
func execute_etb():
	print('pre enter field', card_effects)
	if 'when_enter_field' in card_effects:
		print('alchemist when enter field')
		var instructions = create_instruction_from_json(card_effects['when_enter_field'])
		print('alchemist ins ', instructions)
		emit_signal("execute_instructions",instructions,self)
	
func shatter():
	pass 
func attack():
	
	var instructions: Array[Instruction] = [
		#Instruction.new("request_target", "game", targeting_criteria),
		Instruction.new("tap", "card"),
		#Instruction.new("card_clash", "game"),
		Instruction.new("cause_damage", "game")
	]
	print('attack ', instructions, 'alchemist')
	emit_signal("execute_instructions",instructions,self)
	
func get_cost():
	var mana = ManaCost.new()  # Start with all costs at 0
	mana.cost[element] = 1
	mana.cost["neutral"] = cost - 1
	
	return mana
func reset():
	selected = false
	crystal_instance.queue_free()

func _on_card_area_3d_card_released(_card: Variant) -> void:
	if current_state :
		current_state.handle_released()
		
func set_valid_target(value: bool):
	is_valid_target = value
		
	
func set_target(value):
	is_target = value
		
func is_type(type:String) -> bool:
	return self.type == type

func is_tapped(_args: Array) -> bool:
	return self.tapped
	
func check_controller(args: Array) -> bool:
	return self.controller == args[0]
