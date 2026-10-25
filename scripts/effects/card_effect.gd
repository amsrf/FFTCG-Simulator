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

## One spec per event this effect handles. A spec carries the event name and the Callable that implements it, so
## there is no separate event list that can drift from the hooks. Each hook chooses its own targets (auto-abilities
## choose at resolution) and is therefore self-contained.
func event_specs() -> Array:
	return []


func spec_for(event: String) -> Dictionary:
	for spec in event_specs():
		if spec is Dictionary and str(spec.get("event", "")) == event:
			return spec
	return {}


## True when this effect wants to be called for `event`.
func handles_event(event: String) -> bool:
	return not spec_for(event).is_empty()


## Small constructor for event_specs(). The hook is a Callable because the engine invokes it later, when the stack
## object resolves.
func _event(event_name: String, hook: Callable) -> Dictionary:
	return {"event": event_name, "run": hook}


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
