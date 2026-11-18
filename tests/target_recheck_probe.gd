extends Node
## TARGETS ARE RE-CHECKED WHEN A SUMMON OR AN ABILITY RESOLVES (rules 11.11.2, 11.11.2.1, 11.3.9).
##
## The user's case: the opponent casts Ifrit at my Forward; I respond with Aerith's Planet Protector ("...They cannot be
## chosen by Summons or abilities this turn"), which resolves first; Ifrit then resolves with no legal target and its
## effect is CANCELLED — it still goes to the Break Zone. Plus: a control run (no protection: the damage lands), the
## partial case (one of two picks protected: only the other is affected, and a divided-damage split follows its card),
## and the same check for an activated ability.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const PRESENTATION := preload("res://scripts/core/presentation.gd")

var _checks := 0
var _fails := 0
var _game: Node = null

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Recheck] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _card(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	return card

## Put an opponent's Ifrit on the stack with `target` already chosen (as a cast would), and resolve it.
func _cast_ifrit_at(target: Card) -> Card:
	var stack = _game.get("stack")
	var ifrit := _card(4, "opponent")   # Ifrit: "Deal 4000 damage to a Forward" — chooses at cast
	ifrit.reparent(stack, false)
	ifrit.effect_targets = [target]
	ifrit.effect_target = target
	stack.cards.append(ifrit)
	await stack.resolve_top_effect()
	await get_tree().process_frame
	return ifrit

func _ready() -> void:
	PRESENTATION.fast_mode = true
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	for _i in range(4):
		await get_tree().process_frame
	var field = _game.get("field")
	var squall := _card(41, "player")   # Squall, Forward 6000: survives 4000
	field.play_card(squall, false, false, false)
	var zack := _card(5, "player")   # Warrior of Light, a second Forward
	field.play_card(zack, false, false, false)
	var aerith := _card(64, "player")   # Aerith 1-064R, Planet Protector
	field.play_card(aerith, false, false, false)
	await get_tree().process_frame

	# ---- CONTROL: no protection, Ifrit's damage lands -------------------------------------------------------------
	var ifrit_a: Card = await _cast_ifrit_at(squall)
	_expect(squall.accumulated_damage == 4000, "control: Ifrit deals its 4000 to an unprotected Forward (%d)"
		% squall.accumulated_damage)
	squall.accumulated_damage = 0

	# ---- THE USER'S CASE: Aerith's Planet Protector resolves first, Ifrit is cancelled ---------------------------
	var effect = aerith.effect()   # kept alive: its Callables point at it
	effect._skill_0(EFFECT_CONTEXT.new(_game, aerith, "test"))
	_expect(squall.status_effects.has("cannot_be_chosen"),
		"Planet Protector: my Forwards cannot be chosen by Summons or abilities this turn")
	var pile_before: int = _game.get("opponent_graveyard").graveyard_cards.size()
	var ifrit_b: Card = await _cast_ifrit_at(squall)
	_expect(squall.accumulated_damage == 0,
		"Ifrit resolves with its only target now unchoosable: NO damage (%d) — its effect is cancelled (11.11.2)"
		% squall.accumulated_damage)
	_expect(_game.get("opponent_graveyard").graveyard_cards.size() == pile_before + 1
			and _game.get("opponent_graveyard").graveyard_cards.has(ifrit_b),
		"the cancelled Summon still goes to its owner's Break Zone")
	_expect(_game.get("stack").stack_length() == 0, "and the stack is empty again")

	# ---- PARTIAL (11.11.2.1): one of two picks protected — only the other is affected ----------------------------
	var theirs := _card(41, "opponent")
	field.play_card(theirs, true, false, false)
	_game.set("_damage_division", [3000, 2000])
	var check: Dictionary = _game.recheck_chosen_targets([squall, theirs],
		{"is_type": "Forward"}, ifrit_a, "Summon")
	_expect(not check["cancelled"] and check["picks"] == [theirs],
		"with one pick still legal the effect is NOT cancelled and keeps only that pick")
	_expect(_game.get("_damage_division") == [2000],
		"a divided-damage split keeps each amount with its card (%s)" % str(_game.get("_damage_division")))
	_game.set("_damage_division", [])

	# ---- ACTIVATED ABILITIES use the same check --------------------------------------------------------------------
	var by_ability: Dictionary = _game.recheck_chosen_targets([squall], {"is_type": "Forward"}, theirs, "Ability")
	_expect(by_ability["cancelled"], "an ability whose only target became unchoosable is cancelled too")
	var free_pick: Dictionary = _game.recheck_chosen_targets([theirs], {"is_type": "Forward"}, theirs, "Ability")
	_expect(not free_pick["cancelled"] and free_pick["picks"] == [theirs], "a still-legal ability target is kept")
	var none: Dictionary = _game.recheck_chosen_targets([], {}, theirs, "Ability")
	_expect(not none["cancelled"], "a targetless effect is never cancelled by the check")

	# ---- A target that LEFT THE FIELD is illegal too ---------------------------------------------------------------
	_game.put_card_into_graveyard(zack)
	await get_tree().process_frame
	var gone: Dictionary = _game.recheck_chosen_targets([zack], {"is_type": "Forward"}, ifrit_a, "Summon")
	_expect(gone["cancelled"], "a target that left the field is no longer legal: cancelled")

	print("[Recheck] %d checks | failures: %d" % [_checks, _fails])
	print("[Recheck] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
