extends Node
## THE STACK FACE OF AN AUTO-ABILITY: the effect, never the trigger. A sweep over EVERY coded auto-ability through the
## real CardEffect.stack_text() (no copy of the parser), plus the parser's own edge cases.

const EVENTS := preload("res://scripts/effects/events.gd")
const TRIGGER_TEXT := preload("res://scripts/effects/trigger_text.gd")
const EFFECT_DIR := "res://assets/effects"

## Coded abilities whose event does NOT appear in the card's printed text (the code and the printed card disagree).
## They keep the full printed text on the stack. A new entry here is a data bug to look at, not a parser case to add.
const KNOWN_UNMATCHED := [
	"523 when_party_attack", "549 when_party_deals_damage", "583 when_party_attacks",
	"2588 when_party_attack", "2808 when_party_attacks", "3261 when_party_attack",
]

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[TriggerText] ok   %s" % what)
	else:
		_fails += 1
		print("[TriggerText] FAIL %s" % what)


func _ready() -> void:
	# --- the parser's edges ---------------------------------------------------------------------------------------
	_expect(TRIGGER_TEXT.for_event("When Cloud enters the field, choose 1 Forward opponent controls. Deal it 2000 damage.",
		EVENTS.Event.ENTER_FIELD) == "Choose 1 Forward opponent controls. Deal it 2000 damage.",
		"the trigger clause is cut and the effect capitalised")
	_expect(TRIGGER_TEXT.for_event("When Paine enters the field, if you control [Card Name (Yuna)], draw 1 card.",
		EVENTS.Event.ENTER_FIELD) == "If you control [Card Name (Yuna)], draw 1 card.",
		"a condition after the trigger STAYS (it is checked at resolution)")
	_expect(TRIGGER_TEXT.clause_end("When [Card Name (A, B)] attacks, draw 1 card.") == 31,
		"a comma inside brackets does not end the trigger clause")
	_expect(TRIGGER_TEXT.for_event("[[ex]]EX BURST[[/]] When Reynn enters the field, draw 1 card.",
		EVENTS.Event.ENTER_FIELD) == "Draw 1 card.", "the EX BURST tag is not part of the ability")
	_expect(TRIGGER_TEXT.for_event("Brave[[br]] When Garland attacks, Garland gains +4000 power until the end of the turn.",
		EVENTS.Event.ATTACK) == "Garland gains +4000 power until the end of the turn.",
		"a keyword line before the ability is skipped")
	_expect(TRIGGER_TEXT.for_event("Brave[[br]] 《1》: Draw 1 card.", EVENTS.Event.ATTACK) == "",
		"no auto-ability on the card -> no match (the caller falls back)")
	_expect(TRIGGER_TEXT.without_trigger("When a Forward you control attacks, draw 1 card.") == "Draw 1 card."
		and TRIGGER_TEXT.without_trigger("Draw 1 card.") == "Draw 1 card.",
		"a JSON trigger's text loses its trigger, and text without one is left alone")

	# --- Gadot: two abilities on one event, each with its OWN sentence -------------------------------------------
	var printed: Dictionary = {}
	for entry in CardDatabase.card_database:
		printed[int(entry.get("id", 0))] = str(entry.get("text_en", ""))
	var gadot = load("%s/card_7.gd" % EFFECT_DIR).new()
	var gadot_etb: Array[int] = gadot.triggered_abilities(EVENTS.Event.ENTER_FIELD)
	_expect(gadot_etb.size() == 2, "Gadot has two enter-the-field abilities")
	if gadot_etb.size() == 2:
		_expect(gadot.stack_text(printed[7], gadot_etb[0]) == "You may play 1 Fire Forward of cost 2 or less from your hand onto the field.",
			"Gadot's FIRST ability shows the play sentence")
		_expect(gadot.stack_text(printed[7], gadot_etb[1]) == "All the Forwards you control gain +1000 power until the end of the turn.",
			"Gadot's SECOND ability shows the +1000 sentence")
	var spec = load("res://scripts/effects/trigger_spec.gd").new(EVENTS.Event.ENTER_FIELD, Callable()).text("Custom.")
	_expect(spec.wording == "Custom.", "a TriggerSpec's .text() override is stored for the stack face")

	# --- the sweep: every coded auto-ability --------------------------------------------------------------------
	var abilities_checked := 0
	var unmatched: Array[String] = []
	var still_triggered: Array[String] = []
	var dir := DirAccess.open(EFFECT_DIR)
	for file in dir.get_files():
		if not file.ends_with(".gd") or not file.begins_with("card_"):
			continue
		var id := int(file.trim_prefix("card_").trim_suffix(".gd"))
		var effect = load("%s/%s" % [EFFECT_DIR, file]).new()   # kept alive while its specs are read
		var list: Array = effect.auto_abilities()
		for i in range(list.size()):
			if list[i].event == EVENTS.Event.CAST:
				continue   # a Summon's whole text IS its effect
			abilities_checked += 1
			var wording: String = effect.stack_text(printed.get(id, ""), i)
			var label := "%d %s" % [id, EVENTS.name_of(list[i].event)]
			if wording.is_empty():
				unmatched.append(label)
				continue
			print("[TriggerText]      %-34s %s" % [label, wording])
			if TRIGGER_TEXT.is_auto_ability(wording):
				still_triggered.append(label)
	_expect(still_triggered.is_empty(), "no stack face starts with its trigger (%s)" % str(still_triggered))
	_expect(abilities_checked > 100, "%d coded auto-abilities were swept" % abilities_checked)
	var new_misses: Array[String] = []
	for label in unmatched:
		if not KNOWN_UNMATCHED.has(label):
			new_misses.append(label)
	_expect(new_misses.is_empty(), "every unmatched ability is a known code/printed mismatch (new: %s)" % str(new_misses))
	print("[TriggerText] %d of %d abilities parsed; unmatched: %s" % [abilities_checked - unmatched.size(), abilities_checked, str(unmatched)])

	print("[TriggerText] %d checks | failures: %d" % [_checks, _fails])
	print("[TriggerText] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
