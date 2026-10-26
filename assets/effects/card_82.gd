extends "res://scripts/effects/card_effect.gd"
## 1-082R Hope


func when_enter_field(ctx) -> void:
	if ctx.condition("cast_this_turn:Alexander"):
		ctx.untap_all_matching({"is_type": "Backup", "controller": "player"})
		return
	var targets: Array = await ctx.choose_targets({"is_type": "Backup", "controller": "player"})
	ctx.untap(targets)
