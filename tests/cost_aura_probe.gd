extends Node
## COST AURA probe — Terra 46: "The cost required for your opponent to cast Summons increases by 1" and
## "Terra cannot be chosen by opponent's Summons".
##
## The surcharge is baked into the cost dictionary before the payment window opens, so the crystal row, the payment
## check and the AI's affordability all read the same number.

const GAME_SCENE := preload("res://game.tscn")

const IFRIT := 4            # Summon, fire, cost 2 → base {火:1, neutral:1}
const TERRA := 46
const SQUALL := 41          # Forward, cost 3: must NOT be surcharged
const FIRE_MANA := 3        # Red Mage, fire Backup

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CostAura] ok   %s" % what)
	else:
		_fails += 1
		print("[CostAura] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	return card


func _card(id: int, side: String) -> Card:
	var list: Array = _field.get_front_cards_for(side) + _field.get_back_cards_for(side)
	for c in list:
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": FIRE_MANA}],   # ONE fire source: enough at base cost, not with Terra's +1
		"player_deck": range(101, 121),
		"opponent_deck": range(141, 161),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var ifrit: Card = _game.call("create_card", IFRIT, "player")
	_game.add_child(ifrit)
	var forward: Card = _game.call("create_card", SQUALL, "player")
	_game.add_child(forward)

	# --- the printed cost, and no aura yet ------------------------------------------------------------------
	var base: Dictionary = ifrit.get_cost()
	print("[CostAura] Ifrit printed %s, effective %s" % [str(base), str(_field.effective_cost(ifrit))])
	_expect(base == {"火": 1, "neutral": 0}, "Ifrit's printed cost is 1 fire (cost 1)")
	_expect(_field.effective_cost(ifrit) == base, "with no Terra, the effective cost is the same")

	# --- Terra on the CASTER's side must not surcharge ------------------------------------------------------
	var own_terra: Card = _make(TERRA, "player")
	_expect(_field.effective_cost(ifrit) == base,
		"your OWN Terra does not raise your Summons")

	# --- Terra on the OPPONENT's side does ----------------------------------------------------------------
	var enemy_terra: Card = _make(TERRA, "opponent")
	var raised: Dictionary = _field.effective_cost(ifrit)
	print("[CostAura] with the opponent's Terra: %s" % str(raised))
	_expect(int(raised.get("neutral", 0)) == int(base.get("neutral", 0)) + 1
			and int(raised.get("火", 0)) == int(base.get("火", 0)),
		"the opponent's Terra adds exactly +1 neutral to your Ifrit")

	# --- the payment modal reads the same number -----------------------------------------------------------
	var assistant = _game.get("assistant")
	assistant.call("_on_hand_charge_start", ifrit)
	print("[CostAura] payment modal mana_cost = %s" % str(assistant.get("mana_cost")))
	_expect(assistant.get("mana_cost") == raised,
		"the payment window is opened with the SURCHARGED cost")
	assistant.call("on_charge_cancelled")

	# --- the AI agrees with the modal ----------------------------------------------------------------------
	var ai = AIAgent.new()
	ai.bind(_game)
	_expect(not ai.call("_can_afford", ifrit, 1),
		"one fire Backup cannot pay 1 fire + 1 neutral")
	var second: Card = _make(FIRE_MANA, "player")
	_expect(ai.call("_can_afford", ifrit, 1),
		"two fire Backups can pay 1 fire + 1 neutral — the AI is paying the surcharge too")

	# --- two Terras stack ----------------------------------------------------------------------------------
	var second_terra: Card = _make(TERRA, "opponent")
	var stacked: Dictionary = _field.effective_cost(ifrit)
	print("[CostAura] with TWO opponent Terras: %s" % str(stacked))
	_expect(int(stacked.get("neutral", 0)) == int(base.get("neutral", 0)) + 2,
		"a second Terra stacks: +2 neutral")

	# --- Characters are not Summons ------------------------------------------------------------------------
	_expect(_field.effective_cost(forward) == forward.get_cost(),
		"a Forward's cost is untouched by Terra")

	# --- Terra cannot be chosen by the opponent's Summons ---------------------------------------------------
	_field.set_viable_targets({"is_type": "Forward"}, ifrit, "Summon")
	print("[CostAura] Terra valid target for your Summon: %s" % enemy_terra.is_valid_target)
	_expect(not enemy_terra.is_valid_target, "your Summon cannot choose the opponent's Terra")
	_field.set_viable_targets({"is_type": "Forward"}, enemy_terra, "Summon")
	_expect(enemy_terra.is_valid_target, "but Terra can be chosen by her own controller's Summon")
	_field.reset_targets()

	print("[CostAura] %d checks | failures: %d" % [_checks, _fails])
	print("[CostAura] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
