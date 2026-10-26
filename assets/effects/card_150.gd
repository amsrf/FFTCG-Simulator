extends "res://scripts/effects/card_effect.gd"
## 1-150R Lulu


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_element": "雷"},
			"method": "power_change",
			"value": 1000,
		}),
	]
