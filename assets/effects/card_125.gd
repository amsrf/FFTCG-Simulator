extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-125R Onion Knight
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field").chooses(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").damaged(true))),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_trigger_targets()
	if targets.is_empty():
		return
	ctx.damage(targets, 5000)
