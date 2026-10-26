extends "res://scripts/effects/card_effect.gd"
## 3-076 Chocobo: when it forms a party and attacks, the party gains +2000.


func when_party_attack(ctx) -> void:
	ctx.power_change_party(2000, 1)
