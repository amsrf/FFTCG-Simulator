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
	_build_target_border()
	
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
		
	
## False while the card is face-down. `mat` (the art material) is kept so that
## revealing restores the SAME instance — rebuilding it would drop the shader's
## `effect_enabled` highlight state.
var revealed: bool = true
var _card_back_material: StandardMaterial3D = null

## Show the card's art, or a plain back for a card whose identity is not public
## knowledge yet (a card parked while its cost is being paid). There is no back
## art asset, so the "back" is a flat dark material.
func set_revealed(is_revealed: bool) -> void:
	if revealed == is_revealed:
		return
	revealed = is_revealed
	var surface_material: Material = mat if is_revealed else _get_card_back_material()
	$HandMesh.set_surface_override_material(0, surface_material)
	$FieldMesh.set_surface_override_material(0, surface_material)

func _get_card_back_material() -> StandardMaterial3D:
	if _card_back_material == null:
		_card_back_material = StandardMaterial3D.new()
		_card_back_material.albedo_color = Color(0.10, 0.11, 0.16)
		_card_back_material.roughness = 0.85
	return _card_back_material

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

## Loaded by PATH rather than by its `class_name`: a newly added global class is only registered
## in Godot's class cache by the editor, so a headless run would fail to parse this file with
## `Identifier "StackCardState" not declared` until the project is opened once.
const STACK_CARD_STATE := preload("res://scripts/stack_card_state.gd")

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
	elif parent is Stack:
		# A stack card IS clickable — it selects itself so its own targeting is displayed —
		# but it is not played by anyone, so this is its only interaction.
		current_state = STACK_CARD_STATE.new(self)
	else:
		current_state = null
		pass
		
func set_state_based_on_parent():
	if get_parent() is Hand:
		current_state = HandCardState.new(self)
	elif get_parent() is Field:
		current_state = FieldCardState.new(self)
	elif get_parent() is Stack:
		current_state = STACK_CARD_STATE.new(self)
	else:
		current_state = null
			
func _on_card_area_3d_card_grabbed(_card: Variant):
	if current_state :
		current_state.handle_grabbed()

## Hover on the card's own area. The hand's LIFT is driven separately by HandMesh
## (mesh_instance_3d.gd); these handlers exist so a zone can react to the pointer being over a
## card. Only the stack needs it: hovering a stack card puts THAT card's targeting on display.
func _on_card_area_3d_mouse_entered():
	var stack: Stack = get_parent() as Stack
	if stack != null:
		stack.set_hovered(self, true)

func _on_card_area_3d_mouse_exited():
	var stack: Stack = get_parent() as Stack
	if stack != null:
		stack.set_hovered(self, false)
	
func can_be_played():
	var player_mode = GlobalVariables.get_player_mode()
	if player_mode == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return type == 'Summon'
	if player_mode == GlobalVariables.Player_Mode.FREE:
		# Summons are always playable; a Character is only legal for the turn
		# player and only with an empty stack. Card keeps no game reference, so
		# ask the Hand it is in (its parent while in hand).
		if type == 'Summon':
			return true
		var owner_hand = get_parent()
		if owner_hand != null and owner_hand.has_method("can_play_character"):
			return owner_hand.can_play_character(self)
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

## The power/damage readout is field-only information: a card in hand, deck,
## stack, damage zone or graveyard must never wear it.
func hide_power_display() -> void:
	if power_label != null:
		power_label.visible = false

## Where a card currently lives. Its whole presentation (scale, rotation baseline,
## which UI is shown) is derived from this, so there is ONE place deciding how a
## card looks — instead of every zone transition leaving the previous zone's
## transform, scale and readout on the card.
enum Zone { NONE, DECK, HAND, FIELD, STACK, GRAVEYARD, DAMAGE }

## Cards read correctly in this project when turned a half turn about Y relative
## to the identity frame. The Hand, Stack, Graveyard, Deck and FocusCard scene
## nodes all supply that themselves with a flipped basis (-1 on X and Z), so their
## cards keep a zero local rotation. **The Field does not** — it is a plain
## identity node — which is why Field.play_card() used to inherit the half turn
## implicitly by preserving the card's global transform, and why zeroing the
## rotation put every field card upside down.
const READABLE_ROTATION := Vector3(0, PI, 0)

## Per-zone look. `rotation` is the card's LOCAL baseline for that zone (see
## READABLE_ROTATION: it depends on whether the container node is flipped).
## `power_ui` is the field readout (Forward power + accumulated damage). A zone's
## layout code may still add rotation on top of this baseline — the hand fan adds
## its per-card tilt — but it starts from here.
const ZONE_PRESENTATION := {
	Zone.NONE:      {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	Zone.DECK:      {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	Zone.HAND:      {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	Zone.FIELD:     {"scale": 1.2, "rotation": READABLE_ROTATION, "power_ui": true},
	Zone.STACK:     {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	Zone.GRAVEYARD: {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	# TODO: the damage-zone node is identity like the Field, so by this rule it
	# needs READABLE_ROTATION too. Left alone until it can be eyeballed, because
	# the OPPONENT's damage zone is authored with a +90 deg frame instead.
	Zone.DAMAGE:    {"scale": 1.2, "rotation": Vector3.ZERO,      "power_ui": false},
}

var current_zone: Zone = Zone.NONE

## The ONE entry point for a zone change. Call it as soon as the card has been
## reparented and BEFORE the destination lays it out: it normalises rotation and
## scale, drops every transient marker (drag, target glow, mana crystal) and shows
## or hides the field readout. Positions stay the zone's own business.
func enter_zone(zone: Zone) -> void:
	current_zone = zone
	var presentation: Dictionary = ZONE_PRESENTATION.get(zone, ZONE_PRESENTATION[Zone.NONE])
	# Local rotation: NOT always zero — see READABLE_ROTATION. The Field is an
	# unflipped container, so its cards must carry the half turn themselves.
	rotation = presentation["rotation"]
	scale = Vector3.ONE * float(presentation["scale"])
	is_dragging = false
	is_valid_target = false
	# EVERY meaning of the ring is about a card in its CURRENT zone: the prompt, "you picked
	# this", "they picked this", and "you may activate this". Leaving any of them set would
	# carry the ring into the next zone — a red or a green one into the graveyard.
	_prompt_glow = false
	_selected_highlight_on = false
	_targeted_highlight_on = false
	_available_highlight_on = false
	_refresh_target_ring()
	reset()  # drops the mana-crystal marker
	if bool(presentation["power_ui"]):
		showPower()
	else:
		hide_power_display()
		
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
	# Only records the blocker. The clash belongs to DAMAGE_RESOLUTION — doing it
	# here as well would apply the damage twice.
	var instructions: Array[Instruction] = [
		Instruction.new('set_blocker','game', self),
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

## "Selected as a mana source" marker. Owned here so that every selection path —
## the human's clicks and an agent paying a cost — produces the same marker.
func show_mana_crystal() -> void:
	if crystal_instance != null or crystal_scene == null:
		return
	crystal_instance = crystal_scene.instantiate()
	add_child(crystal_instance)
	crystal_instance.position = Vector3(0, 0.05, -0.35)

func clear_mana_crystal() -> void:
	if crystal_instance == null:
		return
	crystal_instance.queue_free()
	crystal_instance = null

func reset():
	clear_mana_crystal()

func _on_card_area_3d_card_released(_card: Variant) -> void:
	if current_state :
		current_state.handle_released()
		
## Glow ring marking a card the game is asking the player to choose or target.
## ALL of the look lives in shaders/target_border_material.tres — open it in the
## editor to tune colours, thickness and pulse from the Inspector. Card itself
## only supplies `card_size` (read from the mesh) and drives `intensity`.
const TARGET_BORDER_MATERIAL := preload("res://shaders/target_border_material.tres")
var target_border: MeshInstance3D = null
var _border_material: ShaderMaterial = null
var _border_tween: Tween = null
var _highlight_on: bool = false

## `glow` exists because legality and visibility are not the same thing. `is_valid_target`
## gates the local player's clicks and is what an agent looks for; the blue ring means "the
## game is asking YOU". When the OPPONENT is the one choosing, the flag must still be set
## (their agent needs it) but the ring is suppressed — we show only the card they actually
## pick, in red.
func set_valid_target(value: bool, glow: bool = true):
	is_valid_target = value
	set_prompt_glow(value and glow)

## The card the player has actually PICKED (the current target, or the card chosen
## for an effect): the same ring in a different colour, so the orange one obviously
## means "this one" while the blue ones are merely legal.
const SELECTED_BORDER_COLOR := Color(1.0, 0.45, 0.05)
const SELECTED_GLOW_COLOR := Color(0.95, 0.32, 0.0)
## The card the OPPONENT has chosen. Their legal options are not our business, so this is
## the only cue we get about an incoming effect while it is still on the stack — drawn in
## red, alongside their targeting arc.
const TARGETED_BORDER_COLOR := Color(0.95, 0.12, 0.12)
const TARGETED_GLOW_COLOR := Color(0.85, 0.03, 0.03)
## A card whose effect YOU can activate right now: an untapped Backup with a "skill", in a
## moment where acting is allowed. Green means "this is available", not "this is being chosen"
## — it goes dark the instant a targeting or payment modal takes the moment away.
const AVAILABLE_BORDER_COLOR := Color(0.15, 0.95, 0.3)
const AVAILABLE_GLOW_COLOR := Color(0.04, 0.7, 0.12)
## The material's own colours, captured when it is built so deselecting restores
## them. Safe because every card owns its own duplicate of the material.
var _border_color_base: Color = Color.WHITE
var _glow_color_base: Color = Color.WHITE
## ONE ring, FOUR meanings. Colour and visibility are derived from these flags together by
## _refresh_target_ring() rather than written to the material by each setter in turn: with
## several independent writers the last one to run decided the colour, and a setter that only
## recoloured left the ring dark (it has to be LIT as well — see set_highlight).
var _prompt_glow: bool = false
var _selected_highlight_on: bool = false
var _targeted_highlight_on: bool = false
var _available_highlight_on: bool = false

## "The game is asking YOU to pick this" (blue) — the same meaning in the hand and on the field.
func set_prompt_glow(enabled: bool) -> void:
	_prompt_glow = enabled
	_refresh_target_ring()

func set_selected_highlight(enabled: bool) -> void:
	if enabled == _selected_highlight_on:
		return
	_selected_highlight_on = enabled
	_refresh_target_ring()

## Mirror of set_selected_highlight() for the opponent's choice: red is "they picked this".
func set_targeted_highlight(enabled: bool) -> void:
	if enabled == _targeted_highlight_on:
		return
	_targeted_highlight_on = enabled
	_refresh_target_ring()

## "You could activate this card's effect right now" (see Field.can_activate_now).
func set_available_highlight(enabled: bool) -> void:
	if enabled == _available_highlight_on:
		return
	_available_highlight_on = enabled
	_refresh_target_ring()

## The material's stock widths, captured when the ring is built (see _build_target_border).
var _border_width_base: float = 0.025
var _glow_width_base: float = 0.07
## How wide the green availability ring is drawn, as a fraction of the others. It is a STANDING
## cue — it can sit on several cards for a whole turn — while blue/orange/red are momentary, so
## it is drawn thinner to stay subordinate to them.
const AVAILABLE_WIDTH_SCALE := 0.5

## The single owner of the ring's appearance: LIT if any meaning is on, and coloured by
## priority — orange (my pick) over red (their pick) over green (available) over blue (merely
## legal). Lighting it is not optional: a ring that is coloured but not lit shows nothing on
## screen, which is how the red reveal once shipped invisible.
func _refresh_target_ring() -> void:
	var lit: bool = _prompt_glow or _selected_highlight_on or _targeted_highlight_on or _available_highlight_on
	if target_border == null and not lit:
		# Nothing built and nothing wanted: do not build a ring just to switch it off.
		_highlight_on = false
		return
	if target_border == null:
		_build_target_border()
	if _border_material == null:
		return
	# Width before colour. Only the green scales, and every other state restores the stock
	# width, so switching between states is exact rather than accumulating.
	var width_scale: float = AVAILABLE_WIDTH_SCALE if _available_highlight_on else 1.0
	_border_material.set_shader_parameter("border_width", _border_width_base * width_scale)
	_border_material.set_shader_parameter("glow_width", _glow_width_base * width_scale)
	var color: Color = _border_color_base
	var glow: Color = _glow_color_base
	if _available_highlight_on:
		color = AVAILABLE_BORDER_COLOR
		glow = AVAILABLE_GLOW_COLOR
	if _targeted_highlight_on:
		color = TARGETED_BORDER_COLOR
		glow = TARGETED_GLOW_COLOR
	if _selected_highlight_on:
		color = SELECTED_BORDER_COLOR
		glow = SELECTED_GLOW_COLOR
	_border_material.set_shader_parameter("border_color", color)
	_border_material.set_shader_parameter("glow_color", glow)
	set_highlight(lit)

## Show/hide the selectable/targetable glow. Fades so the cue does not pop, and
## is cheap to call repeatedly: Hand.refresh_highlights() runs on every layout,
## so an unchanged request must not restart the tween.
func set_highlight(enabled: bool) -> void:
	if target_border == null:
		_build_target_border()
	if target_border == null:
		return
	if enabled == _highlight_on:
		return
	_highlight_on = enabled
	if not is_inside_tree():
		_border_material.set_shader_parameter("intensity", 1.0 if enabled else 0.0)
		target_border.visible = enabled
		return
	if _border_tween != null and _border_tween.is_valid():
		_border_tween.kill()
	_border_tween = create_tween()
	if enabled:
		target_border.visible = true
	_border_tween.tween_method(_set_border_intensity, _border_intensity(), 1.0 if enabled else 0.0, 0.12)
	if not enabled:
		_border_tween.tween_callback(func(): target_border.visible = false)

func _border_intensity() -> float:
	return float(_border_material.get_shader_parameter("intensity"))

func _set_border_intensity(value: float) -> void:
	_border_material.set_shader_parameter("intensity", value)

## Built in code rather than authored in card.tscn so the quad can be sized from
## the card mesh's own AABB: the ring then lands on whatever silhouette the art
## has, and nothing in the scene tree has to be kept in sync by hand.
##
## The quad must COVER the whole glow, and the quad's edge is what crops it if it
## does not: the ring is drawn outside the card (half-extent = card_size/2 +
## margin). So the margin is DERIVED here from the material's own ring/spill widths
## instead of being tuned by hand — raise `border_width` or `glow_width` and the
## quad grows with it. The floors only exist so a failed parameter lookup (which
## returns null, i.e. 0.0) cannot collapse the quad onto the card and crop the ring.
const BORDER_MARGIN_MIN := 0.05

## Reported once per run so the numbers the shader is actually using are visible in
## the output — the quickest way to tell whether a .tres tweak is reaching it.
static var _border_look_reported: bool = false

func _report_target_border_look(size: Vector2, margin: float) -> void:
	if _border_look_reported:
		return
	_border_look_reported = true
	print("[TargetBorder] card=%s quad=%s border_width=%.3f border_color=%s glow_width=%.3f glow_color=%s" % [
		size,
		size + Vector2.ONE * margin * 2.0,
		float(_border_material.get_shader_parameter("border_width")),
		str(_border_material.get_shader_parameter("border_color")),
		float(_border_material.get_shader_parameter("glow_width")),
		str(_border_material.get_shader_parameter("glow_color")),
	])

func _build_target_border() -> void:
	if target_border != null:
		return
	var size: Vector2 = _card_face_size()
	# The look lives in target_border_material.tres so it can be tuned in the
	# Inspector; duplicated so every card owns its own fade.
	_border_material = TARGET_BORDER_MATERIAL.duplicate()
	_border_material.set_shader_parameter("card_size", size)
	_border_material.set_shader_parameter("intensity", 0.0)
	# Remember the stock colours so set_selected_highlight() can put them back.
	var border_color: Variant = _border_material.get_shader_parameter("border_color")
	if border_color is Color:
		_border_color_base = border_color
	var glow_color: Variant = _border_material.get_shader_parameter("glow_color")
	if glow_color is Color:
		_glow_color_base = glow_color
	# ...and the stock WIDTHS, so a state can be drawn thinner (the green availability ring is
	# half width) without losing the look the material was tuned to.
	_border_width_base = maxf(float(_border_material.get_shader_parameter("border_width")), 0.005)
	_glow_width_base = maxf(float(_border_material.get_shader_parameter("glow_width")), 0.0)
	# Size the quad from the ring + spill, and write the result back so the shader
	# and the geometry can never disagree about where the glow ends.
	var border_width: float = _border_width_base
	var glow_width: float = _glow_width_base
	# 3x the spill width is roughly where its exponential has decayed to ~5%.
	var margin: float = maxf(border_width + glow_width * 3.0 + 0.01, BORDER_MARGIN_MIN)
	_border_material.set_shader_parameter("margin", margin)
	_report_target_border_look(size, margin)
	var plane := PlaneMesh.new()
	# PlaneMesh lies in the XZ plane with normal +Y — the same plane the card mesh
	# uses (card.tres AABB), so it needs no rotation.
	plane.size = size + Vector2.ONE * margin * 2.0
	target_border = MeshInstance3D.new()
	target_border.name = "TargetBorder"
	target_border.mesh = plane
	target_border.material_override = _border_material
	# A hair above the face (the card quad sits at y ~ 0) so they never z-fight;
	# the shader draws nothing inside the silhouette either way.
	target_border.position = Vector3(0, 0.002, 0)
	target_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target_border.visible = false
	# Parented to the visible mesh, NOT to the Card: the hand's hover animation
	# moves and scales HandMesh without touching the Card, so a sibling border
	# would be left behind. As a child it follows the lift and scales with the
	# card, which is what keeps the ring hugging the edge.
	var border_parent: Node3D = hand_mesh if hand_mesh != null else self
	border_parent.add_child(target_border)

## Card face size in metres. The mesh is a flat quad in XZ (0.429 x 0.6), so the
## AABB's x is the width and its z the height.
func _card_face_size() -> Vector2:
	if hand_mesh != null and hand_mesh.mesh != null:
		var aabb: AABB = hand_mesh.mesh.get_aabb()
		if aabb.size.x > 0.0 and aabb.size.z > 0.0:
			return Vector2(aabb.size.x, aabb.size.z)
	return Vector2(0.429, 0.6)

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

## Transient "selected as this combat's blocker" marker. Mirrors
## set_attacker_status() but keeps its own status key, so being a blocker never
## masquerades as being an attacker.
func set_blocker_status(is_blocking: bool) -> void:
	if(is_blocking):
		status_effects['blocking'] = 1
		position.z += 0.05
	else:
		status_effects.erase('blocking')
		position.z -= 0.05
	
func check_controller(args) -> bool:
	if args is Array:
		return self.controller == args[0]
	return self.controller == args

func get_global_center():
	return global_position + Vector3(0.2,0.3,0)

## True centre of the card's FACE in world space. The card mesh is centred on its own
## origin, so this is simply the position. (get_global_center() above adds a fixed
## (0.2, 0.3, 0) offset and is NOT the centre; it is left alone because other callers
## depend on its behaviour, but anything that must land exactly on the middle of the
## card — the targeting arc's destination — uses this.)
func get_global_face_centre() -> Vector3:
	return global_position

## Mid-point of the edge the player sees as the card's TOP, in world space. The
## targeting arc leaves from here rather than from the middle of the card.
func get_global_top_centre() -> Vector3:
	var half_height: float = _card_face_size().y * 0.5 * global_transform.basis.z.length()
	var axis: Vector3 = global_transform.basis.z.normalized()
	var edge_a: Vector3 = global_position + axis * half_height
	var edge_b: Vector3 = global_position - axis * half_height
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return edge_a
	# Viewport y grows downwards, so the smaller projection is the edge that reads as
	# the top. Testing the two candidate edges keeps this right whatever the card's own
	# rotation or fan tilt happens to be.
	return edge_a if cam.unproject_position(edge_a).y <= cam.unproject_position(edge_b).y else edge_b

func is_effect_card() -> bool:
	# Real cards cast from hand have an empty key_word_effect. Only stack
	# copies (triggered abilities, skill proxies) are effect cards.
	return key_word_effect != ""
	
func signal_target():
	emit_signal('on_target',self)
