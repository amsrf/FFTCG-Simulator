extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 21-021C Red Mage


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.PARTY_ATTACK, "when_party_attack"),
	]


func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().character(true)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)
