extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")

func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.DAMAGE_RECEIVED, "damage_received").owner_only(),
	]


func damage_received(ctx: EFFECT_CONTEXT) -> void:
	if not await ctx.may("Deal 5000 damage"):
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	ctx.damage(targets, 5000)
