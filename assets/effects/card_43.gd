extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-043H Snow


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ATTACK, "when_attack"),
	]


func when_attack(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	if ctx.condition("cast_this_turn:Shiva"):
		ctx.add_status(targets, "frozen", 1)
