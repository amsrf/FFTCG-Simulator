extends Node3D

class_name CardInField
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

var offset = Vector3.ZERO
var camera: Camera3D
var action_buttons = []
@onready var powerLife: Label3D =  $PowerDisplay
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
	if not texture:
		push_error("Failed to load texture for card: %s" % code)
		return

	var shader = load("res://shaders/card.gdshader")
	mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texture_albedo", texture)
	mat.set_shader_parameter("cutoff", 0.875)
	mat.set_shader_parameter("effect_enabled", false)

	$MeshInstance3D.set_surface_override_material(0, mat)
	
	
func scale_card(target_scale: Vector3):
	# Use a Tween for smooth scaling
	var tween = create_tween()
	tween.tween_property(self, "transform:basis", Basis().scaled(target_scale), 0.05) 
		
func _updateUI():
	showPower()
			
func _on_card_area_3d_card_grabbed(_card: Variant):
	if current_state :
		current_state.handle_grabbed()

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
		mat.set_shader_parameter("effect_enabled", false)
		
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
func power_change(amount,duration):
	power_array.append([amount,duration])
	power += amount
	powerLife.changePower(power)
	
func execute_etb():
	if 'when_enter_field' in card_effects:
		var instructions = create_instruction_from_json(card_effects['when_enter_field'])
		emit_signal("execute_instructions",instructions,self)

func execute_attack_effect():
	if 'when_attack' in card_effects:
		var instructions = create_instruction_from_json(card_effects['when_attack'])
		emit_signal("execute_instructions",instructions,self)
		
func declare_blocker():
	var instructions: Array[Instruction] = [
		Instruction.new('set_blocker','game', self),
		#Instruction.new("pass_priority","game"),
		Instruction.new('clash_attacker_blocker','game'),
		
	]
	emit_signal("execute_instructions",instructions,self)

func attack():
	var instructions: Array[Instruction] = [
		#Instruction.new("request_target", "game", targeting_criteria),
		Instruction.new('set_attacker','game', self),
		Instruction.new("tap", "card"),
		Instruction.new('execute_attack_effect',"card"),
		Instruction.new("pass_priority","game"),
		#Instruction.new("card_clash", "game"),
		Instruction.new("cause_attacking_damage", "game")
	]
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
		
func is_type(ntype:String) -> bool:
	return self.type == ntype

func is_tapped(_args: Array) -> bool:
	return self.tapped
	
func check_controller(args: Array) -> bool:
	return self.controller == args[0]
	
func get_global_center():
	return global_position + Vector3(0.2,0.3,0)
	
func signal_target():
	emit_signal('on_target',self)
