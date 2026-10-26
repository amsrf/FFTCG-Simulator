extends "res://scripts/effects/card_effect.gd"
## 1-126 Orlandeau: when it attacks, deal 3000 to every opponent Forward.


func when_attack(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 3000)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Lightning》《Lightning》: Orlandeau gains Haste until the end of the turn.",
			"cost": {"雷": 2},
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "haste", 1)