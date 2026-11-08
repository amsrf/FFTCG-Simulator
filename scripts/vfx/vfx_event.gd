class_name VfxEvent
extends RefCounted
## One semantic presentation event. Rules code describes WHAT happened; the
## VfxDirector and element/status presets decide HOW it looks.
##
## This is intentionally data-only. Do not put scene instantiation or card rules
## in here.

enum Kind {
	STATUS_APPLIED,
	STATUS_REMOVED,
	DAMAGE,
	BOARD_DAMAGE,
	CARD_BROKEN,
	## A zone move or other board presentation. The rules have ALREADY changed the state; `presenter` only animates
	## it (reparent, fly, lay out). Run in queue order like every other event.
	PRESENT,
}

var kind: Kind = Kind.STATUS_APPLIED
var targets: Array = []
## PRESENT only: the coroutine that animates an already-applied rules change.
var presenter: Callable
## Pre-damage presentation snapshots survive rules-driven zone changes.
var target_visuals: Dictionary = {}
var source: Card = null
var element: String = ""
var amount: int = 0
## "single", "multi", "sequence", "radial", "board"
var mode: String = ""
var status: String = ""
var duration: int = 0
var cause: String = ""
## Deterministic variation seed for particles/shake offsets.
var seed: int = 0
var timestamp_ms: int = 0


func _init(p_kind: Kind = Kind.STATUS_APPLIED, p_targets: Array = [],
		p_element: String = "", p_amount: int = 0, p_source: Card = null,
		p_mode: String = "", p_status: String = "", p_cause: String = "") -> void:
	kind = p_kind
	for target in p_targets:
		if target != null and is_instance_valid(target):
			targets.append(target)
	element = p_element
	amount = p_amount
	source = p_source
	mode = p_mode
	status = p_status
	cause = p_cause
	timestamp_ms = Time.get_ticks_msec()
	var key: Array = [kind, element, amount, mode, status, cause]
	for target in targets:
		key.append(target.get_instance_id())
	if source != null and is_instance_valid(source):
		key.append(source.get_instance_id())
	seed = absi(hash(key))


## Damage tiers are semantic, not lightning-specific: every element cue can read
## the same tier and size its impact from it. The bands are the project's 3000
## steps: 0 = <=3000, 1 = up to 6000, 2 = up to 8999, 3 = 9000+.
const DAMAGE_TIER_SCALES: Array[float] = [0.55, 1.0, 1.35, 1.75]


func target_count() -> int:
	return targets.size()


static func damage_tier_for(value: int) -> int:
	if value <= 3000:
		return 0
	if value <= 6000:
		return 1
	if value < 9000:
		return 2
	return 3


func damage_tier() -> int:
	return damage_tier_for(amount)


## A neutral multiplier for cues that do not have their own per-tier tuning.
func damage_scale() -> float:
	return DAMAGE_TIER_SCALES[damage_tier()]


func damage_tier_name() -> String:
	return str(["weak", "medium", "high", "maximum"][damage_tier()])


func is_area() -> bool:
	return kind == Kind.BOARD_DAMAGE or mode in ["board", "multi", "sequence", "radial"]


func describe() -> String:
	var who: String = status if not status.is_empty() else str(amount)
	return "VfxEvent(%s, %s, targets=%d, element=%s, mode=%s)" % [
		Kind.keys()[kind], who, targets.size(), element, mode
	]
