extends RefCounted
## One continuous aura, as a typed object instead of a metadata dictionary.
##
## An aura has no cost, no stack object and no target choice. The engine scans the board, asks `matches()` for each
## card, and keeps a stable key so the grant can be revoked exactly once.
##
## A subclass supplies the query and the kind:
##
##   query = CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)
##   kind = KIND_POWER
##   value = 1000
##
## or:
##
##   kind = KIND_STATUS
##   status = "first_strike"

const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const CARD_TARGET := preload("res://scripts/card_target.gd")

const KIND_POWER := 0
const KIND_STATUS := 1

## null means every card on the field.
var query = null
var kind: int = KIND_POWER
var value: int = 0
var status: String = ""
## Optional predicate called with the source card; the aura is inactive while it returns false.
var condition: Callable


func matches(card: Card, source: Card) -> bool:
	if card == null:
		return false
	if condition.is_valid() and not bool(condition.call(source)):
		return false
	return CARD_TARGET.matches(card, target_block(), source)


func target_block() -> Dictionary:
	if query != null and query.has_method("to_block"):
		return query.to_block()
	return {}


func is_active(source: Card) -> bool:
	if condition.is_valid() and not bool(condition.call(source)):
		return false
	return true


## Bridge for the existing continuous-effect collector, which still speaks in `method`/`targets` entries.
func as_rule() -> Dictionary:
	return {
		"targets": target_block(),
		"method": "power_change" if kind == KIND_POWER else "grant_status",
		"value": value,
		"status": status,
		"condition": condition,
	}
