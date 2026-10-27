extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 12-087H Mid Previa
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACKS: Callable(self, "when_party_attacks"),
	}


func when_party_attacks(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).tapped(false)))
	if targets.is_empty():
		return
	ctx.damage(targets, 8000)
