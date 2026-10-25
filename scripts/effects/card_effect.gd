extends RefCounted
## The engine-facing contract for code-defined card behavior.
##
## A card effect is STATELESS: the per-event state lives in the EffectContext passed to the hook. One instance can be
## cached per card id and shared by every copy of that card.
##
## There are three kinds of hook:
##   * triggered events   -- declare the event in triggered_events(); the engine puts a stack object on the stack and
##                           calls the matching on_* method when it resolves
##   * continuous queries -- normal calls (current_elements, modify_cost, ...) made whenever the engine needs an answer
##   * replacement hooks  -- intercept something before it happens (future work)
##
## This file deliberately contains no card logic. A card subclass overrides only the hooks it needs.

## EVENT METHODS ARE THE CONTRACT. A card defines a method named exactly like the engine event it handles, e.g.
## `func when_enter_field(ctx)`. The engine asks `has_method(event)` and, at resolution, calls that same method.
## There is no separate event list and no name mapping, so there is nothing to drift.
func handles_event(event: String) -> bool:
	return has_method(event)


# ---------------------------------------------------------------------------------------------------------------
# Continuous queries
# ---------------------------------------------------------------------------------------------------------------

## Elements the card currently has. The base implementation returns only its printed element; a subclass adds or
## replaces it. The engine calls this through Card.current_elements().
func current_elements(_ctx, card) -> Array[String]:
	return [card.element]

## Change a cost. Return the same dictionary shape.
func modify_cost(_ctx, _card, cost: Dictionary) -> Dictionary:
	return cost

## Change incoming damage before it lands.
func modify_damage(_ctx, _target, amount: int) -> int:
	return amount
