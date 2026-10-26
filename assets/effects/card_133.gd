extends "res://scripts/effects/card_effect.gd"
## 1-133 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.break_zone_to_hand({"any": [{"type": "Forward"}, {"type": "Backup"}]})
