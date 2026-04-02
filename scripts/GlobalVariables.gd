# Global.gd
extends Node

# Private variables
var _hand_center = Vector3(0, 2, -2.9)
var _card_width = 0.429
var _card_height = 0.6
var _card_spacing = -0.15
var _hand_rotation = Vector3(36, -180, 0)
var focus_card_id = null
enum Player_Mode { FREE, PAYING_COST, ATTACKING, BLOCKED, TARGET , NO_PRIORITY, INSTANT_SPEED_TIME, PRIORITY}
var player_mode: Player_Mode = Player_Mode.FREE
var priority_holder : int = 0
var phase: Phase

signal focus_card(id)
signal player_mode_change(pm : Player_Mode)
enum Phase {
	ACTIVE_PHASE,
	DRAW_PHASE,
	FIRST_MAIN_PHASE,
	ATTACK_PREPARATION_STEP,
	ATTACK_DECLARATION_STEP,
	BLOCKER_DECLARATION_STEP,
	DAMAGE_RESOLUTION_STEP,
	COMBAT_END_STEP,
	SECOND_MAIN_PHASE,
	END_PHASE
}

var phase_priority_map: Dictionary = {
	Phase.ACTIVE_PHASE: Player_Mode.NO_PRIORITY,  # CORRECTED: Players can use abilities/summons.
	Phase.DRAW_PHASE: Player_Mode.NO_PRIORITY,     # CORRECTED: Priority window exists before the draw.
	Phase.FIRST_MAIN_PHASE: Player_Mode.FREE,
	Phase.ATTACK_PREPARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.ATTACK_DECLARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.BLOCKER_DECLARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.DAMAGE_RESOLUTION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.COMBAT_END_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.SECOND_MAIN_PHASE: Player_Mode.FREE,
	Phase.END_PHASE: Player_Mode.INSTANT_SPEED_TIME
}

func reset_to_default_phase_player_mode():
	var pm = phase_priority_map[phase]
	set_player_mode(pm)


# Setters (optional, if you want to allow modification)
func set_player_mode(value : Player_Mode):
	player_mode = value
	player_mode_change.emit(value)
	var stack_trace = get_stack()
	
func set_phase(phase_param:Phase):
	phase = phase_param
	var pm = phase_priority_map[phase]
	set_player_mode(pm)
	
func get_player_mode():
	return player_mode
	
func get_priority():
	return priority_holder
	
func set_priority_holder(id:int):
	priority_holder = id

# Getters
func get_hand_center():
	return _hand_center

func get_card_width():
	return _card_width

func get_card_spacing():
	return _card_spacing

func get_hand_rotation():
	return _hand_rotation

# Setters (optional, if you want to allow modification)
func set_hand_center(value):
	_hand_center = value

func set_card_width(value):
	_card_width = value

func set_card_spacing(value):
	_card_spacing = value
