extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-062L Valefor


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	await ctx.return_to_hand(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward")))
