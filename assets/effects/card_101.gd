extends "res://scripts/effects/card_effect.gd"
## 1-101 enter-the-field ability


func when_enter_field(ctx) -> void:
	ctx.power_change(ctx.cards_in("field", {"is_type": "Forward", "controller": "your"}), 4000, 1)
