class_name Instruction
extends RefCounted  # Lightweight reference-counted base class

var action: String      # e.g., "destroy", "draw", "tap"
var executor: String    # e.g., "card", "hand", "game_manager"
var value    # e.g., 2 (damage amount, cards to draw)
## Optional guard, set from the card data's "condition" key. Today the only one is "if_last_succeeded": run this
## instruction only if the previous one reported success (e.g. "search ... and if you do so, return Vanille").
## Empty means run unconditionally, which is every instruction written before this existed.
var condition: String = ""

func _init(p_action: String, p_executor: String, p_value = null, p_condition: String = ""):
	action = p_action
	executor = p_executor
	value = p_value
	condition = p_condition

func _to_string() -> String:
	var value_str = str(value) if value != null else "null"
	return "[Instruction: %s -> %s (value: %s)]" % [executor, action, value_str]
