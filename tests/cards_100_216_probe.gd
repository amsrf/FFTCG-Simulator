extends Node
## CARDS 100-216, phases A1 + A2 — one representative card per mechanism.
##
## The 57 data entries share a dozen shapes; testing every card would duplicate the same five lines 57 times.
## This probe exercises each SHAPE against the real engine, plus a few data-shape assertions for the cards whose
## shape is the whole point (skill arrays, apply_effect inside a skill, riders, power_per).

const GAME_SCENE := preload("res://game.tscn")

const SQUALL := 41
const SNOW := 43
const CHEMIST := 31
const KEFKA := 104          # earth Backup, cost 4
const DRAGOON := 147        # lightning Forward, 6000
const LULU_AURA := 150      # lightning Backup: Lightning Forwards +1000
const VAAN := 154           # water Forward, 6000
const ULTIMECIA := 152      # water Forward, 9000
const YUNA_BACKUP := 176
const SERAH := 195          # ice Forward
const NOEL := 208           # lightning Forward: +2000 with Serah

class TargetAgent extends Agent:
	var wanted: Card = null

	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		if wanted != null and is_instance_valid(wanted) and wanted.is_valid_target:
			game.field.set_target_card(wanted)
		game.assistant.on_target_complete()


var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Range] ok   %s" % what)
	else:
		_fails += 1
		print("[Range] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _off_field(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	add_child(card)
	return card


func _drain() -> void:
	var guard: int = 0
	while _stack.stack_length() > 0 and guard < 20:
		await _stack.resolve_top_effect()
		guard += 1
	await get_tree().process_frame


func _pick(card: Card) -> void:
	# Code ETBs open their target window when the stack object resolves, not synchronously inside
	# execute_card_effect(). Start that resolution, then wait for the window before supplying the click.
	if _stack != null and _stack.stack_length() > 0 \
			and GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET:
		_stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	_field.set_target_card(card)
	_assistant.call("on_target_complete")


func _pick_many(cards: Array) -> void:
	if _stack != null and _stack.stack_length() > 0 			and GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET:
		_stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	for c in cards:
		_field.set_target_card(c)
	_assistant.call("on_target_complete")


func _ready() -> void:
	# --- data shapes that cannot be inferred from a card being present --------------------------------
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	var lulu_specs: Array = load("res://assets/effects/card_149.gd").new().activated_abilities()
	_expect(lulu_specs.size() == 2, "Lulu 149 has two code abilities")
	_expect(not lulu_specs.is_empty() and not lulu_specs[0].sacrifice.is_empty(),
		"and the first one sacrifices a Backup")
	var cloud_specs: Array = load("res://assets/effects/card_182.gd").new().activated_abilities()
	_expect(cloud_specs.size() == 2 and "Meteorain" in cloud_specs[0].text,
		"Cloud 182's Meteorain is a code ability")
	_expect(load("res://assets/effects/card_198.gd").new().has_method("when_cast"),
		"Valefor 198's mass damage is code-owned")
	var raines_riders: Array = load("res://assets/effects/card_192.gd").new().damage_caused_riders()
	_expect(raines_riders.size() == 1 and raines_riders[0].has("on_enter_break_zone"),
		"Cid Raines 192 attaches a code-owned on-break rider")
	var ramza_rules: Array = load("res://assets/effects/card_144.gd").new().power_per_rules()
	_expect(ramza_rules.size() == 1 and int(ramza_rules[0].get("value", 0)) == 1000,
		"Ramza 144 scales with your Backups")
	var noel_cp: Array = load("res://assets/effects/card_208.gd").new().conditional_powers()
	_expect(noel_cp.size() == 1 and int(noel_cp[0].get("value", 0)) == 2000,
		"Noel 208 has a code conditional +2000")
	_expect(load("res://assets/effects/card_196.gd").new().has_method("when_enter_field"),
		"Mog 196's Category XIII search is code-owned")

	MatchSetup.config = MatchSetup.build_config("clean", {
		"opponent_type": "ai",
		"opponent_hand": [1, 2, 3],
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")

	# --- 112 Delita: ETB breaks one of YOUR Characters -------------------------------------------------
	var mine: Card = _make(CHEMIST, "player")
	var delita: Card = _make(112, "player")
	_field.execute_card_effect(delita, "when_enter_field")
	await _pick(mine)
	await _drain()
	_expect(not mine.is_on_field(), "Delita 112's ETB breaks the chosen Character you control")

	# --- 117 Hecatoncheir: break a Backup of cost 3 or more --------------------------------------------
	var big_backup: Card = _make(KEFKA, "opponent")
	var heca: Card = _off_field(117, "player")
	_field.execute_card_effect(heca, "when_cast")
	await _pick(big_backup)
	await _drain()
	_expect(not big_backup.is_on_field(), "Hecatoncheir 117 breaks a cost-4 Backup")

	# --- 140 Magus: ETB 5000 damage -------------------------------------------------------------------
	var target: Card = _make(SQUALL, "opponent")
	var magus: Card = _make(140, "player")
	# 140 is a code-defined auto-ability: it chooses its target when it resolves.
	var previous_agent = _game.get("player_agent")
	var target_agent := TargetAgent.new()
	target_agent.bind(_game)
	target_agent.wanted = target
	_game.set("player_agent", target_agent)
	_field.execute_card_effect(magus, "when_enter_field")
	await _drain()
	_game.set("player_agent", previous_agent)
	_expect(target.accumulated_damage == 5000, "Magus 140 deals 5000 to the chosen Forward")

	# --- 101 Gippal: all YOUR Forwards +4000 ----------------------------------------------------------
	var g1: Card = _make(SQUALL, "player")
	var g2: Card = _make(DRAGOON, "player")
	var p1: int = g1.power
	var p2: int = g2.power
	var gippal: Card = _make(101, "player")
	_field.execute_card_effect(gippal, "when_enter_field")
	await _drain()
	_expect(g1.power == p1 + 4000 and g2.power == p2 + 4000,
		"Gippal 101 gives every Forward you control +4000")

	# --- 132 Cait Sith: dull an opponent Forward ------------------------------------------------------
	var dull_me: Card = _make(SNOW, "opponent")
	var cait: Card = _make(132, "player")
	_field.execute_card_effect(cait, "when_enter_field")
	await _pick(dull_me)
	await _drain()
	_expect(dull_me.tapped, "Cait Sith 132 dulls the chosen opponent Forward")

	# --- 164 Tidus: Water Forwards +1000 on attack ----------------------------------------------------
	var tidus: Card = _make(164, "player")
	var water_a: Card = _make(VAAN, "player")
	var water_b: Card = _make(ULTIMECIA, "player")
	var ice_ctrl: Card = _make(SQUALL, "player")
	var wt: int = tidus.power
	var wa: int = water_a.power
	var wb: int = water_b.power
	var ic: int = ice_ctrl.power
	_field.execute_card_effect(tidus, "when_attack")
	await _drain()
	print("[Range] Tidus: self %d->%d, Vaan %d->%d, Ultimecia %d->%d, ice %d->%d" % [
		wt, tidus.power, wa, water_a.power, wb, water_b.power, ic, ice_ctrl.power])
	_expect(tidus.power == wt + 1000 and water_a.power == wa + 1000 and water_b.power == wb + 1000,
		"Tidus 164 buffs every Water Forward")
	_expect(ice_ctrl.power == ic, "and leaves a non-Water Forward alone")

	# --- 208 Noel: conditional +2000 with Serah -------------------------------------------------------
	var serah: Card = _make(SERAH, "player")
	var noel_base: int = 0
	var noel: Card = _make(NOEL, "player")
	noel_base = 5000
	_expect(noel.power == noel_base + 2000, "Noel 208 gains +2000 while you control Serah")

	# --- 144 Ramza: +1000 per Backup ------------------------------------------------------------------
	var b1: Card = _make(CHEMIST, "player")
	var b2: Card = _make(CHEMIST, "player")
	var ramza: Card = _make(144, "player")
	var back_count: int = _field.get_back_cards_for("player").size()
	print("[Range] Ramza: power %d with %d Backups on field" % [ramza.power, back_count])
	_expect(ramza.power == 5000 + 1000 * back_count,
		"Ramza 144 gains +1000 for each Backup you control")

	# --- 150 Lulu: Lightning Forwards +1000 aura ------------------------------------------------------
	var dragoon: Card = _make(DRAGOON, "player")
	var lulu: Card = _make(LULU_AURA, "player")
	await _drain()
	_expect(dragoon.power == 6000 + 1000, "Lulu 150's aura buffs a Lightning Forward")

	# --- 110 Titan: dull it, and it cannot be broken this turn ----------------------------------------
	var titan_target: Card = _make(SQUALL, "player")
	var titan: Card = _off_field(110, "player")
	_field.execute_card_effect(titan, "when_cast")
	await _pick(titan_target)
	await _drain()
	_expect(titan_target.tapped, "Titan 110 dulls the chosen Forward")
	_game.call("break_card", titan_target)
	await _drain()
	_expect(titan_target.is_on_field(), "and it cannot be broken this turn")

	# --- 193 Jihl: freeze up to two Forwards ----------------------------------------------------------
	var f1: Card = _make(SNOW, "opponent")
	var f2: Card = _make(SQUALL, "opponent")
	var jihl: Card = _make(193, "player")
	_field.execute_card_effect(jihl, "when_enter_field")
	await _pick_many([f1, f2])
	await _drain()
	_expect(f1.status_effects.has("frozen") and f2.status_effects.has("frozen"),
		"Jihl 193 freezes both chosen Forwards")

	# --- 198 Valefor: 3000 to all opponent Forwards, and untap Backups with Yuna -----------------------
	var v1: Card = _make(SQUALL, "opponent")
	var v2: Card = _make(SNOW, "opponent")
	var yuna: Card = _make(YUNA_BACKUP, "player")
	var backup: Card = _make(CHEMIST, "player")
	yuna.tap()
	backup.tap()
	var valefor: Card = _off_field(198, "player")
	_field.execute_card_effect(valefor, "when_cast")
	await _drain()
	_expect(v1.accumulated_damage == 3000 and v2.accumulated_damage == 3000,
		"Valefor 198 deals 3000 to every opponent Forward")
	_expect(not yuna.tapped and not backup.tapped,
		"and activates your Backups because you control Yuna")

	# --- 192 Cid Raines: damage rider -> opponent discards on break -----------------------------------
	# Yuna 176 is still on the field from the Valefor case, and her exile replacement would stop this card from
	# reaching the Break Zone. Remove her so the rider can be observed.
	_game.call("put_card_into_graveyard", yuna)
	await get_tree().process_frame
	var victim: Card = _make(SQUALL, "opponent")
	var hand_before: int = _game.get("opponent").hand.cards.size()
	var raines: Card = _make(192, "player")
	_field.execute_card_effect(raines, "when_enter_field")
	await _pick(victim)
	await _drain()
	_expect(victim.accumulated_damage == 4000, "Cid Raines 192 deals 4000 to the dull Forward")
	_expect(victim.status_effects.has("raines_mark"), "and marks it")
	_game.call("break_card", victim)
	await _drain()
	await get_tree().process_frame
	print("[Range] Cid Raines: opponent hand %d -> %d" % [hand_before, _game.get("opponent").hand.cards.size()])
	_expect(_game.get("opponent").hand.cards.size() == hand_before - 1,
		"and when that Forward hits the Break Zone the opponent discards 1")

	print("[Range] %d checks | failures: %d" % [_checks, _fails])
	print("[Range] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
