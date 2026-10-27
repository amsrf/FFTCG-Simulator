extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 9-006H Queen of Eblan


func when_party_attack(ctx) -> void:
	if not ctx.condition("party_has_named:King of Eblan"):
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.damage(targets, 5000)
