extends RefCounted
## TARGET BLOCKS — one evaluator for "which cards may this effect pick?", shared by every path that asks that question.
##
## WHY THIS EXISTS. There were two matchers with two different schemas. `Card.matches_criteria()` takes METHOD NAMES ON
## CARD as keys and push_error()s and returns false for anything else; `Card.does_card_match_target()` understood only
## {type, controller, element}. The aura path used the second and the targeting path the first, so "named Aerith" could
## only be said in one of them, and a session key like `count` made EVERY candidate illegal in the other — silently,
## because a failed match just means the ring never lights.
##
## A BLOCK HAS THREE KINDS OF KEY:
##
##   session  — "count": how many picks the session takes. Not a property of a card, so it is skipped here rather than
##              treated as a criteria key that must exist as a method.
##   criteria — "is_type", "is_element", "is_named", "is_tapped", … a METHOD NAME on Card taking the value and returning
##              bool. A key that is not a method is an ERROR, loudly, rather than a silent "no".
##   rules    — "exclude": a block, or an ARRAY of blocks, the card must NOT match ("other than Aerith"). "is_source" is
##              accepted as a key: true when the candidate IS the card the effect came from.
##
## The two older spellings the aura data uses — type and element — are accepted as aliases of is_type and is_element, and
## "controller" is compared directly because no `is_controller()` method exists. The canonical spelling is the `is_*` one.
## Deliberately no `class_name`: a new global class is not in Godot's cache until the editor rescans, and every headless
## run of this project has been bitten by that. Callers preload the path.

## Keys that configure the SESSION and say nothing about a card. `in` picks the target domain — "field" (default) or
## "stack", so an effect can choose a Summon that has not resolved yet (Summoner 53).
const SESSION_KEYS := ["count", "in"]
## The aura data's spellings of the two criteria that have a method of their own.
const ALIASES := {"type": "is_type", "element": "is_element", "job": "is_job"}

static func matches(card: Card, block: Dictionary, source: Card = null) -> bool:
	if card == null:
		return false
	for key in block:
		var name: String = str(key)
		if name in SESSION_KEYS:
			continue
		if name == "exclude":
			if _matches_exclusion(card, block[key], source):
				return false
			continue
		if name == "is_source":
			if (card == source) != bool(block[key]):
				return false
			continue
		# `check_controller` is the older spelling of the same rule, used by `conditional_power` conditions ("if you
		# control Aerith"). It is routed HERE, not to Card.check_controller(), because that method only sees the
		# CANDIDATE card and cannot know whose point of view "you" is.
		if name == "controller" or name == "check_controller":
			if not _controller_matches(card, str(block[key]), source):
				return false
			continue
		var method_name: String = ALIASES.get(name, name)
		if not card.has_method(method_name):
			push_error("[TargetBlock] '%s' is neither a session key, a rule, nor a method on Card" % name)
			return false
		if not card.callv(method_name, [block[key]]):
			return false
	return true

## A single block, or a list of them — "not any of these". A non-block exclusion matches nothing rather than
## everything, because "exclude something unreadable" must not quietly exclude the whole board.
static func _matches_exclusion(card: Card, exclusion: Variant, source: Card) -> bool:
	if exclusion is Array:
		for one in exclusion:
			if one is Dictionary and matches(card, one, source):
				return true
		return false
	if exclusion is Dictionary:
		return matches(card, exclusion, source)
	return false

## "your"/"their" AND "opponent" are read RELATIVE TO THE SOURCE, because that is how the cards read ("your Fire
## Forwards", "choose 1 Forward opponent controls"). The literal side names keep working for an effect that says them
## outright.
##
## "opponent" MUST be relative: it used to fall through to the literal branch, which meant the string "opponent"
## matched the P2 cards. From the human caster that is accidentally right, but when the AI cast a "dull an opponent's
## Forward" effect it resolved to its OWN Forwards — the card dulled itself. Any card that says "opponent" is written
## from its controller's point of view, so resolve it the same way as "theirs".
##
## With no source there is nothing to be relative to, so "opponent" falls back to the literal side name (P2), which is
## what effect criteria outside a resolution — apply_effect snapshots, probes — have always meant.
static func _controller_matches(card: Card, wanted: String, source: Card) -> bool:
	var mine: String = source.controller if source != null else ""
	var theirs: String = "opponent" if mine == "player" else "player"
	match wanted:
		"mine", "your", "yours":
			return source != null and card.controller == mine
		# "player" IS ALSO WRITTEN FROM THE CASTER'S POINT OF VIEW in this project's card data ("if you control
		# Aerith", "activate all the Backups you control"). Resolve it relative when we know the source, and fall back
		# to the literal P1 seat when we do not (snapshots and probes), which is what it used to mean everywhere.
		"player":
			if source == null:
				return card.controller == "player"
			return card.controller == mine
		"theirs", "their":
			return source != null and card.controller == theirs
		"opponent", "opponents", "enemy":
			if source == null:
				return card.controller == "opponent"
			return card.controller == theirs
		"self":
			return card == source
		_:
			return card.controller == wanted
