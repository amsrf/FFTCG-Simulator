extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-176H Yuna


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	await ctx.return_to_hand(targets)


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD

func exiles_break_zone() -> bool:
	return true
