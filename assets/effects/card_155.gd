extends "res://scripts/effects/card_effect.gd"
## 1-155R Warrior of Light


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_job": "Standard Unit"},
			"method": "power_change",
			"value": 2000,
		}),
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_job": "Standard Unit"},
			"method": "grant_status",
			"status": "first_strike",
		}),
	]
