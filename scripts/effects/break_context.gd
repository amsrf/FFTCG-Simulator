extends RefCounted
const BREAK_CAUSE := preload("res://scripts/effects/break_cause.gd")
## One break event, seen by every card that may replace it. `rule_owner` is the protector whose method is running;
## `card` is the card that would otherwise break.

var card: Card = null
var rule_owner: Card = null
var cause: BREAK_CAUSE = null
var field: Node = null


func cause_is(kind: int) -> bool:
	return cause != null and cause.kind == kind


func caused_by_opponent() -> bool:
	return cause != null and cause.is_opponent_of(rule_owner)
