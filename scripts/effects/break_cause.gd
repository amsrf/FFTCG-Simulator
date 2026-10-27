extends RefCounted
## What is causing a card to break. Kept separate from DamageContext because a break can come from an effect that
## never dealt damage (break_targets, a destruction replacement, ...).

enum Kind {
	COMBAT,
	DAMAGE,
	ABILITY,
	SUMMON,
	EFFECT,
	OTHER,
}

var kind: int = Kind.OTHER
var source: Card = null
var source_controller: String = ""
## Legacy Summon/Ability marker from the break caller.
var source_kind: String = ""


func is_opponent_of(protector: Card) -> bool:
	if protector == null:
		return false
	if source_controller != "":
		return source_controller != protector.controller
	return source != null and is_instance_valid(source) and source.controller != protector.controller


func kind_name() -> String:
	match kind:
		Kind.COMBAT:
			return "combat"
		Kind.DAMAGE:
			return "damage"
		Kind.ABILITY:
			return "ability"
		Kind.SUMMON:
			return "summon"
		Kind.EFFECT:
			return "effect"
		_:
			return "other"
