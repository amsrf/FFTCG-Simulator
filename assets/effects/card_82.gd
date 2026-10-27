extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-082R Hope


func when_enter_field(ctx) -> void:
	if ctx.condition("cast_this_turn:Alexander"):
		ctx.untap_all_matching({"is_type": "Backup", "controller": "player"})
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER)))
	ctx.untap(targets)
