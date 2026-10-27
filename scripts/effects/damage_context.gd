extends RefCounted
## One damage event, as seen by every card that wants to modify it.
##
## A card's `modify_damage(ctx)` is a pure query: read the event, return the new amount. The rule owner is the card
## whose method is running, which is what lets field-wide replacement effects (Knight, Minwu) see damage dealt to
## another card.

enum Kind {
	COMBAT,
	ABILITY,
	SUMMON,
	EX_BURST,
	EFFECT,
}

var amount: int = 0
var original_amount: int = 0
var source: Card = null
var source_controller: String = ""
## Legacy Summon/Ability marker used by older condition data.
var source_kind: String = ""
var target: Card = null
var kind: int = Kind.EFFECT
var rule_owner: Card = null
var field: Node = null


func source_is_owner() -> bool:
	return source != null and source == rule_owner


func target_is_owner() -> bool:
	return target != null and target == rule_owner


func target_in_party_with_owner() -> bool:
	if field == null or rule_owner == null or target == null:
		return false
	if not field.has_method("party_members"):
		return false
	var members: Array = field.party_members()
	return members.has(rule_owner) and members.has(target)


func kind_name() -> String:
	match kind:
		Kind.COMBAT:
			return "combat"
		Kind.ABILITY:
			return "ability"
		Kind.SUMMON:
			return "summon"
		Kind.EX_BURST:
			return "ex_burst"
		_:
			return "effect"
