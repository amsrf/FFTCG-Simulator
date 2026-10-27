extends "res://scripts/effects/card_effect.gd"
const BREAK_CAUSE := preload("res://scripts/effects/break_cause.gd")
## Auron 1-002H: your Backups cannot be broken by opponent Summons or abilities.


func prevents_break(ctx) -> bool:
	if not ctx.card.is_type("Backup"):
		return false
	if ctx.card.controller != ctx.rule_owner.controller:
		return false
	if not ctx.caused_by_opponent():
		return false
	return ctx.cause_is(BREAK_CAUSE.Kind.SUMMON) or ctx.cause_is(BREAK_CAUSE.Kind.ABILITY)
