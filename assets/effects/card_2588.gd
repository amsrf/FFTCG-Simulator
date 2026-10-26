extends "res://scripts/effects/card_effect.gd"
## 4-062C Chocobo: when it forms a party and attacks, the party gains +3000.


func when_party_attack(ctx) -> void:
	ctx.power_change_party(3000, 1)
