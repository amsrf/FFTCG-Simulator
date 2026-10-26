extends "res://scripts/effects/card_effect.gd"
## 1-205S Barret


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Grenade Bomb 《S》: Deal 2000 damage to all opponent Forwards.",
			"s_cost": true,
			"cost": {},
			"run": Callable(self, "_damage_all_opponent_forwards"),
		}),
	]

func _damage_all_opponent_forwards(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 2000)

