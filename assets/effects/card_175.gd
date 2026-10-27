extends "res://scripts/effects/card_effect.gd"
## 1-175 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
	await ctx.put_hand_card_on_bottom()
