extends RefCounted
const ABILITY_SPEC := preload("res://scripts/effects/ability_spec.gd")
const COST_CONTEXT := preload("res://scripts/effects/cost_context.gd")
const EVENTS := preload("res://scripts/effects/events.gd")
## The engine-facing contract for code-defined card behavior.
##
## A card effect is STATELESS: the per-event state lives in the EffectContext passed to the hook. One instance can be
## cached per card id and shared by every copy of that card.
##
## There are three kinds of hook:
##   * triggered events   -- declare event -> method in handlers(); the engine puts a stack object on the stack and
##                           calls dispatch() with that event when it resolves
##   * continuous queries -- normal calls (current_elements, modify_cost, ...) made whenever the engine needs an answer
##   * replacement hooks  -- intercept something before it happens (future work)
##
## This file deliberately contains no card logic. A card subclass overrides only the hooks it needs.

## THE TRIGGER DECLARATION. A card that handles an event puts exactly one entry here:
##
##   func handlers() -> Dictionary:
##       return { EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field") }
##
## The engine reads the KEYS before putting anything on the stack; dispatch() reads the Callable later. One entry
## answers both "should this trigger?" and "what runs?". The base is empty, so a card with no triggers costs nothing.
func handlers() -> Dictionary:
	return {}


func handles_event(event: int) -> bool:
	return handlers().has(event)


## One place maps the event id to the card's method. No has_method() lookup and no string method name at the call site.
func dispatch(event: int, ctx) -> void:
	var handler: Callable = handlers().get(event, Callable())
	if handler.is_valid():
		await handler.call(ctx)


## Optional event filter for code-defined triggers. The Field checks this before enqueueing the stack object, so a
## card can listen to a shared event (card_left_field, summon_cast, ...) without reacting to every instance of it.
func event_matches(_event: int, _source: Card, _data: Dictionary) -> bool:
	return true


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


## Static rule blocks owned by code (protections, shields, damage modifiers and similar). The readers ask
## Card.static_rule() key by key, so a card can move one family out of JSON at a time.
func static_rules() -> Dictionary:
	return {}


## This card's own dynamic power contribution. Called from the continuous scan with a read-only context.
func power_modifier(_ctx) -> int:
	return 0


## Dynamic properties this card currently has, in addition to printed keywords and granted statuses.
func properties(_ctx) -> Array[String]:
	return []


## Which existing hook runs when this card becomes damage. The default is "no EX BURST"; only cards that have one
## override this and return an Event id. It is a pointer to the card's existing effect, never a second implementation.
func ex_burst_event() -> int:
	return EVENTS.Event.NONE


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
func modify_damage(ctx) -> int:
	return ctx.amount
