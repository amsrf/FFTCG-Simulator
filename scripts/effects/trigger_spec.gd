extends RefCounted
## One declarative trigger subscription.
##
## The engine evaluates this BEFORE putting an ability on the stack, so a card
## no longer needs an event_matches() method. The filter is always about the
## event card, relative to the card that owns the trigger.
const EVENT_CONTEXT := preload("res://scripts/effects/event_context.gd")

enum PlayerScope {
	ANY,
	OWNER,
	OPPONENT,
}

var event: int = -1
var handler: Callable
var card_filter = null
var destination: int = -1
var player_scope: int = PlayerScope.ANY
var requires_active: bool = false
## What the stack face says. Empty = derived from the printed text (TriggerText); set it with .text() only when the
## printed wording does not parse.
var wording: String = ""


func _init(p_event: int, p_handler: Callable) -> void:
	event = p_event
	handler = p_handler


## Only accept events whose affected card matches this query.
func card(filter):
	card_filter = filter
	return self


## Only accept a card leaving to this destination (Card.Zone).
func to_zone(zone: int):
	destination = zone
	return self


func for_player(scope: int):
	player_scope = scope
	return self


func owner_only():
	player_scope = PlayerScope.OWNER
	return self


func opponent_only():
	player_scope = PlayerScope.OPPONENT
	return self


func active_only():
	requires_active = true
	return self


## Override the stack face's wording for this ability (the printed text did not parse).
func text(value: String):
	wording = value
	return self


func accepts(source: Card, ctx: EVENT_CONTEXT) -> bool:
	if event != ctx.event:
		return false
	if requires_active and source != null and source.tapped:
		return false
	if destination >= 0 and ctx.to_zone != destination:
		return false
	if card_filter != null:
		if ctx.card == null or not is_instance_valid(ctx.card):
			return false
		if not ctx.card.matches_criteria(card_filter.to_block(), source):
			return false
	if player_scope != PlayerScope.ANY:
		var owner_id: int = 1 if source != null and source.controller == Card.PLAYER else 2
		var wanted: int = owner_id if player_scope == PlayerScope.OWNER else 3 - owner_id
		if ctx.player_id != wanted:
			return false
	return true
