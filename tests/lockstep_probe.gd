extends Node
## ONLINE LOCKSTEP, end to end without a network. Machine A plays seat 1 with its decisions RECORDED (RecordingAgent
## around the AI) into JSON messages. Machine B plays the same match as seat 2, with seat 1 answered ONLY from those
## messages (RemoteAgent). If the protocol carries everything, B's board hash matches A's at every turn boundary.
##
## Run one match after the other rather than side by side: two live games would share the autoloads (player mode,
## the presentation queue), which a real pair of machines does not.
##   godot --headless res://tests/lockstep_probe.tscn -- --seed=2 --turns=4

const GAME_SCENE := preload("res://game.tscn")
const PRESENTATION := preload("res://scripts/presentation.gd")
const RECORDING_AGENT := preload("res://scripts/agents/recording_agent.gd")
const REMOTE_AGENT := preload("res://scripts/agents/remote_agent.gd")
const TIME_LIMIT := 150.0

var SEED := 424242
var TURNS := 3
## --tamper drops one message on the way to machine B: the probe then REQUIRES the divergence to be caught.
var TAMPER := false
## --human: seat 1 on machine A is a HUMAN (LocalAgent) driven through the real UI calls by _drive_human().
var HUMAN := false
var _human_casts := 0
var _human_cancels := 0
var _human_activations := 0
var _human_activation_cancels := 0
var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Lockstep] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("--seed="):
			SEED = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			TURNS = int(a.get_slice("=", 1))
		elif a == "--tamper":
			TAMPER = true
		elif a == "--human":
			HUMAN = true

func _base() -> Dictionary:
	var cfg: Dictionary = MatchSetup.build_config("ai", {"player_type": "ai", "opponent_type": "ai", "seed": SEED, "starting_player": 1})
	if SEED != 424242:
		cfg["player_deck"] = MatchSetup._shuffled(cfg.get("player_deck", []), SEED)
		cfg["opponent_deck"] = MatchSetup._shuffled(cfg.get("opponent_deck", []), SEED + 1)
	return cfg

func _mirrored(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in cfg:
		var k: String = str(key)
		if k.begins_with("player_"):
			out["opponent_" + k.substr(7)] = cfg[key]
		elif k.begins_with("opponent_"):
			out["player_" + k.substr(9)] = cfg[key]
		else:
			out[key] = cfg[key]
	out["starting_player"] = 3 - int(cfg.get("starting_player", 1))
	out["local_seat"] = 2
	return out

var _human_driver_pending = null
## Set when machine A's match is over: the driver must not touch a game that is being freed.
var _driver_stop := false

func _play(cfg: Dictionary, label: String) -> Dictionary:
	MatchSetup.config = cfg
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	if _human_driver_pending != null:
		_drive_human(game, _human_driver_pending)
	var start := Time.get_ticks_msec()
	var desyncs: Array = []
	game.desync_detected.connect(func(t, a, b): desyncs.append("turn %s: %s vs %s" % [t, a, b]))
	while not game.match_over and game.turn_number <= TURNS:
		await get_tree().create_timer(0.1).timeout
		if (Time.get_ticks_msec() - start) / 1000.0 > TIME_LIMIT:
			print("[Lockstep] %s hit the time limit at turn %d" % [label, game.turn_number])
			break
	_driver_stop = true
	var out := {"hashes": game.turn_hashes.duplicate(), "turn": game.turn_number, "desyncs": desyncs,
		"snapshot": game.snapshot_by_seat()}
	print("[Lockstep] %s: turn %d after %.1fs" % [label, game.turn_number, (Time.get_ticks_msec() - start) / 1000.0])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return out

## THE SCRIPTED HUMAN: plays seat 1 through the same calls the UI makes (Hand.charge, selecting mana, the Assistant's
## confirm / cancel / pass, no attack, no block). In its first priority window it starts a cast and CANCELS it (a draft:
## nothing may be sent), then casts for real.
func _drive_human(game: Node, holder: Array) -> void:
	var last_window := -1
	var announced := {}
	while not _driver_stop and is_instance_valid(game) and not game.match_over:
		await get_tree().create_timer(0.05).timeout
		var rec = holder[0]
		if _driver_stop or rec == null or not is_instance_valid(game):
			continue
		var assistant = game.assistant
		match rec.pending_kind:
			"take_priority":
				if rec.window_serial == last_window:
					continue
				last_window = rec.window_serial
				if _human_activation_cancels == 0 and await _human_activate(game, true) == "cancelled":
					_human_activation_cancels += 1
				if _human_activations < 3 and await _human_activate(game, false) == "activated":
					_human_activations += 1
					continue
				if _human_cancels == 0 and await _human_cast(game, true) == "cancelled":
					_human_cancels += 1
				if await _human_cast(game, false) == "cast":
					_human_casts += 1
				else:
					assistant.pressed_pass_priority.emit()
			"decide_attackers", "decide_attacker":
				assistant.advance_attack_declaration_step.emit()
			"decide_blocker":
				assistant.advance_blocker_declaration_step.emit()
			"":
				pass
			_:
				if not announced.has(rec.pending_kind):
					announced[rec.pending_kind] = true
					print("[Lockstep] human driver has no answer for '%s'" % rec.pending_kind)

## Activate one of the human's field abilities the way the UI does: the click, then the S card, the payment, and
## the targets or the Confirm. `cancel` backs out at the last step instead, which must send nothing.
func _human_activate(game: Node, cancel: bool) -> String:
	var hand = game.hand_for(1)
	var field = game.field
	var stack = game.stack
	var assistant = game.assistant
	for card in field.get_all_cards():
		if card.controller != Card.PLAYER or not field.can_activate_now(card):
			continue
		var skills: Array = card.activation_skills()
		if skills.size() != 1:
			continue
		var def: Dictionary = skills[0]
		if bool(def.get("x_cost", false)) or not Dictionary(def.get("sacrifice", {})).is_empty() \
				or int(def.get("discard", 0)) > 0:
			continue
		field.try_activate_from_field(card)
		await get_tree().process_frame
		if _driver_stop or not is_instance_valid(game):
			return "none"
		if stack.skill_activation_proxy == null:
			continue
		if stack.s_cost_active:
			var named = hand.cards.filter(func(h): return h.card_name == card.card_name)
			if named.is_empty() or cancel:
				assistant.choose_card_finished.emit(false)
				await get_tree().process_frame
				if cancel:
					return "cancelled"
				continue
			hand.selected_card_for_effect = named[0]
			assistant.choose_card_finished.emit(true)
			await get_tree().process_frame
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.PAYING_COST:
			for backup in field.get_back_cards_for(Card.PLAYER):
				if assistant.can_pay_cost():
					break
				if not backup.tapped and backup != card:
					field.add_card_to_mana_conversion(backup, backup.mana_element())
			for other in hand.cards.duplicate():
				if assistant.can_pay_cost():
					break
				if other != stack.s_cost_selected_card:
					hand.add_card_to_mana_conversion(other)
			if cancel or not assistant.can_pay_cost():
				assistant.on_charge_cancelled()
				await get_tree().process_frame
				if cancel:
					return "cancelled"
				continue
			assistant.on_charge_complete()
			await get_tree().process_frame
		if stack.skill_activation_proxy == null:
			continue
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			var target = null
			for c in field.get_all_cards():
				if c.is_valid_target:
					target = c
					break
			if target == null or cancel:
				assistant.on_target_cancel()
				await get_tree().process_frame
				if cancel:
					return "cancelled"
				continue
			field.set_target_card(target)
			await get_tree().process_frame
			if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
				assistant.on_target_complete()
				await get_tree().process_frame
		elif cancel:
			stack.call("_clear_skill_proxy")
			GlobalVariables.refresh_mode()
			assistant.show_pass_priority_button()
			return "cancelled"
		else:
			stack.confirm_skill_without_target_then_priority()
		await get_tree().process_frame
		if not stack.skill_mana_deferred_until_target_confirm:
			print("[Lockstep] human activated %s" % card.card_name)
			return "activated"
	return "none"

func _human_cast(game: Node, cancel: bool) -> String:
	var hand = game.hand_for(1)
	var field = game.field
	var assistant = game.assistant
	for card in hand.cards.duplicate():
		if card.type != Card.FORWARD and card.type != Card.BACKUP:
			continue
		if not hand.charge(card):
			continue
		await get_tree().process_frame
		if _driver_stop or not is_instance_valid(game):
			return "none"
		if cancel:
			assistant.on_charge_cancelled()
			await get_tree().process_frame
			return "cancelled"
		for backup in field.get_back_cards_for(Card.PLAYER):
			if assistant.can_pay_cost():
				break
			if not backup.tapped:
				field.add_card_to_mana_conversion(backup, backup.mana_element())
		for other in hand.cards.duplicate():
			if assistant.can_pay_cost():
				break
			if other != card:
				hand.add_card_to_mana_conversion(other)
		if assistant.can_pay_cost():
			assistant.on_charge_complete()
			await get_tree().process_frame
			return "cast"
		assistant.on_charge_cancelled()
		await get_tree().process_frame
	return "none"

func _ready() -> void:
	_read_args()
	print("[Lockstep] seed=%d turns=%d tamper=%s human=%s" % [SEED, TURNS, TAMPER, HUMAN])
	PRESENTATION.fast_mode = true
	var base := _base()

	# MACHINE A: seat 1 is local; its decisions are recorded.
	var recorder := [null]
	var cfg_a := base.duplicate()
	if HUMAN:
		cfg_a["player_type"] = "local"
	cfg_a["wrap_agent"] = func(local_id: int, agent: Agent) -> Agent:
		if local_id == 1:
			recorder[0] = RECORDING_AGENT.new(agent)
			return recorder[0]
		return agent
	if HUMAN:
		_human_driver_pending = recorder
	_driver_stop = false
	var a: Dictionary = await _play(cfg_a, "machine A (seat 1, recording)")
	_human_driver_pending = null
	var messages: Array = recorder[0].sent if recorder[0] != null else []
	var plays := 0
	for m in messages:
		if m.contains("\"take_priority\"") and m.contains("\"card\""):
			plays += 1
	print("[Lockstep] seat 1 sent %d messages (%d priority windows with a play)" % [messages.size(), plays])
	if HUMAN:
		print("[Lockstep] scripted human: %d casts, %d cancelled drafts, %d abilities, %d cancelled abilities" % [
			_human_casts, _human_cancels, _human_activations, _human_activation_cancels])
		_expect(_human_casts > 0 and _human_cancels > 0, "the human both cast and cancelled (%d / %d)" % [_human_casts, _human_cancels])
		_expect(_human_activations > 0 and _human_activation_cancels > 0,
			"the human both activated and cancelled abilities (%d / %d)" % [_human_activations, _human_activation_cancels])
		var acts := 0
		for m in messages:
			acts += m.count("\"activate\"")
		_expect(acts == _human_activations, "only committed abilities were sent (%d sent, %d activated)" % [acts, _human_activations])
		_expect(plays == _human_casts + _human_activations, "only committed plays were sent (%d sent, %d cast + %d activated)" % [
			plays, _human_casts, _human_activations])
	_expect(messages.size() > 5, "seat 1 sent decisions to replay (%d)" % messages.size())

	if TAMPER and messages.size() > 3:
		messages = messages.duplicate()
		messages.remove_at(2)
	# MACHINE B: seat 2 is local; seat 1 is answered only from A's messages.
	var remote := [null]
	var cfg_b := _mirrored(base)
	cfg_b["wrap_agent"] = func(local_id: int, agent: Agent) -> Agent:
		if local_id == 2:   # on machine B the "opponent" is seat 1
			var r = REMOTE_AGENT.new()
			for m in messages:
				r.receive(m)
			remote[0] = r
			return r
		return agent
	var b: Dictionary = await _play(cfg_b, "machine B (seat 2, seat 1 remote)")
	PRESENTATION.fast_mode = false

	if TAMPER:
		# A missing message must be CAUGHT (a wrong kind of decision, or a board that no longer matches), never absorbed.
		var hashes_differ := false
		for t in a["hashes"]:
			if str(a["hashes"][t]) != str(b["hashes"].get(t, "")):
				hashes_differ = true
		_expect((remote[0] != null and remote[0].diverged) or not b["desyncs"].is_empty() or hashes_differ,
			"a dropped message is detected (diverged=%s, hashes differ=%s)" % [str(remote[0].diverged if remote[0] else null), str(hashes_differ)])
	else:
		_expect(remote[0] != null and not remote[0].diverged, "every replayed decision was the kind the game asked for")
		_expect(b["desyncs"].is_empty(), "no desync reported on machine B %s" % str(b["desyncs"]))
		var h_a: Dictionary = a["hashes"]
		var h_b: Dictionary = b["hashes"]
		var same := 0
		for t in h_a:
			var ok: bool = str(h_a[t]) == str(h_b.get(t, ""))
			print("[Lockstep] turn %d  A %s  B %s  %s" % [t, h_a[t], h_b.get(t, "-"), "ok" if ok else "MISMATCH"])
			if ok:
				same += 1
		_expect(not h_a.is_empty() and same == h_a.size() and h_a.size() == h_b.size(),
			"both machines hash every turn identically (%d / %d)" % [same, h_a.size()])
		if same != h_a.size():
			for line in GAME_SCENE.instantiate().get_script().diff_snapshots(a["snapshot"], b["snapshot"]):
				print("[Lockstep] DIFF " + line)
	print("[Lockstep] %d checks | failures: %d" % [_checks, _fails])
	print("[Lockstep] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
