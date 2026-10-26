extends "res://scripts/effects/card_effect.gd"
## 1-179: when this card deals damage to the opponent, draw 1.


func when_cause_damage_to_player(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
