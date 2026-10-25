extends "res://scripts/effects/card_effect.gd"
## 1-167C Viking
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_enter_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
