extends "res://scripts/effects/card_effect.gd"
## 1-024 enter-the-field ability


func when_enter_field(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 3000)
