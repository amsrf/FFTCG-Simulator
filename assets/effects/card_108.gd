extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")

func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.DAMAGE_RECEIVED, "damage_received").chooses(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT))).owner_only(),
	]


func damage_received(ctx: EFFECT_CONTEXT) -> void:
	# Printed order: choose 1 Forward, THEN "you may deal it 5000 damage".
	var targets: Array = await ctx.choose_trigger_targets()
	if targets.is_empty():
		return
	if await ctx.may("Deal 5000 damage"):
		ctx.damage(targets, 5000)
