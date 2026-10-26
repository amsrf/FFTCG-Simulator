extends "res://scripts/effects/card_effect.gd"
## 1-168: when it enters the Break Zone from the field, draw 1.


func when_enter_break_from_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
