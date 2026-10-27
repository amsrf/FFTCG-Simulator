extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-186L Sephiroth


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup")))
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func keywords() -> Array[String]:
	return ["first_strike"]
