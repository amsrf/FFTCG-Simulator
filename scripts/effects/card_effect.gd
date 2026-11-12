extends RefCounted
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const DAMAGE_CONTEXT := preload("res://scripts/effects/damage_context.gd")
const BREAK_CONTEXT := preload("res://scripts/effects/break_context.gd")
const ABILITY_SPEC := preload("res://scripts/effects/ability_spec.gd")
const COST_CONTEXT := preload("res://scripts/effects/cost_context.gd")
const EVENTS := preload("res://scripts/effects/events.gd")
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TRIGGER_SPEC := preload("res://scripts/effects/trigger_spec.gd")
const TRIGGER_TEXT := preload("res://scripts/effects/trigger_text.gd")
const TARGET_CONTEXT := preload("res://scripts/effects/target_context.gd")
## The engine-facing contract for code-defined card behavior.
##
## A card effect is STATELESS: the per-event state lives in the EffectContext passed to the hook. One instance can be
## cached per card id and shared by every copy of that card.
##
## There are three kinds of hook:
##   * auto-abilities     -- one TriggerSpec per printed "When ..." ability in trigger_specs(); the engine puts ONE
##                           stack object per ability on the stack and calls dispatch() with that ability's index
##   * continuous queries -- normal calls (current_elements, modify_cost, ...) made whenever the engine needs an answer
##   * replacement hooks  -- intercept something before it happens (future work)
##
## This file deliberately contains no card logic. A card subclass overrides only the hooks it needs.

## THE AUTO-ABILITY DECLARATION. One TriggerSpec per printed auto-ability, in PRINTED ORDER:
##
##   func trigger_specs() -> Array:
##       return [
##           trigger(EVENTS.Event.ENTER_FIELD, "play_fire_forward"),   # 1st "When Gadot enters the field"
##           trigger(EVENTS.Event.ENTER_FIELD, "pump_forwards"),       # 2nd "When Gadot enters the field"
##       ]
##
## Two specs may share an event: each one is its own ability and becomes its own stack object. Optional filters on the
## spec (card(), to_zone(), owner_only(), active_only()) are evaluated by the engine BEFORE the stack object exists.
## The method names are free; the spec is what pairs the event with its handler.
func trigger_specs() -> Array:
	return []


## Convenience builder used by card scripts:
##   trigger(EVENTS.Event.CARD_LEFT_FIELD, "on_left").card(...).to_zone(...)
func trigger(event: int, method: String):
	return TRIGGER_SPEC.new(event, Callable(self, method))


## THE ONE LIST the engine reads. An ability's position in it is its identity: the stack copy stores that index and
## dispatch() runs exactly that entry, so two abilities on the same event can never be confused.
func auto_abilities() -> Array:
	var out: Array = []
	for spec in trigger_specs():
		if spec != null:
			out.append(spec)
	return out


## Indices (into auto_abilities()) of the abilities this event triggers. With an EventContext the spec's filters are
## evaluated (board events); without one only the event id is compared (the card's own events: enter, attack, ...).
func triggered_abilities(event: int, event_ctx = null, source = null) -> Array[int]:
	var out: Array[int] = []
	var abilities: Array = auto_abilities()
	for i in range(abilities.size()):
		var spec = abilities[i]
		if spec.event != event:
			continue
		if event_ctx != null and not spec.accepts(source, event_ctx):
			continue
		out.append(i)
	return out


func handles_event(event: int) -> bool:
	for spec in auto_abilities():
		if spec.event == event:
			return true
	return false


## What auto-ability `index` says on its stack card: the EFFECT, without the trigger that caused it. The spec's own
## .text() wins; otherwise it is the printed ability for that event, counting abilities that share the event in printed
## order (Gadot's second ENTER_FIELD spec is his second "When Gadot enters the field" sentence). "" = no match.
func stack_text(printed: String, index: int) -> String:
	var abilities: Array = auto_abilities()
	if index < 0 or index >= abilities.size():
		return ""
	var spec = abilities[index]
	if not spec.wording.is_empty():
		return spec.wording
	var nth := 0
	for i in range(index):
		if abilities[i].event == spec.event:
			nth += 1
	return TRIGGER_TEXT.for_event(printed, spec.event, nth)


## Run one auto-ability. `index` is the ability's position in auto_abilities() (the stack copy carries it); a negative
## index means "the first ability on this event", for callers that have no stack copy (a Summon's CAST).
func dispatch(event: int, ctx: EFFECT_CONTEXT, index: int = -1) -> void:
	var abilities: Array = auto_abilities()
	if index < 0:
		for i in range(abilities.size()):
			if abilities[i].event == event:
				index = i
				break
	if index < 0 or index >= abilities.size():
		return
	var spec = abilities[index]
	if spec.event != event:
		push_error("CardEffect.dispatch: ability %d is event %d, not %d" % [index, spec.event, event])
		return
	if spec.handler.is_valid():
		await spec.handler.call(ctx)


## What this Summon asks the player to choose WHEN CAST, before it enters the stack. Return a Dictionary for one
## target, an Array for staged targets, or {} for no target. The picks are stored on the card and passed to
## when_cast() as ctx.targets at resolution.
func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return {}


## Conditional power rules this card applies to itself. Each rule is
## { "value": int, "condition": Callable(source) -> bool }.
func conditional_powers() -> Array:
	return []


## Does this card's controller control a card matching `criteria`? Relative controller words resolve against
## `source`'s controller, which is what "you" means on a card.
func controls(source: Card, criteria: CARD_QUERY) -> bool:
	var field = source.get_parent()
	if field == null or not field.has_method("controls_matching"):
		return false
	return field.controls_matching(source.controller, criteria.to_block(), source)



## This card's own dynamic power contribution. Called from the continuous scan with a read-only context.
func power_modifier(_ctx: EFFECT_CONTEXT) -> int:
	return 0


## Dynamic properties this card currently has, in addition to printed keywords and granted statuses.
func properties(_ctx: EFFECT_CONTEXT) -> Array[String]:
	return []


## Static, card-local flags. Each reader asks only the flag it needs; no rule dictionary is involved.
func has_all_jobs() -> bool:
	return false


func disables_ex_burst() -> bool:
	return false


func exiles_break_zone() -> bool:
	return false


func light_dark_exemption() -> String:
	return ""


func produces_any_element() -> bool:
	return false


func grants_party_brave() -> bool:
	return false


## Combat legality owned by the card itself. `allows_blocker` is asked of the attacker; `can_block_attacker` is asked
## of the blocker. Both default to legal, so only restricting cards override them.
func allows_blocker(_owner: Card, _blocker: Card) -> bool:
	return true


func can_block_attacker(_owner: Card, _attacker: Card) -> bool:
	return true


## Choice/targeting protection and priority. `TARGET_CONTEXT` carries the candidate, the effect source and the effect
## kind, so each card answers the question it actually prints instead of sharing a rule dictionary.
func prevents_being_chosen(_ctx: TARGET_CONTEXT) -> bool:
	return false


func must_be_chosen(_ctx: TARGET_CONTEXT) -> bool:
	return false


func prevents_return_to_hand(_ctx: TARGET_CONTEXT) -> bool:
	return false


## A shielding card protects ANOTHER card. The context's `rule_owner` is this card and `candidate` is the card being
## chosen.
func shields_from_choice(_ctx: TARGET_CONTEXT) -> bool:
	return false


## Replacement/continuous rule applied after another Character enters the field.
func on_character_enter(_entering: Card, _ctx: EFFECT_CONTEXT) -> void:
	pass


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
func current_elements(_ctx: EFFECT_CONTEXT, card: Card) -> Array[String]:
	return [card.element]

## Change the cost of THIS card (self-modifiers such as "if you control Ovelia, this costs 1 less").
func modify_cost(_ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	return cost


## Change what ANOTHER card costs while this source is on the field ("your Water Summons cost 1 less").
func modify_cost_for(_ctx: COST_CONTEXT, _subject: Card, cost: Dictionary) -> Dictionary:
	return cost

## Change incoming damage before it lands.
func modify_damage(ctx: DAMAGE_CONTEXT) -> int:
	return ctx.amount


## Replace a break: return true to stop it. The default protects nothing.
func prevents_break(_ctx: BREAK_CONTEXT) -> bool:
	return false


## The colour this source generates when selected for mana. One colour returns immediately; a card that can
## produce several asks through the context's crystal circle.
func generate_mana(ctx: EFFECT_CONTEXT) -> String:
	return str(await ctx.choose_crystal_in_circle(ctx.source.mana_elements()))
