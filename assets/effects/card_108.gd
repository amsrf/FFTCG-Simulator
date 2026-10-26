extends "res://scripts/effects/card_effect.gd"

func event_matches(event: String, source: Card, data: Dictionary) -> bool:
	return event == "damage_received" and int(data.get("player_id", 0)) == (1 if source.controller == "player" else 2)


func damage_received(ctx) -> void:
	if not await ctx.may("Deal 5000 damage"):
		return
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "controller": "opponent"})
	ctx.damage(targets, 5000)
