extends "res://scripts/effects/card_effect.gd"
## 1-198S Valefor


func when_cast(ctx) -> void:
	var forwards: Array = ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"})
	ctx.damage(forwards, 3000)
	if ctx.condition("controls:Yuna"):
		ctx.untap_all_matching({"is_type": "Backup", "controller": "player"})


func ex_burst_event() -> String:
	return "when_cast"
