extends "res://scripts/effects/card_effect.gd"
## 5-121R Andoria: when a party you control deals damage, draw 1.


func when_party_deals_damage(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
