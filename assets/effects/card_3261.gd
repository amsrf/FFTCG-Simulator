extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 9-006H Queen of Eblan


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.PARTY_ATTACK, "when_party_attack"),
	]


func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	if not ctx.condition("party_has_named:King of Eblan"):
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.damage(targets, 5000)
