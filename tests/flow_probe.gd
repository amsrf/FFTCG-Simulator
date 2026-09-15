extends Node3D
## Headless probe for the effect → stack → targeting handoff.
##
## Run it instead of the game:
##   "<godot>" --headless res://tests/flow_probe.tscn --quit-after 5000
##
## Unlike `arrow_probe`, this boots the REAL game scene and drives the actual flow by
## calling functions (headless has no mouse, and the click handlers do nothing except call
## these same functions). Every assertion below is a bug that actually happened:
##
##   1. the effect copy going on the stack and pointing back at the played card
##   2. the targeting arrow coming from the CARD IN THE STACK, not the card on the field
##   3. exactly the legal targets being marked for the criteria
##   4. the arrow's origin tracking the copy's TOP EDGE — and still tracking it after the
##      stack's 0.3 s tween moves it, which is the "origin at the middle of the screen"
##      bug: a captured origin is wrong and stays wrong
#---
## It says nothing about how any of it LOOKS.

const GAME_SCENE := preload("res://game.tscn")
## Card 31 (Chemist) has `when_enter_field` with `choose_target {"is_type": "Forward"}`,
## and it is in the debug preset's opening hand. That preset is unshuffled with a fixed
## seed, so this is stable run to run.
const ETB_CARD_ID := 31

var _failures: Array[String] = []

func _ready() -> void:
	print("\n[FlowProbe] ============== effect -> stack -> target ==============")

	# Deterministic board, fixed seed, no shuffle. The `ai` preset is the debug board with a
	# playable opponent: its hand carries Ifrit (for the summon-cast section below) while the
	# local hand still carries the Chemist the first section needs.
	MatchSetup.config = MatchSetup.build_config("ai")
	# Deliberately untyped: the probe calls the game's own methods dynamically, the same way
	# an agent does.
	var game = GAME_SCENE.instantiate()
	# Plain add_child is enough: Hand, Stack and DamageZone resolve their siblings by
	# walking the tree rather than through get_tree().current_scene (see damage_zone.gd),
	# so the game runs fully wired even though this probe — not the game — is the scene the
	# tree loaded.
	add_child(game)
	await get_tree().process_frame
	# Keep our own camera current so the arrow's screen-space maths is the real one.
	$Camera3D.current = true

	var field = game.get("field")
	var stack = game.get("stack")
	var hand = game.get("hand")
	if field == null or stack == null or hand == null:
		_expect(false, "the game scene exposed field / stack / hand")
		_report()
		get_tree().quit()
		return

	print("[FlowProbe] board: %d field cards, stack %d, hand %s"
		% [field.get_all_cards().size(), stack.cards.size(), _names(hand.cards)])

	var chemist: Card = _find_by_id(hand.cards, ETB_CARD_ID)
	_expect(chemist != null, "the debug opening hand contains card %d" % ETB_CARD_ID)
	if chemist == null:
		_report()
		get_tree().quit()
		return

	# Exactly what Field._on_tween_finished() calls when a played card lands.
	field.execute_card_effect(chemist, "when_enter_field")

	# 1. The effect copy is on the stack, pointing back at the played card.
	_expect(stack.cards.size() == 1, "the ETB put one effect copy on the stack (got %d)" % stack.cards.size())
	var copy: Card = stack.cards.back() if stack.cards.size() > 0 else null
	_expect(copy != null and copy.effect_source == chemist, "the copy's effect_source is the played card")
	if copy == null:
		_report()
		get_tree().quit()
		return

	# 2. The arrow's source is the COPY, not the card on the field.
	var arrow = field.arrow
	_expect(arrow != null, "targeting started an arrow")
	if arrow == null:
		_report()
		get_tree().quit()
		return
	_expect(arrow._source_card == copy,
		"the arrow comes from the effect copy in the stack, not the field card")

	# 3. Exactly the legal targets were marked.
	var valid: Array[String] = []
	var only_forwards: bool = true
	for c in field.get_all_cards():
		if c.is_valid_target:
			valid.append("%s/%s" % [c.card_name, c.type])
			if c.type != "Forward":
				only_forwards = false
	print("[FlowProbe] viable targets: %s" % [valid])
	_expect(valid.size() > 0, "at least one legal target was marked")
	_expect(only_forwards, 'only Forwards are legal for an {"is_type": "Forward"} effect')

	# Picking a target must not leave the orange ring behind when the session ends. This is the
	# bug where a resolved ability's target glowed orange for the rest of the match: the
	# selection ring was set on the click and only ever cleared by the NEXT session starting.
	var pick: Card = null
	for c in field.get_all_cards():
		if c.is_valid_target:
			pick = c
			break
	if pick != null:
		field.set_target_card(pick)
		print("[FlowProbe] picked %s -> orange=%s" % [pick.card_name, pick._selected_highlight_on])
		_expect(pick._selected_highlight_on, "the local player's pick turns orange")
		field.reset_targets()
		print("[FlowProbe] after the session ends: %s orange=%s" % [pick.card_name, pick._selected_highlight_on])
		_expect(not pick._selected_highlight_on,
			"ending the session clears the orange (no permanently glowing card)")

	# 4. The origin sits on the copy's top edge, and keeps sitting there after the stack
	#    tween has moved the copy into place — the fixed behaviour is to RE-READ it.
	print("[FlowProbe] origin now %s | copy top centre %s" % [arrow.start_pos, copy.get_global_top_centre()])
	await get_tree().create_timer(0.6).timeout
	print("[FlowProbe] origin after the stack tween %s | copy top centre %s"
		% [arrow.start_pos, copy.get_global_top_centre()])
	_expect(arrow.start_pos.distance_to(copy.get_global_top_centre()) < 0.05,
		"the origin is still on the copy's top edge once it has settled")

	# Move the copy deterministically, so this can never pass by accident.
	copy.global_position = copy.global_position + Vector3(0.0, 0.0, 0.4)
	arrow._process(0.0)
	print("[FlowProbe] after moving the copy 0.40 m: origin %s | copy top centre %s"
		% [arrow.start_pos, copy.get_global_top_centre()])
	_expect(arrow.start_pos.distance_to(copy.get_global_top_centre()) < 0.05,
		"the origin follows the copy when it moves")
	_expect(copy.get_global_top_centre().distance_to(copy.global_position) > 0.1,
		"the origin uses the card's TOP edge, not its centre")

	# ---- The OPPONENT casts a Summon. Two things must hold: the arc comes from the card in
	# ---- the stack, and a choice that is not ours never puts the blue ring on our cards.
	var opponent_hand = game.get("opponent_hand")
	var ifrit: Card = _find_by_id(opponent_hand.cards, 4)
	_expect(ifrit != null, "the opponent's hand contains Ifrit")
	if ifrit != null:
		await game.play_card_for(2, ifrit)
		# The AI picks through its agent, which may finish a frame later.
		await get_tree().process_frame
		await get_tree().process_frame
		var summon_arc = field.arrow
		var source_card: Card = summon_arc._source_card if summon_arc != null else null
		print("[FlowProbe] summon cast: stack.cards=%d | arc source=%s | source parent=%s"
			% [stack.cards.size(), source_card.card_name if source_card != null else "<none>",
			source_card.get_parent().name if (source_card != null and source_card.get_parent() != null) else "<none>"])
		if source_card != null:
			var source_top: Vector3 = source_card.get_global_top_centre()
			print("[FlowProbe] source at %s (top centre %s) | arc origin %s | opponent hand at %s"
				% [source_card.global_position, source_top, summon_arc.start_pos,
				game.get("opponent_hand").global_position])
			_expect(source_card.get_parent() == stack,
				"the arc originates from the card IN THE STACK, not from the opponent's hand")
			_expect(summon_arc.start_pos.distance_to(Vector3.ZERO) > 0.15,
				"the origin is not at the world origin (which projects to the screen centre)")
			# The RIBBON is what the player sees, so assert on the MESH once the card has
			# settled, not on `start_pos` mid-tween. The AI locks its target a frame or two
			# after the cast, while the Summon is still travelling from its owner's hand —
			# so a mesh built only at lock time would stay anchored back there.
			await get_tree().create_timer(0.6).timeout
			var shaft_start: Vector3 = summon_arc.line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
			print("[FlowProbe] after 0.6 s: start_pos %s | drawn ribbon starts %s | card top centre %s | locked=%s"
				% [summon_arc.start_pos, shaft_start, source_card.get_global_top_centre(), summon_arc.locked])
			_expect(shaft_start.distance_to(source_card.get_global_top_centre()) < 0.1,
				"the DRAWN ribbon starts at the card's top edge once it has settled")

		var blue: Array[String] = []
		for c in field.get_all_cards():
			# "Blue" is a prompt ring WITHOUT red, orange or green claiming the card:
			# `_highlight_on` alone only means "some ring is on", which is how this check
			# passed for the wrong reason once the red reveal started lighting one.
			if c._highlight_on and not c._targeted_highlight_on and not c._selected_highlight_on \
					and not c._available_highlight_on:
				blue.append(c.card_name)
		print("[FlowProbe] glowing blue during the opponent's targeting: %s" % [blue])
		_expect(blue.is_empty(), "no blue ring appears while the OPPONENT is choosing")

		# GREEN = "you may activate this right now". It must be OFF while a modal owns the
		# moment (you cannot start an ability mid-targeting), and come back afterwards — and
		# it is the local player's cards only, never the opponent's.
		field.refresh_available_effects()
		var green_open: Array[String] = []
		for c in field.get_all_cards():
			if c._available_highlight_on:
				green_open.append(c.card_name)
		print("[FlowProbe] green with the targeting modal open: %s" % [green_open])
		_expect(green_open.is_empty(), "no green ring while a modal owns the moment")

		# The probe owns the mode here, so closing the session manually is how the state the
		# real flow reaches after Confirm gets reproduced.
		GlobalVariables.pop_modal(GlobalVariables.Player_Mode.TARGET)

		# With the modal closed, the WINDOW is what decides: while the opponent holds priority
		# the input mode is still FREE/INSTANT_SPEED_TIME, so only a priority check keeps the
		# green off — the case the mode check alone cannot catch.
		field.refresh_available_effects()
		var green_ours: int = 0
		for c in field.get_all_cards():
			if c._available_highlight_on:
				green_ours += 1
		var saved_holder: int = int(game.get("priority_holder"))
		game.set("priority_holder", 2)
		field.refresh_available_effects()
		var green_theirs: int = 0
		for c in field.get_all_cards():
			if c._available_highlight_on:
				green_theirs += 1
		game.set("priority_holder", saved_holder)
		print("[FlowProbe] green with the modal closed: ours=%d | while the OPPONENT holds the window=%d"
			% [green_ours, green_theirs])
		_expect(green_ours > 0, "green appears on our activatable cards while WE hold the window")
		_expect(green_theirs == 0, "no green while the OPPONENT holds the window (same input mode)")

		field.refresh_available_effects()
		var red_mage: Card = null
		var theirs_green: bool = false
		for c in field.get_all_cards():
			if c.controller == "player" and c.id == 3:
				red_mage = c
			elif c.controller != "player" and c._available_highlight_on:
				theirs_green = true
		print("[FlowProbe] green with nothing pending: red mage=%s (lit=%s) | any opponent green=%s"
			% [red_mage != null,
			red_mage._available_highlight_on if red_mage != null else false,
			theirs_green])
		_expect(red_mage != null and red_mage._available_highlight_on,
			"the local player's activatable Backup goes green once nothing is pending")
		_expect(not theirs_green, "no opponent card is ever green")

		# The green is a STANDING cue, so it is drawn at half the ring's width — and every
		# other state has to restore the stock width exactly when it takes over.
		if red_mage != null:
			var green_width: float = float(red_mage._border_material.get_shader_parameter("border_width"))
			print("[FlowProbe] ring width: green=%.4f | stock=%.4f (scale %.2f)"
				% [green_width, red_mage._border_width_base, Card.AVAILABLE_WIDTH_SCALE])
			_expect(green_width < red_mage._border_width_base,
				"the green ring is drawn thinner than the others")
			red_mage.set_available_highlight(false)
			red_mage.set_prompt_glow(true)
			var other_width: float = float(red_mage._border_material.get_shader_parameter("border_width"))
			print("[FlowProbe] ring width with the prompt on instead: %.4f" % other_width)
			_expect(is_equal_approx(other_width, red_mage._border_width_base),
				"any other state restores the stock ring width")
			red_mage.set_prompt_glow(false)

		# --- the stack as a fan: top of the stack at the LEFT, older cards stepping right ---
		await get_tree().create_timer(0.4).timeout
		_expect(stack.cards.size() >= 2, "there are at least two cards on the stack to fan")
		if stack.cards.size() >= 2:
			var top: Card = stack.cards.back()
			var oldest: Card = stack.cards.front()
			print("[FlowProbe] stack fan: top(%s).x=%.3f | oldest(%s).x=%.3f | tilts %.3f / %.3f"
				% [top.card_name, top.position.x, oldest.card_name, oldest.position.x,
				top.rotation.y, oldest.rotation.y])
			_expect(top.position.x < oldest.position.x,
				"the TOP of the stack sits at the LEFT end of the fan")
			_expect(absf(top.rotation.y) + absf(oldest.rotation.y) > 0.0001,
				"the fan tilts its cards")
			var top_y: float = top.position.y
			stack.select_card(oldest)
			await get_tree().create_timer(0.4).timeout
			print("[FlowProbe] selecting the oldest card: y %.4f (top is at %.4f)"
				% [oldest.position.y, top_y])
			_expect(stack.selected_or_top() == oldest, "clicking an older card selects it")
			_expect(oldest.position.y > top.position.y,
				"the selected card is raised above the rest of the fan")
			stack.select_top()
			await get_tree().create_timer(0.4).timeout
			_expect(stack.selected_or_top() == stack.cards.back(),
				"select_top() returns the display to the top of the stack")

			# --- the review link: hovering a stack card shows ITS target, else the top's ---
			var mine: Card = null
			var theirs: Card = null
			for c in field.get_all_cards():
				if c.type == "Forward" and c.can_attack():
					if c.controller == "player" and mine == null:
						mine = c
					elif c.controller != "player" and theirs == null:
						theirs = c
			if mine != null and theirs != null:
				# Stood up directly: this section tests the DISPLAY, not how a target gets
				# attached — the earlier sections already exercised that path.
				oldest.effect_target = mine
				top.effect_target = theirs
				stack.refresh_target_display()
				# The reveal (red, held until the stack resolves) must SURVIVE the review link.
				# The link draws an arrow ONLY: an earlier version painted the aura too, and
				# stole the reveal's ring, because both writers lit the same card.
				var revealed: Card = field.target_card
				stack.refresh_target_display()
				print("[FlowProbe] no hover -> display=%s | arrow aiming=%s | reveal red=%s"
					% [stack.displayed_card().card_name,
					field.review_arrow.is_aiming if field.review_arrow != null else false,
					revealed._targeted_highlight_on if revealed != null else false])
				_expect(stack.displayed_card() == top,
					"with no hover, the link shown is the TOP card's")
				_expect(field.review_arrow != null and field.review_arrow.is_aiming,
					"the top card's review link is actually drawn")
				# WHERE the arc is drawn, not merely that it exists. The arrow treats its points as
				# LOCAL, so parenting it to the lifted, flipped stack put it in "random places".
				# Assert on the MESH: its first vertex must sit at the stack card's top edge.
				var want_start: Vector3 = top.get_global_top_centre()
				var drawn_start: Vector3 = (field.review_arrow.line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
				print("[FlowProbe] review arc starts at %s | the stack card's top is %s | gap %.4f"
					% [drawn_start, want_start, drawn_start.distance_to(want_start)])
				_expect(drawn_start.distance_to(want_start) < 0.2,
					"the review arc is drawn AT the stack card, not offset by the stack transform")
				_expect(revealed != null and revealed._targeted_highlight_on,
					"the review link does not disturb the reveal's ring")
				stack.set_hovered(oldest, true)
				print("[FlowProbe] hovering %s -> display=%s | reveal still red=%s"
					% [oldest.card_name, stack.displayed_card().card_name,
					revealed._targeted_highlight_on if revealed != null else false])
				_expect(stack.displayed_card() == oldest,
					"hovering an older card shows ITS link")
				var want_hovered: Vector3 = oldest.get_global_top_centre()
				var hovered_start: Vector3 = (field.review_arrow.line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
				print("[FlowProbe] re-aimed arc starts at %s | %s's top is %s | gap %.4f"
					% [hovered_start, oldest.card_name, want_hovered,
					hovered_start.distance_to(want_hovered)])
				_expect(hovered_start.distance_to(want_hovered) < 0.2,
					"hovering re-aims the arc onto THAT card, from its own top edge")
				_expect(revealed != null and revealed._targeted_highlight_on,
					"and the reveal is still untouched while reviewing")
				_expect(not theirs._targeted_highlight_on,
					"the aura follows the hover — the previous target is cleared")
				stack.set_hovered(oldest, false)
				_expect(stack.displayed_card() == top,
					"leaving the card restores the top of the stack")

		var chosen: Card = field.target_card
		print("[FlowProbe] opponent chose %s (red=%s, orange=%s)"
			% [chosen.card_name if chosen != null else "<none>",
			chosen._targeted_highlight_on if chosen != null else false,
			chosen._selected_highlight_on if chosen != null else false])
		_expect(chosen != null and chosen._targeted_highlight_on,
			"the card the opponent picked is marked RED")
		_expect(chosen == null or not chosen._selected_highlight_on,
			"and it does not carry the local player's orange")
		# The bug that shipped to the user: the STATE was set and the colour swapped, but the
		# ring was never lit, so nothing appeared on screen. Assert the rendered state too.
		print("[FlowProbe] rendered ring on the chosen card: lit=%s (red=%s, orange=%s)"
			% [chosen._highlight_on if chosen != null else false,
			chosen._targeted_highlight_on if chosen != null else false,
			chosen._selected_highlight_on if chosen != null else false])
		_expect(chosen != null and chosen._highlight_on,
			"the red ring is LIT on screen, not merely recoloured")

		# Timing measurement: how long is the reveal actually visible? The AI confirms its
		# pick a frame or two after casting, so this is the window the human actually gets.
		await get_tree().create_timer(0.8).timeout
		print("[FlowProbe] red ring +0.8 s: chosen=%s | red=%s | stack.cards=%d | priority_holder=%s"
			% [chosen.card_name if chosen != null else "<none>",
			chosen._targeted_highlight_on if chosen != null else false,
			stack.cards.size(), game.priority_holder])
		_expect(chosen == null or chosen._targeted_highlight_on,
			"the reveal is still up while the stack resolves, so the human can read it")

		# ...and it must not outlive the reveal: cleared once the stack empties, and dropped
		# when the card changes zone (or a red ring would ride into the graveyard).
		field.clear_targeted_highlights()
		_expect(chosen == null or not chosen._targeted_highlight_on,
			"clear_targeted_highlights() ends the reveal")
		if chosen != null:
			chosen.set_targeted_highlight(true)
			chosen.enter_zone(Card.Zone.GRAVEYARD)
			_expect(not chosen._targeted_highlight_on,
				"a card changing zone drops the red ring, so none is left in the graveyard")

	_report()
	get_tree().quit()

func _find_by_id(cards: Array, card_id: int) -> Card:
	for c in cards:
		if c != null and c.id == card_id:
			return c
	return null

func _names(cards: Array) -> String:
	var out: Array[String] = []
	for c in cards:
		if c != null:
			out.append(str(c.id))
	return str(out)

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("[FlowProbe]  ok  %s" % what)
	else:
		_failures.append(what)
		print("[FlowProbe] FAIL %s" % what)

func _report() -> void:
	if _failures.is_empty():
		print("[FlowProbe] RESULT: all checks passed\n")
		return
	print("[FlowProbe] RESULT: %d check(s) FAILED" % _failures.size())
	for f in _failures:
		print("[FlowProbe]   x %s" % f)
	print("")
