extends "res://scripts/effects/card_effect.gd"
## 1-116 Prishe: when this card blocks, it gains +4000.


func when_blocks(ctx) -> void:
	ctx.power_change([ctx.source], 4000, 1)
