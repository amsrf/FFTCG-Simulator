extends "res://scripts/effects/card_effect.gd"
## 1-037 Kuja: when chosen by the opponent, they discard 1.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CHOSEN: Callable(self, "when_chosen"),
	}


func when_chosen(ctx) -> void:
	await ctx.opponent_discards(1)
