extends RefCounted
const ABILITY_SPEC := preload("res://scripts/effects/ability_spec.gd")
const AURA_SPEC := preload("res://scripts/effects/aura_spec.gd")
const COST_CONTEXT := preload("res://scripts/effects/cost_context.gd")
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


## What this Summon asks the player to choose WHEN CAST, before it enters the stack. Return a Dictionary for one
## target, an Array for staged targets, or {} for no target. The picks are stored on the card and passed to
## when_cast() as ctx.targets at resolution.
func cast_target_criteria(_ctx) -> Variant:
	return {}


## Conditional power rules this card applies to itself. Each rule is
## { "value": int, "condition": Callable(source) -> bool }.
func conditional_powers() -> Array:
	return []


## Does this card's controller control a card matching `criteria`? Relative controller words resolve against
## `source`'s controller, which is what "you" means on a card.
func controls(source: Card, criteria: Dictionary) -> bool:
	var field = source.get_parent()
	if field == null or not field.has_method("controls_matching"):
		return false
	return field.controls_matching(source.controller, criteria, source)


## Count-based continuous power rules. Each rule:
## { "count": Dictionary-or-"damage_received", "value": int, "brave_at": int (optional) }.
func power_per_rules() -> Array:
	return []


## Which existing hook runs when this card becomes damage. The default is "no EX BURST"; only cards that have one
## override this and return "when_cast" or "when_enter_field". It is a pointer to the card's existing effect, never a
## second implementation.
func ex_burst_event() -> String:
	return ""


## Printed keywords owned by code. The keyword readers on Card ask this before the JSON view; migrate one keyword
## family at a time without changing the readers.
func keywords() -> Array[String]:
	return []


## Activated abilities this card offers. Event methods are zero-or-one per event; a card may have several activated
## abilities, and each one carries its own costs and target timing, so they get a descriptor.
func activated_abilities() -> Array:
	return []


func _ability(data: Dictionary) -> RefCounted:
	return ABILITY_SPEC.new(data)


## Continuous effects this card grants while it is on the field. Unlike activated_abilities(), these are not chosen
## or paid for; Field applies them to every matching card and keeps the teardown ledger.
func auras() -> Array:
	return []


func _aura(data: Dictionary) -> RefCounted:
	return AURA_SPEC.new(data)


# ---------------------------------------------------------------------------------------------------------------
# Continuous queries
# ---------------------------------------------------------------------------------------------------------------

## Elements the card currently has. The base implementation returns only its printed element; a subclass adds or
## replaces it. The engine calls this through Card.current_elements().
func current_elements(_ctx, card) -> Array[String]:
	return [card.element]

## Change the cost of THIS card (self-modifiers such as "if you control Ovelia, this costs 1 less").
func modify_cost(_ctx, _card, cost: Dictionary) -> Dictionary:
	return cost


## Change what ANOTHER card costs while this source is on the field ("your Water Summons cost 1 less").
func modify_cost_for(_ctx, _subject: Card, cost: Dictionary) -> Dictionary:
	return cost

## Change incoming damage before it lands.
func modify_damage(_ctx, _target, amount: int) -> int:
	return amount
