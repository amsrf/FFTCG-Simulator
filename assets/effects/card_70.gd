extends "res://scripts/effects/card_effect.gd"
## 1-070C Thief
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx) -> void:
	await ctx.mill(3 - ctx.owner_id, 1)
