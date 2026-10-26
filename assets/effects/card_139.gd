extends "res://scripts/effects/card_effect.gd"
## 1-139C Summoner


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》, put Summoner into the Break Zone: Cast 1 Summon of cost 6 or less from your hand for free.",
			"cost": {},
			"tap": true,
			"sacrifice": {"is_source": true},
			"run": Callable(self, "_free_summon"),
		}),
	]

func _free_summon(ctx) -> void:
	await ctx.cast_summon_for_free({"is_type": "Summon", "is_cost_at_most": 6})

