extends "res://scripts/effects/card_effect.gd"
## 1-154 enter-the-field ability


func when_enter_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
