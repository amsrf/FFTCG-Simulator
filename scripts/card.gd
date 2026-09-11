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
## Damage the card has accumulated this turn. The card breaks once this
## reaches its current power; it is reset to 0 during the End Phase. (Replaces
## the old "life" counter, which counted down from power.)
@export var accumulated_damage: int = 0
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
## Index into card_effects["skill"] for stack copies activating a skill (-1 = not used).
@export var skill_activation_index: int = -1
## "Summon" / "Ability" for stack copies; empty on real cards. Lets protection
## rules ("cannot be chosen by opponent's Summons or abilities") identify the
## source of a targeting effect.
@export var effect_kind: String = ""
## Power currently granted by conditional continuous effects (e.g. Zack/Aerith).
var current_conditional_bonus: int = 0

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

@onready var power_label: Label3D =  $PowerDisplay
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
		accumulated_damage = 0
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
	tween = create_tween()
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
	hide_actions()
	# Only activated abilities get buttons here. Attacking is handled by the
	# ATTACK_DECLARATION_STEP flow (FieldCardState), not by card buttons.
	if "skill" in card_effects:
		var si := 0
		for skill in card_effects["skill"]:
			var idx := si
			si += 1
			var card_button_scene = preload("res://card_button.tscn")
			var card_button = card_button_scene.instantiate()
			action_buttons.append(card_button)
			
			card_button.position = Vector3(0.5 + 0.35 * idx, 0.1, -0.25)
			card_button.rotation_degrees = Vector3(0, 180, 0)
			card_button.set_text("Skill")
			card_button.set_on_press_callback(func():
				var f := get_parent() as Field
				if f:
					f.begin_skill_activation(self, idx)
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
	if(power_label == null):
		return
	if(type == 'Forward'):
		power_label.visible = true
		mat.set_shader_parameter("effect_enabled", true)
	else:
		power_label.visible = false
		
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
	
func suffer_damage(damage: int):
	# Damage accumulates; the card breaks once the total reaches its current
	# power (enforced by Game.enforce_game_state_rules()).
	accumulated_damage += damage
	if power_label:
		power_label.changeAccumulatedDamage(accumulated_damage)

func take_damage(damage: int):
	# Alias kept for effect data that uses the "take_damage" instruction.
	suffer_damage(damage)

func is_broken() -> bool:
	# Break rule: accumulated damage equal to or greater than current power.
	return accumulated_damage >= power

func has_zero_power() -> bool:
	# Power of 0 or less is NOT a break: the card is put into the Graveyard.
	return power <= 0

func clear_damage():
	# End Phase cleanup: all damage is removed from the card.
	accumulated_damage = 0
	if power_label:
		power_label.changeAccumulatedDamage(0)

func add_status_effect(status,duration):
	status_effects[status] = duration
	
func turn_end():
	# End Phase cleanup for this card: expire "until end of turn" status
	# effects and temporary power modifiers, then remove all damage.
	for s in status_effects.keys():
		var dur = status_effects[s]
		if dur is int:
			dur -= 1
			if dur <= 0:
				status_effects.erase(s)
			else:
				status_effects[s] = dur

	var remaining_buffs: Array = []
	for p in power_array:
		var dur = p[1]
		if dur is int and dur > 0:
			dur -= 1
			if dur > 0:
				p[1] = dur
				remaining_buffs.append(p)
			else:
				power -= p[0]
		else:
			# Permanent modifiers (aura: duration -1 or null) never expire.
			remaining_buffs.append(p)
	power_array = remaining_buffs
	if power_label:
		power_label.changePower(power)
	clear_damage()
	
			
func power_change(amount, duration):
	# duration < 0 (or null) means permanent (used by auras).
	if duration == null:
		duration = -1
	power_array.append([amount, duration])
	power += amount
	if power_label:
		power_label.changePower(power)
	
func get_card_effect_instructions() -> Array[Instruction]:
	if key_word_effect == "skill" and skill_activation_index >= 0:
		if not "skill" in card_effects:
			print("Error: no skill entry for card ", id)
			return []
		var skills = card_effects["skill"]
		if skill_activation_index >= skills.size():
			return []
		var raw = skills[skill_activation_index].get("instructions", [])
		return create_instruction_from_json(raw)
	if key_word_effect != "" and key_word_effect in card_effects:
		var entry = card_effects[key_word_effect]
		if entry is Dictionary and entry.has("instructions"):
			return create_instruction_from_json(entry["instructions"])
		if entry is Array and entry.size() > 0:
			var first = entry[0]
			if first is Dictionary and first.has("instructions"):
				return create_instruction_from_json(first["instructions"])
	print("Error no keyword %s in card effects" % key_word_effect)
	return []
func is_key_word_in_card_effect(keyword:String):
	return keyword in card_effects
	
	
		
func declare_blocker():
	var instructions: Array[Instruction] = [
		Instruction.new('set_blocker','game', self),
		Instruction.new('clash_attacker_blocker','game'),
	]
	emit_signal("execute_instructions", instructions)

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

func get_cast_target_criteria() -> Dictionary:
	# Targeting requirement for casting (Summons use "when_cast").
	if "when_cast" in card_effects:
		var entry = card_effects["when_cast"]
		if entry is Dictionary and entry.has("choose_target"):
			var criteria = entry["choose_target"]
			if criteria is Dictionary:
				return criteria
	return {}

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

func is_cost_lower_than(value: int) -> bool:
	return cost < value

func is_named(value: String) -> bool:
	# Card-name condition (e.g. "if you control a card named Aerith").
	return card_name == value

const ELEMENT_NAMES = {
	"Fire": "火",
	"Ice": "氷",
	"Wind": "風",
	"Earth": "土",
	"Lightning": "雷",
	"Water": "水",
	"Light": "光",
	"Dark": "闇",
}

func is_element(value: String) -> bool:
	# Accepts either the English element name ("Fire") or the game's
	# single-character element code ("火").
	if element == value:
		return true
	return ELEMENT_NAMES.get(value, "") == element

func matches_criteria(criteria: Dictionary) -> bool:
	# Criteria keys are method names on Card (is_type, is_element, ...).
	for key in criteria:
		var method_name = key
		if not has_method(method_name):
			push_error("Criteria method not found on Card: %s" % method_name)
			return false
		var method_args = [criteria[key]]
		if not callv(method_name, method_args):
			return false
	return true

func get_effect_kind() -> String:
	# Targeting-source kind for protection checks: "Summon" or "Ability".
	# Explicit effect_kind wins; otherwise derive from the card itself.
	if effect_kind != "":
		return effect_kind
	if type == "Summon":
		return "Summon"
	if is_effect_card():
		return "Ability"
	return ""

func can_be_chosen_by(source: Card, source_kind: String = "") -> bool:
	# Protection rules (e.g. Zidane: "cannot be chosen by your opponent's
	# Summons or abilities"). Unlike choose_target, these are evaluated against
	# the SOURCE of the targeting effect, not against this card.
	if source == null:
		return true
	if not card_effects.has("cannot_be_chosen"):
		return true
	var rule = card_effects["cannot_be_chosen"]
	if not (rule is Dictionary):
		return true
	# "controller": "opponent" means the rule applies only to the other
	# player's effects. Any other/absent value applies to every source.
	var scope: String = str(rule.get("controller", ""))
	if scope == "opponent" and source.controller == self.controller:
		return true
	var kind: String = source_kind if source_kind != "" else source.get_effect_kind()
	var sources: Array = rule.get("sources", [])
	if not sources.is_empty() and not (kind in sources):
		return true
	return false

func is_tapped(_args = null) -> bool:
	return self.tapped
	
func set_attacker_status(is_attacking: bool):
	if(is_attacking):
		status_effects['attacking'] = 1
		position.z += 0.05
	else:
		status_effects.erase('attacking')
		position.z -= 0.05
	
func check_controller(args) -> bool:
	if args is Array:
		return self.controller == args[0]
	return self.controller == args

func get_global_center():
	return global_position + Vector3(0.2,0.3,0)
	
func is_effect_card() -> bool:
	# Real cards cast from hand have an empty key_word_effect. Only stack
	# copies (triggered abilities, skill proxies) are effect cards.
	return key_word_effect != ""
	
func signal_target():
	emit_signal('on_target',self)
