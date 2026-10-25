extends "res://scripts/effects/card_effect.gd"
## 1-145C Ramza
## 《Dull》: Choose 1 Backup. Activate it.


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: Choose 1 Backup. Activate it.",
			"cost": {},
			"tap": true,
			"targets": {"is_type": "Backup"},
			"run": Callable(self, "_activate_backup"),
		}),
	]


func _activate_backup(ctx) -> void:
	ctx.untap(ctx.targets)
