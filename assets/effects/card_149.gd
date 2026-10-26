extends "res://scripts/effects/card_effect.gd"
## 1-149R Lulu


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》, put 1 Backup into the Break Zone: Choose 1 Forward. Deal it 5000 damage.",
			"cost": {},
			"tap": true,
			"sacrifice": {"is_type": "Backup", "controller": "player"},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_damage_5000"),
		}),
		_ability({
			"text": "Thundaga 《S》《Lightning》《Dull》: Choose 1 Forward. Deal it 10000 damage.",
			"s_cost": true,
			"cost": {"雷": 1},
			"tap": true,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_damage_10000"),
		}),
	]

func _damage_5000(ctx) -> void:
	ctx.damage(ctx.targets, 5000)

func _damage_10000(ctx) -> void:
	ctx.damage(ctx.targets, 10000)

