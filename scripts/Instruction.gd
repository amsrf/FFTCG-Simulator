class_name Instruction
extends RefCounted  # Lightweight reference-counted base class

var action: String      # e.g., "destroy", "draw", "tap"
var executor: String    # e.g., "card", "hand", "game_manager"
var value    # e.g., 2 (damage amount, cards to draw)

func _init(p_action: String, p_executor: String, p_value = null):
	action = p_action
	executor = p_executor
	value = p_value

func _to_string() -> String:
	var value_str = str(value) if value != null else "null"
	return "[Instruction: %s -> %s (value: %s)]" % [executor, action, value_str]
