extends "res://scripts/effects/card_effect.gd"
## 1-199 enter-the-field ability


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Backup", "controller": "your"}, 3)
	if targets.is_empty():
		return
	if ctx.condition("controls:Yuna"):
		ctx.draw(ctx.owner_id, 1)
	if ctx.condition("controls:Rikku"):
		ctx.untap(targets)
