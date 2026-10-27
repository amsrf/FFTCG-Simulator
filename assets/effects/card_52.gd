extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
const TARGET_SEQUENCE := preload("res://scripts/effects/target_sequence.gd")
## 1-052R Hades


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_SEQUENCE.new([TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.OPPONENT))])


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_SEQUENCE.new([
		TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)),
		TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.OPPONENT)),
	]))
	if targets.size() < 2:
		return
	ctx.dull([targets[0]])
	await ctx.return_to_hand([targets[1]])
	await ctx.opponent_discards(1)
