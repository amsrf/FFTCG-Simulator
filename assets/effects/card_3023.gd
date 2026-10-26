extends "res://scripts/effects/card_effect.gd"
## 7-054L Chelinka


func when_party_attack(ctx) -> void:
	if not ctx.condition("party_has_named:Yuri"):
		return
	var targets: Array = await ctx.choose_targets({"is_type_any": ["Forward", "Monster"]})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
