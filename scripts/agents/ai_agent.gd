extends MockAgent
class_name AIAgent
## Phase 3 stub. Real heuristics (play cards, attack when profitable, block
## when it matters) land here; until then it behaves exactly like MockAgent so
## `config["opponent_type"] = "ai"` is safe to select.

func _init() -> void:
	think_time = 0.35
