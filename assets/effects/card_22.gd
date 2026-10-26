extends "res://scripts/effects/card_effect.gd"
## 1-022R Firion

func activated_abilities() -> Array:
	return [
		_ability({"text": "《1》: Firion gains First Strike until the end of the turn.", "cost": {"neutral": 1}, "run": Callable(self, "_first_strike")}),
		_ability({"text": "《1》: Firion gains Brave until the end of the turn.", "cost": {"neutral": 1}, "run": Callable(self, "_brave")}),
		_ability({"text": "《2》: Choose 1 Forward. Deal it 1000 damage.", "cost": {"neutral": 2}, "targets": {"is_type": "Forward"}, "run": Callable(self, "_ping")}),
		_ability({"text": "《2》: Firion gains +1000 power until the end of the turn.", "cost": {"neutral": 2}, "run": Callable(self, "_pump")}),
	]

func _first_strike(ctx) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)

func _brave(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)

func _ping(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func _pump(ctx) -> void:
	ctx.source.power_change(1000, 1)
