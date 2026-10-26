extends "res://scripts/effects/card_effect.gd"
## 1-113: when this card blocks, it gains +2000.


func when_blocks(ctx) -> void:
	ctx.power_change([ctx.source], 2000, 1)
