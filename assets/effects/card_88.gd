extends "res://scripts/effects/card_effect.gd"
## 1-088C Archer


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《風》《風》《Dull》, put Archer into the Break Zone: Break 1 Backup of cost 3 or less.",
			"cost": {"風": 2},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Backup", "is_cost_at_most": 3},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.break_cards(ctx.targets)
