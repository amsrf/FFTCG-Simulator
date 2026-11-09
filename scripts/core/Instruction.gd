class_name Instruction
extends RefCounted  # Lightweight reference-counted base class

var action: String      # e.g., "destroy", "draw", "tap"
var executor: String    # e.g., "card", "hand", "game_manager"
var value    # e.g., 2 (damage amount, cards to draw)
## Optional guard, set from the card data's "condition" key. Today the only one is "if_last_succeeded": run this
## instruction only if the previous one reported success (e.g. "search ... and if you do so, return Vanille").
## Empty means run unconditionally, which is every instruction written before this existed.
var condition: String = ""

## OPTIONAL INSTRUCTION ("you may ..."). The choice is made when the instruction is REACHED, i.e. at resolution and
## after targets are locked. `may_by == "opponent"` hands the decision to the other player (Leon 60), and
## `may_prompt` is the confirm button's short text ("Deal 6000").
var may: bool = false
var may_by: String = ""
var may_prompt: String = ""

func _init(p_action: String, p_executor: String, p_value = null, p_condition: String = "",
		p_may: bool = false, p_may_by: String = "", p_may_prompt: String = ""):
	action = p_action
	executor = p_executor
	value = p_value
	condition = p_condition
	may = p_may
	may_by = p_may_by
	may_prompt = p_may_prompt

func _to_string() -> String:
	var value_str = str(value) if value != null else "null"
	return "[Instruction: %s -> %s (value: %s)]" % [executor, action, value_str]
