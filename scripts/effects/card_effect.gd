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

## Event names this effect wants on the stack. Keep the names identical to the engine's event vocabulary.
func triggered_events() -> Array[String]:
	return []

## Criteria for targets chosen when the trigger is put on the stack. Return null for an untargeted effect. The
## engine requests these before resolution, so the normal targeting UI/agent path and the arrow source are preserved.
func target_criteria(_event: String):
	return null


## True when this effect wants to be called for `event`. Used by Field.execute_card_effect before anything is queued.
func handles_event(event: String) -> bool:
	return event in triggered_events()

## Dispatch one event to its hook. Kept in one place so the engine never needs a growing match statement.
func dispatch(event: String, ctx) -> void:
	match event:
		"when_enter_field":
			await on_enter_field(ctx)
		"when_attack":
			await on_attack(ctx)
		"when_cast":
			await on_cast(ctx)
		"when_blocks":
			await on_blocks(ctx)
		"when_blocked":
			await on_blocked(ctx)
		"when_damage_to_player":
			await on_damage_to_player(ctx)
		"attack_phase_start":
			await on_attack_phase_start(ctx)
		"when_party_attack":
			await on_party_attack(ctx)
		"when_party_attacks":
			await on_party_attacks(ctx)
		"when_party_deals_damage":
			await on_party_deals_damage(ctx)
		"when_enter_break_from_field":
			await on_enter_break_from_field(ctx)
		"when_break":
			await on_break(ctx)
		_:
			push_warning("[CardEffect] no dispatch for event '%s'" % event)

# ---------------------------------------------------------------------------------------------------------------
# Triggered events
# ---------------------------------------------------------------------------------------------------------------

func on_enter_field(_ctx) -> void:
	pass

func on_attack(_ctx) -> void:
	pass

func on_cast(_ctx) -> void:
	pass

func on_blocks(_ctx) -> void:
	pass

func on_blocked(_ctx) -> void:
	pass

func on_damage_to_player(_ctx) -> void:
	pass

func on_attack_phase_start(_ctx) -> void:
	pass

func on_party_attack(_ctx) -> void:
	pass

func on_party_attacks(_ctx) -> void:
	pass

func on_party_deals_damage(_ctx) -> void:
	pass

func on_enter_break_from_field(_ctx) -> void:
	pass

func on_break(_ctx) -> void:
	pass

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
