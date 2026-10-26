extends "res://scripts/effects/card_effect.gd"
## 5-134R Celestia: when a party you control attacks, that party gains +1000.


func when_party_attacks(ctx) -> void:
	ctx.power_change_party(1000, 1)
