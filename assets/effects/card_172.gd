extends "res://scripts/effects/card_effect.gd"
## 1-172C Moogle


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 2)
	await ctx.discard(ctx.owner_id, 1)


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
