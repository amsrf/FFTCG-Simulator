extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-043H Snow


func when_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	if ctx.condition("cast_this_turn:Shiva"):
		ctx.add_status(targets, "frozen", 1)
