extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-060 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	if await ctx.may_for(3 - ctx.owner_id, "Play a Character"):
		await ctx.play_from_hand(CARD_QUERY.new().character(true),  "opponent")
