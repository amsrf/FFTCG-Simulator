extends "res://scripts/effects/card_effect.gd"
## 1-156C


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_job": "Knight"},
			"method": "power_change",
			"value": 1000,
		}),
	]
