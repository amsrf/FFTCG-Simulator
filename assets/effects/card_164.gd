extends "res://scripts/effects/card_effect.gd"
## 1-164 Tidus: when it attacks, your Water Forwards gain +1000.


func when_attack(ctx) -> void:
	ctx.power_change(ctx.cards_in("field", {"is_type": "Forward", "controller": "your",
		"is_element": "水"}), 1000, 1)
