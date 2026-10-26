extends "res://scripts/effects/card_effect.gd"
## 1-074R Sylph


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward"})
	ctx.untap(targets)
	ctx.power_change(ctx.cards_in("field", {"is_type": "Forward", "controller": "player"}), 1000, 1)
