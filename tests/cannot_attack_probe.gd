extends Node
## `cannot_attack` probe — Time Mage 1-049C, "Choose 1 Forward. It cannot attack this turn."
##
## Two things this has to prove, because they are easy to conflate:
##   * the Forward cannot ATTACK
##   * it can still be DULLED — the restriction is on declaring an attack, not on tapping
## and that the restriction wears off with the turn.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CannotAttack] ok   %s" % what)
	else:
		_fails += 1
		print("[CannotAttack] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	card.status_effects.clear()
	card.untap()
	await get_tree().process_frame

	_expect(card.can_attack(), "a normal untapped Forward can attack")

	# The debuff, applied exactly as the card data applies it.
	_game.set("_targets", [card])
	_game.add_status_to_targets("cannot_attack", 1)

	_expect(not card.can_attack(), "with cannot_attack it can no longer attack")
	_expect(card.can_tap(), "but it can still be DULLED — the card restricts attacking, not tapping")
	_expect(not card.tapped, "and nothing tapped it")

	# The AI selects attackers through the same predicate, so it must not pick this card.
	#
	# EMPTY THE POOL FIRST. The debug board has other untapped Forwards, and the AI simply picked one of those — the
	# first version of this check therefore failed for a reason that had nothing to do with the debuff. With every
	# other Forward tapped, our card is the ONLY candidate, so a null answer can only mean it was excluded.
	var field_for_pool = _game.get("field")
	for other in field_for_pool.get_front_cards_for("player"):
		if other != card:
			other.tap()
	var ai = load("res://scripts/agents/ai_agent.gd").new()
	ai.bind(_game)
	var picked: Card = await ai.decide_attacker(1)
	_expect(picked == null, "the AI will not attack with it either")

	# ...and it WOULD have, but for the debuff. Same pool, status removed.
	#
	# Checked on the AI's own candidate list rather than on decide_attacker(): that function deliberately keeps one
	# Forward back, so with a single candidate it returns null for reasons that have nothing to do with the debuff.
	# The list is the thing that must contain the card.
	card.status_effects.erase("cannot_attack")
	var pool_without: Array = ai.call("_untapped_forwards", 1)
	_expect(pool_without.has(card), "with the status removed the AI's candidate list DOES contain it")
	card.status_effects["cannot_attack"] = 1
	var pool_with: Array = ai.call("_untapped_forwards", 1)
	_expect(not pool_with.has(card), "and with the status it does not")

	# --- it wears off with the turn -------------------------------------------------------------------
	card.turn_end()
	_expect(not card.status_effects.has("cannot_attack"), "the status is gone after the turn ends")
	_expect(card.can_attack(), "so it can attack again")

	# --- the data ---------------------------------------------------------------------------------------
	var entry: Dictionary = CardDatabase.card_effects.get("49", {})
	var skills: Array = entry.get("skill", [])
	_expect(skills.size() == 1, "Time Mage has one skill")
	if skills.size() == 1:
		var skill: Dictionary = skills[0]
		_expect(bool(skill.get("tap", false)), "activating it dulls the Backup")
		_expect(skill.has("choose_target"), "and it chooses a Forward")
		var instrs: Array = skill.get("instructions", [])
		_expect(instrs.size() == 1 and str(instrs[0].get("name", "")) == "add_status_effect",
			"whose effect is the status")
		if instrs.size() == 1:
			var args: Array = instrs[0].get("argument", [])
			_expect(args.size() >= 1 and str(args[0]) == "cannot_attack", "namely cannot_attack")

	print("[CannotAttack] %d checks | failures: %d" % [_checks, _fails])
	print("[CannotAttack] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
