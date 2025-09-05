# Global.gd
extends Node

# Private variables
var _hand_center = Vector3(0, 2, -2.9)
var _card_width = 0.429
var _card_spacing = -0.15
var _hand_rotation = Vector3(36, -180, 0)
var focus_card_id = null
enum Player_Mode { FREE, PAYING_COST, BLOCKED, TARGET , NO_PRIORITY, INSTANT_SPEED_RESPONSE}
var player_mode: Player_Mode = Player_Mode.FREE
var priority = true

signal focus_card(id)

# Setters (optional, if you want to allow modification)
func set_player_mode(value : Player_Mode):
	player_mode = value
	
func get_player_mode():
	return player_mode
	
func get_priority():
	return priority

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
