extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-188R Zangan


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func auras() -> Array:

	return [Aura0.new()]

func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD

func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.search_deck(CARD_QUERY.new().name_contains("Tifa"))

class Aura0 extends "res://scripts/effects/aura.gd":
	func _init() -> void:
		query = CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER).named("Tifa").cost_at_most(4)
		kind = KIND_STATUS
		status = "haste"
