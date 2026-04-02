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
@export var base_power: int
@export var life: int
var crystal_scene
var crystal_instance
var current_state
@export var target_arrow: BallisticArrow 
var mat: ShaderMaterial
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
@export var power_array = []
@export var card_effects : Dictionary
@export var key_word_effect: String
@export var effect_target: Card
@export var effect_source: Card

@onready var hand_mesh: MeshInstance3D = $HandMesh
@onready var field_mesh: MeshInstance3D = $FieldMesh

var offset = Vector3.ZERO
var camera: Camera3D
var action_buttons = []
var tween: Tween
var original_basis: Basis
# DEBUG VARIABLES
var debug_step: int = 0
var debug_log: Array = []

@onready var powerLife: Label3D =  $PowerDisplay
signal card_dragged(card)
signal focus_card(card)
signal execute_instructions(instructions)
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
	load_card_effects()
	assign_card_texture()
		
func load_card_data():
	var card_data = CardDatabase.card_database[id-1]
	if card_data:
		type = card_data.get('type_en','Unknown type')
		card_name = card_data.get("name_en", "Unknown")
		base_power = int(card_data.get("power", 0))
		power = base_power
		cost = int(card_data.get("cost", 0))
		code = card_data.get("code", "Unknown")
		text = card_data.get("text_en", "invalid")
		life = base_power
		element = card_data.get("element",'invalid')[0]
		
	else:
		print("Card with ID '%s' not found in database." % id)
		

func load_card_effects():
	if string_id in CardDatabase.card_effects:
		card_effects = CardDatabase.card_effects[string_id]
		
	
func assign_card_texture():
	var texture_path = "res://assets/cards/%s.jpg" % code
	var full_texture = load(texture_path)
	if not full_texture:
		push_error("Failed to load texture for card: %s" % code)
		return

	var shader = load("res://shaders/card.gdshader")
	mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texture_albedo", full_texture)
	mat.set_shader_parameter("effect_enabled", false)
	
	
	$HandMesh.set_surface_override_material(0, mat)
	$FieldMesh.set_surface_override_material(0, mat)

		
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
		
func _updateUI():
	showPower()

func _applyAurasOnField(field:Field):
	if 'aura' in card_effects:
		for aura in card_effects['aura']:
			field.add_aura(aura, self.get_instance_id())
			
func _receiveAurasFromField(field:Field):
	field.add_all_auras_to_card(self)
	
func _executeAuraEffects():
	var field: Field = get_parent()
	_applyAurasOnField(field)
	_receiveAurasFromField(field)

func _update_state():
	# Assign the new state based on current parent
	var parent = get_parent()
	#print('state updated')
	if parent is Hand:
		current_state = HandCardState.new(self)
	elif parent is Field:
		_updateUI()
		_executeAuraEffects()
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
	
func can_be_played():
	var player_mode = GlobalVariables.get_player_mode()
	if player_mode == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
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
	if "skill" in card_effects:
		for skill in card_effects["skill"]:
			var card_button_scene = preload("res://card_button.tscn")
			var card_button = card_button_scene.instantiate()
			action_buttons.append(card_button)
			
			card_button.position = Vector3(0.5, 0.1, -0.25)
			card_button.rotation_degrees = Vector3(0, 180, 0)
			card_button.set_text("Skill")
			card_button.set_on_press_callback(func(): 
				hide_actions()
			)
			
			add_child(card_button)

func is_on_field():
	return get_parent() is Field

func hide_actions():
	for button in action_buttons:
		button.queue_free()
	action_buttons = []
	
func showPower():
	if(powerLife == null):
		return
	if(type == 'Forward'):
		powerLife.visible = true
		mat.set_shader_parameter("effect_enabled", true)
	else:
		powerLife.visible = false
		
@export var tap_speed: float = 0.3
@export var tap_angle: float = -90.0

func tap():
	if tapped: return
	
	tapped = true
	
	if tween:
		tween.kill()
	
	# Rotate 90° clockwise FROM CURRENT POSITION
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:y",
						rotation_degrees.y - 90.0,  # -90° = clockwise
						tap_speed)

func untap():
	if not tapped: return
	
	tapped = false
	
	if tween:
		tween.kill()
	
	# Rotate 90° counter-clockwise back
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:y",
						rotation_degrees.y + 90.0,  # +90° = counter-clockwise
						tap_speed)


'''func _log_state(context: String):
	var entry = {
		"step": debug_step,
		"context": context,
		"time": Time.get_ticks_msec(),
		"rotation": rotation,
		"rotation_degrees": rotation_degrees,
		"global_rotation": global_rotation if has_method("global_rotation") else Vector3.ZERO,
		"transform_basis": transform.basis,
		"scale": scale,
		"position": position
	}
	debug_log.append(entry)
	
	print("\n[", context, "]")
	print("  rotation: ", rotation, " (", rotation_degrees, "°)")
	print("  scale: ", scale)
	print("  position: ", position)
# Call this before/after animations	'''
	
func suffer_damage(damage):
	life =  max(life - damage,0)

func take_damage(damage):
	life =  max(life - damage,0)
	
func add_status_effect(status,duration):
	status_effects[status] = duration
	
func turn_end():
	for s in status_effects:
		status_effects[s] -= 1
		if(status_effects[s] == 0):
			status_effects.erase(s)
	for p in power_array:
		p[1] -= 1
		if p[1] == 0:
			power -= p[0]
	powerLife.changePower(power)
	power_array.filter(func(x): return x[1] > 0)
	life = base_power
	
			
func power_change(amount,duration):
	power_array.append([amount,duration])
	power += amount
	powerLife.changePower(power)
	
func get_card_effect_instructions():#etb
	if key_word_effect in card_effects:
		return create_instruction_from_json(card_effects[key_word_effect]['instructions'])
	else:
		print("Error no keyword %s in card effects" % key_word_effect)
func is_key_word_in_card_effect(keyword:String):
	return keyword in card_effects
	
	
		
func declare_blocker():
	var instructions: Array[Instruction] = [
		Instruction.new('set_blocker','game', self),
		Instruction.new('clash_attacker_blocker','game'),
	]
	emit_signal("execute_instructions",instructions,self)

func can_attack():
	if(tapped):
		return false
	if(type != 'Forward'):
		return false
	return true
		
func attack():
	tap()
	
func get_cost() -> Dictionary:
	return {element:1, "neutral":cost-1}
func reset():
	crystal_instance.queue_free()

func _on_card_area_3d_card_released(_card: Variant) -> void:
	if current_state :
		current_state.handle_released()
		
func set_valid_target(value: bool):
	is_valid_target = value

func does_card_match_target(target_dict: Dictionary) -> bool:
	if target_dict.has("type") and type != target_dict["type"]:
		return false
	
	if target_dict.has("controller") and controller != target_dict["controller"]:
		return false
		
	if target_dict.has("element") and element != target_dict["element"]:
		return false
		
	return true
	
func set_target(value):
	is_target = value
	
func is_type(ntype:String) -> bool:
	return self.type == ntype

func is_tapped(_args: Array) -> bool:
	return self.tapped
	
func set_attacker_status(is_attacking: bool):
	if(is_attacking):
		status_effects['attacking'] = 1
		position.z += 0.05
	else:
		status_effects.erase('attacking')
		position.z -= 0.05
	
func check_controller(args: Array) -> bool:
	return self.controller == args[0]
	
func get_global_center():
	return global_position + Vector3(0.2,0.3,0)
	
func is_effect_card():
	return key_word_effect != null
	
func signal_target():
	emit_signal('on_target',self)
