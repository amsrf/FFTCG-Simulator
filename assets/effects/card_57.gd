extends "res://scripts/effects/card_effect.gd"
## 1-057C


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_element": "氷"},
			"method": "power_change",
			"value": 1000,
		}),
	]
