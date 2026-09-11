extends Agent
class_name MockAgent
## Placeholder opponent: passes after a short delay, never attacks, never
## blocks. Preserves the behaviour from before turn alternation existed, so the
## turn structure can be tested without a real AI.

var think_time: float = 0.5

func take_priority(_player_id: int) -> void:
	await game.get_tree().create_timer(think_time).timeout

func decide_attacker(_player_id: int) -> Card:
	return null

func decide_blocker(_player_id: int, _attacker: Card) -> Card:
	return null
