extends Node
## AERITH'S SKILL, END TO END — does the activation leave the stack?
##
## The report: discard the Aerith, press Discard, the effect goes on the stack, press Confirm ... and it stays there and the
## game hangs. This drives exactly that sequence and prints the state after each step, so the step where it stops is
## visible rather than guessed at.
##
## THE DECISIVE PART: the player's agent is swapped for a MockAgent, so the priority round passes on its own. If the flow
## completes that way, the stall is in the HUMAN input path (the pass button / the mode); if it still stalls, it is in the
## resolution itself. Either way the answer comes from a run, not from reasoning about the code.
##
##   godot --headless res://tests/skill_flow_probe.tscn --quit-after 2000

const GAME_SCENE := preload("res://game.tscn")
const MOCK_AGENT := preload("res://scripts/agents/mock_agent.gd")

var _checks: int = 0
var _fails: int = 0
var _done: bool = false

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SkillFlow] ok   ", what)
	else:
		_fails += 1
		print("[SkillFlow] FAIL ", what)

## The preset to run against. "ai" is what the user actually plays; it differs from "debug" in one way that matters here —
## its opponent is an AIAgent rather than a MockAgent — and that difference was never controlled for. Pass the preset on the
## command line to compare: -- ai
var _preset: String = "debug"

func _report(tag: String, stack, proxy, source) -> void:
	# THE MODE AND THE MODAL STACK ON EVERY STEP. "Stuck in a modal" is the obvious shape for this bug, and the pass button
	# hides itself in PAYING_COST / TARGET / CHOOSE_CARD_IN_HAND / NO_PRIORITY — so if the mode is modal when the priority
	# round starts, the human has nothing to press and the effect never resolves.
	print("[SkillFlow] %-22s proxy_in_cards=%s stack_len=%d s_cost_used=%s tapped=%s | mode=%s modal=%s top=%s" % [
		tag, proxy != null and proxy in stack.cards, stack.stack_length(),
		stack.s_cost_selected_card != null, source.tapped,
		GlobalVariables.get_player_mode(), GlobalVariables.has_modal(),
		GlobalVariables.modal_top() if GlobalVariables.has_modal() else "-"])

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_preset = str(arg)
	print("[SkillFlow] preset=%s" % _preset)
	MatchSetup.config = MatchSetup.build_config(_preset)
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# NO HUMAN. Every priority round passes itself, so a stall can only be the resolution.
	# THE REAL AGENTS ARE KEPT. Swapping in mocks made the resolution pass, which proved the resolution is not the problem
	# — the stall is in the HUMAN input path, so that is what this drives: a pass emitted the way the pass button emits it.
	var field = game.field
	var hand = game.hand
	var stack = game.stack
	var assistant_node = game.assistant
	game.priority_holder = 1

	var source: Card = game.create_card(64, "player")
	field.add_child(source)
	field.play_card(source, false, false)
	var sacrifice: Card = null
	for c in hand.cards:
		if c.card_name == "Aerith":
			sacrifice = c
	_expect(sacrifice != null and source != null, "Aerith is on the field with another in hand")
	if sacrifice == null:
		_finish()
		return

	field.begin_skill_activation(source, 0)
	_report("after activation", stack, stack.skill_activation_proxy, source)
	_expect(stack.skill_activation_proxy != null, "activating puts the proxy on the stack")
	_expect(stack.skill_activation_proxy in stack.cards, "and it is a legal stack object")

	hand.toggle_effect_card_selection(sacrifice)
	stack._on_choose_card_finished(true)
	_report("after Discard", stack, stack.skill_activation_proxy, source)
	_expect(stack.s_cost_selected_card == sacrifice, "the s cost is recorded")

	# TAP THE FORWARDS NOW, so the untap is observable. Left untapped they are already upright, and "still untapped after
	# the effect" would pass without the effect doing anything — which is exactly how a missing untap slipped through.
	var tapped_before: int = 0
	for c in field.get_front_cards_for("player"):
		if not c.tapped:
			c.tap()
			tapped_before += 1
	print("[SkillFlow] tapped %d player Forward(s) before the effect resolves" % tapped_before)
	_expect(tapped_before > 0, "there is at least one player Forward to watch untap")

	# THE CONFIRM. This is the press that is supposed to commit and start the resolution.
	stack.confirm_skill_without_target_then_priority()
	_report("after Confirm", stack, stack.skill_activation_proxy, source)
	_expect(not sacrifice in hand.cards, "the s-cost card is discarded from hand")

	# --- THE HUMAN PATH, which is where the report actually is ----------------------------------------------
	# The priority round is now waiting on the LOCAL player to pass. The reported bug was that the confirm just pressed was
	# still standing, in the same slot the pass button uses — so the pass button never appeared and the game looked frozen
	# with the effect on the stack. So: check the button, then pass the way the pass button passes.
	await get_tree().process_frame
	await get_tree().process_frame
	var confirm_visible: bool = assistant_node != null and assistant_node.confirmButton.visible
	print("[SkillFlow] with priority waiting: confirm_button_visible=%s" % confirm_visible)
	_expect(not confirm_visible,
		"the confirm that started this is GONE — left up, it hides the pass button and the game looks frozen")
	if assistant_node != null:
		assistant_node.pressed_pass_priority.emit()
	# MODEL THE HUMAN: press the PASS button whenever it is up, and count whether it ever appears.
	#
	# passPhaseButton, NOT confirmButton — they are separate nodes, and checking the confirm told me nothing about the pass
	# button. That is what produced the previous run's "seen 0 times" and made me report a false finding.
	var passes: int = 0
	var button_seen: int = 0
	var waited: float = 0.0
	while stack.stack_length() > 0 and waited < 4.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if assistant_node != null and assistant_node.passPhaseButton.visible:
			button_seen += 1
			assistant_node.pressed_pass_priority.emit()
			passes += 1
	print("[SkillFlow] pass button: seen %d time(s), pressed %d time(s), waited %.1fs, stack_len=%d, mode=%s, confirm=%s" % [
		button_seen, passes, waited, stack.stack_length(), GlobalVariables.get_player_mode(),
		assistant_node.confirmButton.visible if assistant_node != null else "?"])
	_expect(button_seen > 0,
		"the pass button APPEARS while priority is waiting — a human has to be able to pass to resolve this")
	_expect(stack.stack_length() == 0, "THE STACK EMPTIES — the effect resolves and leaves, which is the whole report")

	# And the effect actually happened: every player Forward should now carry the granted immunity AND be upright again.
	var granted: int = 0
	var still_tapped: int = 0
	for c in field.get_front_cards_for("player"):
		if c.status_effects.has("cannot_be_chosen"):
			granted += 1
		if c.tapped:
			still_tapped += 1
	print("[SkillFlow] player Forwards carrying the grant: %d | still tapped: %d" % [granted, still_tapped])
	_expect(granted > 0, "and the grant reached the player's Forwards")
	_expect(still_tapped == 0, "AND THE UNTAP HAPPENED — they were tapped before the effect resolved")

	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	print("[SkillFlow] %d checks | failures: %d" % [_checks, _fails])
	print("[SkillFlow] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
