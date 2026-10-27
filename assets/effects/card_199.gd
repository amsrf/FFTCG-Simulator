extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-199 enter-the-field ability


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.YOUR)).up_to(3))
	if targets.is_empty():
		return
	if ctx.condition("controls:Yuna"):
		ctx.draw(ctx.owner_id, 1)
	if ctx.condition("controls:Rikku"):
		ctx.untap(targets)
