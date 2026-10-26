extends "res://scripts/effects/card_effect.gd"
## 1-001H Auron


func when_cause_damage_to_player(ctx) -> void:
	await ctx.may_play_from_hand({
		"is_type": "Backup",
		"is_element": "火",
	}, true, "Play a Fire Backup")
