extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 13-095C Tonogiri
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.PARTY_ATTACK, "when_party_attack"),
	]


func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	await ctx.return_to_hand(targets)
