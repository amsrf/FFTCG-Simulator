extends "res://scripts/effects/card_effect.gd"
## 1-113: when this card blocks, it gains +2000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.BLOCKS: Callable(self, "when_blocks"),
	}


func when_blocks(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change([ctx.source], 2000, 1)
