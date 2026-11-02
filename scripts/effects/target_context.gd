extends RefCounted
## Typed context for a choice/targeting question.
##
## `candidate` is the card someone is trying to choose; `source` is the card that
## owns the effect doing the choosing; `rule_owner` is the card whose continuous
## protection rule is being asked (usually the candidate, or a shielding card).
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")

var candidate: Card = null
var source: Card = null
var source_kind: String = ""
var rule_owner: Card = null


func _init(p_candidate: Card = null, p_source: Card = null, p_kind: String = "",
		p_rule_owner: Card = null) -> void:
	candidate = p_candidate
	source = p_source
	source_kind = p_kind
	rule_owner = p_rule_owner if p_rule_owner != null else p_candidate


func from_opponent() -> bool:
	if source == null or rule_owner == null:
		return false
	return source.controller != rule_owner.controller


func is_kind(kind: String) -> bool:
	return source_kind == kind


func kind_in(kinds: Array) -> bool:
	return kinds.is_empty() or source_kind in kinds


func controls(criteria: CARD_QUERY) -> bool:
	if rule_owner == null or criteria == null:
		return false
	var host: Node = rule_owner.get_parent()
	if host == null or not host.has_method("controls_matching"):
		return false
	return host.controls_matching(rule_owner.controller, criteria.to_block(), rule_owner)
