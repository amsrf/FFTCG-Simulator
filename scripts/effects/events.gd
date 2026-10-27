extends RefCounted
## The finite event vocabulary. The enum is the internal identity; `NAMES` is the boundary translation used by logs,
## stack snapshots and any remaining data-driven code.
##
## Event names are also card hook method names, so `name_of()` and `from_name()` keep the two in sync in one place.

enum Event {
	NONE,
	ENTER_FIELD,
	ATTACK,
	CAST,
	BLOCKS,
	BLOCKED,
	CAUSE_DAMAGE_TO_PLAYER,
	ENTER_BREAK_FROM_FIELD,
	BREAK,
	CHOSEN,
	PARTY_ATTACK,
	PARTY_ATTACKS,
	PARTY_DEALS_DAMAGE,
	ATTACK_PHASE_START,
	DAMAGE_RECEIVED,
	CARD_LEFT_FIELD,
	FORWARD_ATTACKS,
	SUMMON_CAST,
}

const NAMES := {
	Event.ENTER_FIELD: "when_enter_field",
	Event.ATTACK: "when_attack",
	Event.CAST: "when_cast",
	Event.BLOCKS: "when_blocks",
	Event.BLOCKED: "when_blocked",
	Event.CAUSE_DAMAGE_TO_PLAYER: "when_cause_damage_to_player",
	Event.ENTER_BREAK_FROM_FIELD: "when_enter_break_from_field",
	Event.BREAK: "when_break",
	Event.CHOSEN: "when_chosen",
	Event.PARTY_ATTACK: "when_party_attack",
	Event.PARTY_ATTACKS: "when_party_attacks",
	Event.PARTY_DEALS_DAMAGE: "when_party_deals_damage",
	Event.ATTACK_PHASE_START: "attack_phase_start",
	Event.DAMAGE_RECEIVED: "damage_received",
	Event.CARD_LEFT_FIELD: "card_left_field",
	Event.FORWARD_ATTACKS: "forward_attacks",
	Event.SUMMON_CAST: "summon_cast",
}


static func name_of(event: int) -> String:
	return str(NAMES.get(event, ""))


static func from_name(event_name: String) -> int:
	for event in NAMES:
		if NAMES[event] == event_name:
			return event
	return Event.NONE


## Accepts an enum id or a legacy string. Used only at boundaries while callers migrate.
static func normalize(value) -> int:
	if value is int:
		return value
	return from_name(str(value))
