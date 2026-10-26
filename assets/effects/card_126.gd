extends "res://scripts/effects/card_effect.gd"
## 1-126 Orlandeau: when it attacks, deal 3000 to every opponent Forward.


func when_attack(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 3000)
