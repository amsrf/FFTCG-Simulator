# Global.gd
extends Node

# Private variables
var _hand_center = Vector3(0, 1.25, -2.55)
var _zoom_card_position = Vector3(-0.7,3.1,-2.6)
var _deck_position = Vector3(2.7,0,-1.85)
var _card_width = 0.429
var _card_spacing = 0.020
var _hand_rotation = Vector3(36, -180, 0)

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
