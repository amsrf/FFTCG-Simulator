extends "res://scripts/effects/card_effect.gd"
## 1-052R Hades


func cast_target_criteria(_ctx) -> Variant:
	return [
		{"is_type": "Forward", "controller": "opponent"},
		{"is_type": "Backup", "controller": "opponent"},
	]


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets([
		{"is_type": "Forward", "controller": "opponent"},
		{"is_type": "Backup", "controller": "opponent"},
	])
	if targets.size() < 2:
		return
	ctx.dull([targets[0]])
	await ctx.return_to_hand([targets[1]])
	await ctx.opponent_discards(1)
