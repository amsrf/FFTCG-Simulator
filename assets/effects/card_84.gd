extends "res://scripts/effects/card_effect.gd"
## 1-084H Y'shtola

func activated_abilities() -> Array:
	return [
		_ability({"text": "《風》: Choose 1 Forward. Deal it 1000 damage.", "cost": {"風": 1}, "targets": {"is_type": "Forward"}, "run": Callable(self, "_wind")}),
		_ability({"text": "《Dull》: Choose 1 Forward. Deal it 2000 damage.", "cost": {}, "tap": true, "targets": {"is_type": "Forward"}, "run": Callable(self, "_dull")}),
	]

func _wind(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func _dull(ctx) -> void:
	ctx.damage(ctx.targets, 2000)
