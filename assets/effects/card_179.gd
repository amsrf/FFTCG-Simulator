extends "res://scripts/effects/card_effect.gd"
## 1-179: when this card deals damage to the opponent, draw 1.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER: Callable(self, "when_cause_damage_to_player"),
	}


func when_cause_damage_to_player(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
