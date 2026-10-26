extends "res://scripts/effects/card_effect.gd"
## 12-058C Gippal: when a party you control attacks, that party gains +5000.


func when_party_attacks(ctx) -> void:
	ctx.power_change_party(5000, 1)
