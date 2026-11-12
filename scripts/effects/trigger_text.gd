extends RefCounted
## THE STACK FACE OF AN AUTO-ABILITY SAYS WHAT IT DOES, NOT WHAT TRIGGERED IT.
##
## "When Cloud enters the field, choose 1 Forward opponent controls. Deal it 2000 damage." goes on the stack as
## "Choose 1 Forward opponent controls. Deal it 2000 damage." A condition AFTER the trigger stays, because it is checked
## at resolution and is part of what the ability does: "When Paine enters the field, if you control Yuna, draw 1 card."
## shows "If you control Yuna, draw 1 card."
##
## Pure text in, text out: no game state. CardEffect.stack_text() is the only caller; a card whose printed text does not
## parse gives its TriggerSpec a .text("...") instead of teaching this file a special case.
const EVENTS := preload("res://scripts/effects/events.gd")

## How each event is worded in a printed trigger clause (lower case). An ability matches when ANY phrase occurs in its
## trigger clause, so one printed "When X blocks or is blocked" ability matches both BLOCKS and BLOCKED.
const PHRASES := {
	EVENTS.Event.ENTER_FIELD: ["enters the field", "enters your field"],
	EVENTS.Event.ATTACK: ["attacks"],
	EVENTS.Event.BLOCKS: ["blocks"],
	EVENTS.Event.BLOCKED: ["is blocked"],
	EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER: ["deals damage to your opponent", "deals damage to the opponent"],
	EVENTS.Event.ENTER_BREAK_FROM_FIELD: ["from the field into the break zone"],
	EVENTS.Event.BREAK: ["is broken", "into the break zone"],
	EVENTS.Event.CHOSEN: ["is chosen"],
	EVENTS.Event.PARTY_ATTACK: ["party"],
	EVENTS.Event.PARTY_ATTACKS: ["party"],
	EVENTS.Event.PARTY_DEALS_DAMAGE: ["party"],
	EVENTS.Event.ATTACK_PHASE_START: ["attack phase starts", "beginning of the attack phase"],
	EVENTS.Event.DAMAGE_RECEIVED: ["receive"],
	EVENTS.Event.CARD_LEFT_FIELD: ["leaves the field", "from the field into the break zone", "into the break zone", "is broken"],
	EVENTS.Event.FORWARD_ATTACKS: ["attacks"],
	EVENTS.Event.SUMMON_CAST: ["cast"],
}

## How a printed auto-ability opens. Anything else (an activated "cost: effect", a static rule) is not one.
const OPENINGS := ["When ", "Each time ", "At the "]


## The printed abilities of a card, one per [[br]] line, with the EX BURST tag removed.
static func abilities(printed: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in printed.split("[[br]]"):
		var ability := line.replace("[[ex]]EX BURST[[/]]", "").replace("[[ex]]EX BURST [[/]]", "").strip_edges()
		if not ability.is_empty():
			out.append(ability)
	return out


static func is_auto_ability(ability: String) -> bool:
	for opening in OPENINGS:
		if ability.begins_with(opening):
			return true
	return false


## Where the trigger clause ends: the first comma outside brackets ("[Card Name (Yuna)]" never splits a clause).
## -1 when there is none.
static func clause_end(ability: String) -> int:
	var depth := 0
	for i in range(ability.length()):
		var ch := ability[i]
		if ch == "[" or ch == "(":
			depth += 1
		elif ch == "]" or ch == ")":
			depth -= 1
		elif ch == "," and depth == 0:
			return i
	return -1


## The ability with its trigger clause cut off and the first letter capitalised. "" when there is no clause to cut.
static func effect_of(ability: String) -> String:
	if not is_auto_ability(ability):
		return ""
	var cut := clause_end(ability)
	if cut < 0:
		return ""
	var rest := ability.substr(cut + 1).strip_edges()
	if rest.is_empty():
		return ""
	return rest.left(1).to_upper() + rest.substr(1)


## The wording of the `nth` printed auto-ability that `event` triggers (0 = the first such ability on the card).
## When no printed clause names the event but the card has exactly ONE auto-ability, that one is it (board events are
## worded too many ways to list). "" when nothing matched: the caller decides the fallback.
static func for_event(printed: String, event: int, nth: int = 0) -> String:
	var autos: Array[String] = []
	for ability in abilities(printed):
		if is_auto_ability(ability):
			autos.append(ability)
	var matching: Array[String] = []
	var phrases: Array = PHRASES.get(event, [])
	for ability in autos:
		var cut := clause_end(ability)
		if cut < 0:
			continue
		var clause := ability.left(cut).to_lower()
		for phrase in phrases:
			if clause.contains(phrase):
				matching.append(ability)
				break
	if nth >= 0 and nth < matching.size():
		return effect_of(matching[nth])
	if autos.size() == 1:
		return effect_of(autos[0])
	return ""


## A wording that may still start with its trigger (a JSON trigger's "text"): cut the clause if there is one, otherwise
## return it unchanged.
static func without_trigger(wording: String) -> String:
	var effect := effect_of(wording.strip_edges())
	return effect if not effect.is_empty() else wording
