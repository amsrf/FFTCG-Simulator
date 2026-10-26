extends "res://scripts/effects/card_effect.gd"
## 1-131R Cait Sith


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Backup", "is_cost_at_most": 1})
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Slots 《S》《Lightning》《Dull》: Remove the top card of your deck from the game. If it is a Forward, deal 7000 damage to all active Forwards opponent controls.",
			"cost": {"雷": 1},
			"tap": true,
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.reveal_top(1)
	if ctx.check_revealed(0, {"is_type": "Forward"}):
		ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent", "is_tapped": false}), 7000)
	ctx.remove_revealed_from_game(0)