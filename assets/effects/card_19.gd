extends "res://scripts/effects/card_effect.gd"
## 1-019C Black Mage


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《火》《Dull》: Choose 1 Fire Backup you control. Activate it.",
			"cost": {"火": 1},
			"tap": true,
			"targets": {"is_type": "Backup", "is_element": "Fire", "controller": "player"},
			"run": Callable(self, "_untap_target"),
		}),
	]

func _untap_target(ctx) -> void:
	ctx.untap(ctx.targets)

