extends "res://scripts/effects/card_effect.gd"
## 1-083R


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player"},
			"method": "power_change",
			"value": 1000,
		}),
	]
