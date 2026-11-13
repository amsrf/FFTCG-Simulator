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

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")
const EVENTS := preload("res://scripts/effects/events.gd")
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
	var board_visual = game.get_node("Board/MeshInstance3D")
	_expect(board_visual.mesh != null and board_visual.mesh.get_surface_count() == 1,
		"the scenery geometry loads on the existing Board node path")
	_expect(not game.get_node("Field/MeshInstance3D").visible,
		"the old purple field surface does not cover the scenery")
	_expect(board_visual.displayed_seat == game.local_seat,
		"board scenery follows the configured local seat")
	var first_board_mesh = board_visual.mesh
	_expect(board_visual.river != null and board_visual.river.mesh != null,
		"the river loads as independent scenery geometry")
	var first_water = board_visual.river.mesh.surface_get_material(0)
	_expect(is_equal_approx(first_water.get_shader_parameter("flow_direction"), 1.0),
		"seat one river follows the world flow direction")
	board_visual.configure_seat(2)
	_expect(board_visual.displayed_seat == 2 and board_visual.mesh != first_board_mesh,
		"seat two loads the opposite biome view")
	var second_water = board_visual.river.mesh.surface_get_material(0)
	_expect(is_equal_approx(second_water.get_shader_parameter("flow_direction"), -1.0),
		"seat two river reverses its screen flow for the same world current")
	board_visual.configure_seat(game.local_seat)
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

	# FIVE BACKUPS AT MOST (7.7.4): the AI board already fields five, so casting this Backup would be refused. Make room.
	# A plain one: the activatable Backups (Aerith) are what the availability checks below are about.
	var backups: Array = field.get_back_cards_for(Card.PLAYER).filter(func(b): return b.activation_skills().is_empty())
	if field.get_back_cards_for(Card.PLAYER).size() >= game.MAX_BACKUPS and not backups.is_empty():
		game.put_card_into_graveyard(backups[backups.size() - 1])
		# Setup, not under test: let its tribute (orb burst + flight to the pile) finish before the timed checks below.
		await Vfx.idle()
		await get_tree().process_frame

	# Character drag has two states: ordinary drag inside the hand band, and the
	# latched cast stance once the pointer crosses above it.
	var screen_size := get_viewport().get_visible_rect().size
	var in_hand_band := screen_size * Vector2(0.5, 0.9)
	var above_band := screen_size * Vector2(0.5, 0.1)
	hand.set_hovered(chemist, true)
	var before_lift := chemist.global_position.y
	hand.begin_character_drag(chemist)
	hand._character_drag_start_pointer_y = in_hand_band.y
	_expect(chemist.global_position.y > before_lift, "Character grab lifts immediately in world Y")
	_expect(hand._card_screen_rect(chemist).end.y > screen_size.y, "Character grab starts with its bottom below the screen")
	var lifted_pose := chemist.global_transform
	hand.update_character_drag(chemist, screen_size * Vector2(0.5, 0.84))
	_expect(not chemist.global_transform.is_equal_approx(lifted_pose) and not hand.character_drag_latched(),
		"partial upward drag moves and pitches before reaching the final stance")
	_expect(not chemist.ring_cast_pending(), "partial pitch has no cast-ready gold aura")
	hand.update_character_drag(chemist, screen_size * Vector2(0.5, hand.character_drag_trigger_y))
	_expect(hand.character_drag_latched() and chemist.ring_cast_pending(), "full pitch and gold aura coincide with the cast boundary")
	var boundary_bottom: float = hand._card_screen_rect(chemist).end.y
	_expect(absf(boundary_bottom - screen_size.y * 0.94) < 1.0, "cast boundary leaves a small bottom margin")
	hand.update_character_drag(chemist, screen_size * Vector2(0.5, hand.character_drag_trigger_y - 0.08))
	_expect(absf(hand._card_screen_rect(chemist).end.y - boundary_bottom) < 1.0 and chemist.ring_cast_pending(),
		"full rotation and maximum bottom gap are reached together")
	_expect(chemist.global_basis.get_scale().x < lifted_pose.basis.get_scale().x,
		"casting preview shrinks from the enlarged hand preview")
	_expect(hand.update_character_drag(chemist, above_band) and hand.character_drag_latched(),
		"crossing above the hand band latches the cast stance")
	_expect(absf(hand._card_screen_rect(chemist).end.y - screen_size.y * 0.94) < 1.0, "full casting pose places the bottom edge at the screen boundary")
	var preview_pose := chemist.global_transform
	var cam_basis: Basis = get_viewport().get_camera_3d().global_transform.basis.orthonormalized()
	var expected_basis := Basis(cam_basis.x, cam_basis.z, -cam_basis.y) * Basis(Vector3.RIGHT, deg_to_rad(hand.character_drag_pitch_degrees))
	_expect(chemist.global_basis.orthonormalized().is_equal_approx(expected_basis.orthonormalized()),
		"the latched card is screen-facing with the negative X pitch")
	var face_normal := chemist.global_basis.y.normalized()
	_expect(face_normal.dot(cam_basis.z) < 0.75 and face_normal.dot(cam_basis.y) > 0.5,
		"casting pose visibly lays back with its top edge receding from the camera")
	hand.update_character_drag(chemist, screen_size * Vector2(0.85, 0.1))
	_expect(chemist.global_transform.is_equal_approx(preview_pose),
		"a latched Character stance does not move horizontally")
	_expect(hand.update_character_drag(chemist, in_hand_band) and not hand.character_drag_latched(),
		"returning to the hand band before payment resumes the normal drag")
	_expect(not chemist.ring_cast_pending(), "retreating below the cast boundary removes the gold aura")
	# Re-latch and verify that payment keeps this pose without parking it in the Stack.
	hand.update_character_drag(chemist, above_band)
	var stance_pose := chemist.global_transform
	var original_hand_index: int = hand.cards.find(chemist)
	hand.remove_card(chemist)
	hand.charging_card = chemist
	stack._on_hand_charge_start(chemist)
	_expect(chemist.global_transform.is_equal_approx(stance_pose) and not stack.layout_cards().has(chemist),
		"Character payment keeps the cast stance and stays out of the stack fan")
	_expect(chemist.get_parent() == hand and chemist.current_zone != Card.Zone.STACK,
		"Character payment does not park the card in the Stack")
	stack._on_assistant_charge_cancelled()
	hand._on_assistant_charge_cancelled()
	_expect(hand.cards.find(chemist) == original_hand_index, "mana cancellation restores the original hand slot")
	_expect(hand.cards.has(chemist) and chemist.current_zone == Card.Zone.HAND,
		"cancelled Character preview returns to hand")

	hand.begin_character_drag(chemist)
	hand._character_drag_start_pointer_y = in_hand_band.y
	hand.update_character_drag(chemist, above_band)
	var still_pose := chemist.global_transform
	hand._update_character_waver(0.4)
	_expect(not chemist.global_transform.is_equal_approx(still_pose) and chemist.global_position.distance_to(still_pose.origin) < 0.015,
		"ready Character gently wavers within a small distance of its baseline")
	hand.begin_character_charge(chemist)
	hand._update_character_waver(0.3)
	_expect(not chemist.global_transform.is_equal_approx(still_pose), "Character waver continues during mana payment")
	hand.end_character_drag(chemist)
	var stopped_pose := chemist.global_transform
	hand._update_character_waver(0.4)
	_expect(chemist.global_transform.is_equal_approx(stopped_pose), "ending the Character preview stops its waver")
	hand.update_card_positions()

	# Exactly what Field.play_card() schedules when a card enters the field.
	field.execute_card_effect(chemist, "when_enter_field")

	# 1. The effect copy is on the stack, pointing back at the played card.
	_expect(stack.cards.size() == 1, "the ETB put one effect copy on the stack (got %d)" % stack.cards.size())
	var copy: Card = stack.cards.back() if stack.cards.size() > 0 else null
	_expect(copy != null and copy.effect_source == chemist, "the copy's effect_source is the played card")
	if copy == null:
		_report()
		get_tree().quit()
		return

	# Code ETBs are resolved by the stack. Start the resolution and wait until the target window opens.
	await get_tree().create_timer(0.1).timeout
	if field.arrow == null and stack.stack_length() > 0:
		stack.resolve_top_effect()
	for _i in range(60):
		if field.arrow != null:
			break
		await get_tree().process_frame

	var arrow = field.arrow
	_expect(arrow != null, "targeting started an arrow")
	if arrow == null:
		_report()
		get_tree().quit()
		return
	_expect(arrow._source_card == copy,
		"the arrow comes from the effect copy in the stack, not the field card")
	# A RESOLVING CARD STAYS ON THE STACK until its effect has fully finished. It used to leave the layout the moment
	# resolution began, so a Gadot vanished before the player had chosen anything.
	_expect(stack.layout_cards().has(copy) and copy.get_parent() == stack,
		"the resolving copy is still laid out on the stack while its choice is open")
	_expect(not stack.cards.has(copy), "the resolving copy is no longer a legal stack object (out of `cards`)")

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

	# Confirm the code-defined ETB so its stack object can finish before the next section begins.
	var etb_assistant = game.get("assistant")
	if etb_assistant != null:
		etb_assistant.call("on_target_complete")
		await get_tree().process_frame
		while stack.stack_length() > 0 or stack.resolution_pending:
			if stack.stack_length() > 0:
				await stack.resolve_top_effect()
			else:
				await stack.resolution_complete
	await get_tree().process_frame
	_expect(not is_instance_valid(copy) or not stack.layout_cards().has(copy),
		"once the effect has resolved, its copy has left the stack layout")

	# ---- The OPPONENT casts a Summon. Two things must hold: the arc comes from the card in
	# ---- the stack, and a choice that is not ours never puts the blue ring on our cards.
	var opponent_hand = game.get("opponent_hand")
	var ifrit: Card = _find_by_id(opponent_hand.cards, 4)
	_expect(ifrit != null, "the opponent's hand contains Ifrit")
	if ifrit != null:
		# The "ai" preset gives the opponent five WIND Evokers so it can cast Valefor.
		# Ifrit costs fire, so add one fire source for this targeted-summon section.
		var fire_source: Card = game.create_card(3, "opponent")
		if fire_source != null:
			game.add_child(fire_source)
			field.play_card(fire_source, true, false, false)
		await game.play_card_for(2, ifrit)
		# The AI picks through its agent, which may finish a frame later.
		await get_tree().process_frame
		await get_tree().process_frame
		# THE OPPONENT'S CHOICE IS PRIVATE: while they pay and aim, the Summon stays face down in their hand and none of
		# their aiming is drawn here.
		var summon_arc = field.arrow
		print("[FlowProbe] opponent summon pending: parent=%s | revealed=%s | aiming arc drawn=%s"
			% [ifrit.get_parent().name, ifrit.revealed,
			summon_arc.is_visible_in_tree() if summon_arc != null and is_instance_valid(summon_arc) else false])
		if stack.summon_casting_card == ifrit:
			_expect(ifrit.get_parent() == opponent_hand and not ifrit.revealed,
				"while the opponent chooses, their Summon waits face down in their hand")
			_expect(summon_arc == null or not is_instance_valid(summon_arc) or not summon_arc.is_visible_in_tree(),
				"and their aiming arc is not drawn on this screen")
		# ...THEN PUBLIC ON THE STACK. Once it has landed, its arrow is drawn from its top edge to what it targets.
		var waited: int = 0
		while (not stack.cards.has(ifrit) or stack._opponent_summon_flight_card == ifrit) and waited < 80:
			await get_tree().create_timer(0.05).timeout
			waited += 1
		await get_tree().create_timer(0.4).timeout
		var landed_target: Card = ifrit.effect_target
		print("[FlowProbe] opponent summon landed: on stack=%s | target=%s | review arrow aiming=%s"
			% [stack.cards.has(ifrit), landed_target.card_name if landed_target != null else "<none>",
			field.review_arrow.is_aiming if field.review_arrow != null else false])
		_expect(stack.cards.has(ifrit) and ifrit.get_parent() == stack and ifrit.revealed,
			"once it commits the Summon is on the stack, face up")
		if landed_target != null and stack.displayed_card() == ifrit:
			_expect(field.review_arrow != null and field.review_arrow.is_aiming,
				"after it lands, the stack shows its arrow")
			var shaft_start: Vector3 = field.review_arrow.line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
			print("[FlowProbe] landed arrow starts %s | card top centre %s" % [shaft_start, ifrit.get_global_top_centre()])
			_expect(shaft_start.distance_to(ifrit.get_global_top_centre()) < 0.15,
				"the DRAWN arrow starts at the stack card's top edge")
			_expect(landed_target._targeted_highlight_on, "and the card it targets carries the red ring")

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
		GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
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
		var green_card: Card = null
		var theirs_green: bool = false
		for c in field.get_all_cards():
			if c.controller == "player" and c._available_highlight_on:
				green_card = c
			elif c.controller != "player" and c._available_highlight_on:
				theirs_green = true
		print("[FlowProbe] green with nothing pending: ours=%s (lit=%s) | any opponent green=%s"
			% [green_card.card_name if green_card != null else "<none>",
			green_card._available_highlight_on if green_card != null else false,
			theirs_green])
		_expect(green_card != null,
			"the local player's activatable card goes green once nothing is pending")
		_expect(not theirs_green, "no opponent card is ever green")

		# The green is a STANDING cue, so it is drawn at half the ring's width — and every
		# other state has to restore the stock width exactly when it takes over.
		if green_card != null:
			var green_width: float = float(green_card._border_material.get_shader_parameter("border_width"))
			print("[FlowProbe] ring width: green=%.4f | stock=%.4f (scale %.2f)"
				% [green_width, green_card._border_width_base, Card.AVAILABLE_WIDTH_SCALE])
			_expect(green_width < green_card._border_width_base,
				"the green ring is drawn thinner than the others")
			green_card.set_available_highlight(false)
			green_card.set_prompt_glow(true)
			var other_width: float = float(green_card._border_material.get_shader_parameter("border_width"))
			print("[FlowProbe] ring width with the prompt on instead: %.4f" % other_width)
			_expect(is_equal_approx(other_width, green_card._border_width_base),
				"any other state restores the stock ring width")
			green_card.set_prompt_glow(false)

		# --- the stack as a fan: top of the stack at the LEFT, older cards stepping right ---
		await get_tree().create_timer(0.4).timeout
		if stack.cards.size() < 2:
			stack.create_card(4, "opponent", "when_cast", null)
			await get_tree().process_frame
		# The new card FLIES in through the presentation queue, behind whatever is still playing (a tribute, say); a
		# card still in flight shows no review link, so wait for it to land rather than for a fixed time.
		await Vfx.idle()
		await get_tree().process_frame
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

	await _check_opponent_translation(game)
	await _check_demo_stack_fan()
	# A fresh, clean board for the simultaneous-trigger check: the AI board above has its own stack history.
	await Vfx.idle()
	game.queue_free()
	await get_tree().process_frame
	await _check_simultaneous_triggers()
	await _check_gadot_played_from_hand()
	await _check_tribute()
	await _check_cost_row()

	_report()
	get_tree().quit()

func _check_demo_stack_fan() -> void:
	var demo = preload("res://tools/opponent_summon_demo.tscn").instantiate()
	add_child(demo)
	for frame in range(6):
		await get_tree().process_frame
	var hand: Hand = demo.opponent_hand
	var stack: Stack = demo.stack
	var count := hand.cards.size()
	for i in range(count):
		var previous_top: Card = stack.cards.back() if not stack.cards.is_empty() else null
		var previous_slot: Vector3 = previous_top.global_position if previous_top != null else Vector3.ZERO
		demo._cast()
		# The flight is queued at the commit: it starts once the presentation queue reaches it.
		var frames: int = 0
		while stack._opponent_summon_flight == null and frames < 60:
			await get_tree().process_frame
			frames += 1
		var flight := stack._opponent_summon_flight
		if flight == null:
			_expect(false, "demo starts flight %d" % (i + 1))
			break
		flight.custom_step(stack.opponent_flight_seconds + 0.001)
		var top: Card = stack.cards.back()
		if previous_top != null:
			previous_top.stack_tween.custom_step(0.31)
			var camera := get_viewport().get_camera_3d()
			_expect(camera.unproject_position(previous_top.global_position).y
				> camera.unproject_position(previous_slot).y,
				"new card pushes the previous top down during flight")
		_expect(stack.cards.size() == i + 1 and hand.cards.size() == count - i - 1
			and top.revealed and top.position.distance_to(stack.calculate_card_position(i)) < 0.001,
			"demo holds %d cards with the latest in its stack slot" % (i + 1))
	demo.game.get_node("Camera3D").current = true
	if stack.cards.size() == count:
		stack.select_card(stack.cards.front())
		for card in stack.cards:
			card.stack_tween.custom_step(0.35)
		var view_camera := get_viewport().get_camera_3d()
		for index in range(count - 1):
			var bottom: Card = stack.cards[index]
			var covering: Card = stack.cards[index + 1]
			var half_edge := Vector3.RIGHT * bottom._card_face_size().x * 0.5
			var left := view_camera.unproject_position(bottom.to_global(-half_edge)).x
			var right := view_camera.unproject_position(bottom.to_global(half_edge)).x
			var cover_edge := view_camera.unproject_position(covering.to_global(half_edge)).x
			var exposed := (right - cover_edge) / (right - left)
			_expect(absf(exposed - stack._stack_spacing(count) / stack.card_width) < 0.002,
				"covered stack card %d exposes the target fraction of its screen width" % (index + 1))
		stack._update_stack_shadows()
		for i in range(1, count):
			var lower: Card = stack.cards[i - 1]
			var upper: Card = stack.cards[i]
			var pose := stack._stack_card_local_basis(lower)
			var offset := upper.position - lower.position
			_expect(absf(offset.dot(pose.y) - stack.FAN_HEIGHT_STEP) < 0.0001
				and view_camera.unproject_position(upper.global_position).y < view_camera.unproject_position(lower.global_position).y - 1.0 and float(lower.mat.get_shader_parameter("shadow_strength")) > 0.0,
				"stack layer %d steps visibly upward while retaining its normal depth" % (i + 1))
		_expect(stack.cards.back().position.is_equal_approx(stack.FAN_ANCHOR), "the newest card occupies the fixed top slot")
		_expect(float(stack.cards.back().mat.get_shader_parameter("shadow_strength")) == 0.0,
			"top stack card receives no overlap shadow")
		var inspected: Card = stack.cards.front()
		var rest_basis := inspected.global_basis
		var slot := inspected.global_position
		var camera := get_viewport().get_camera_3d()
		stack.set_hovered(inspected, true)
		inspected.stack_tween.custom_step(0.05)
		var halfway := inspected.global_position
		_expect(halfway.distance_to(slot) > 0.001, "hover starts moving within 50 ms")
		stack.set_hovered(inspected, false)
		_expect(inspected.global_position.is_equal_approx(slot), "interrupted hover returns to the slot immediately")
		stack.set_hovered(inspected, true)
		inspected.stack_tween.custom_step(0.1)
		stack._update_stack_shadows()
		_expect(camera.global_position.distance_to(inspected.global_position) < camera.global_position.distance_to(slot) - 0.5
			and camera.unproject_position(slot).distance_to(camera.unproject_position(inspected.global_position)) < 1.0
			and float(inspected.mat.get_shader_parameter("shadow_strength")) == 0.0,
			"hover lifts the buried card toward the camera under the cursor")
		_expect(inspected.global_basis.x.normalized().dot(camera.global_basis.x) > 0.999
			and inspected.global_basis.y.normalized().dot(camera.global_basis.z) > 0.999
			and inspected.global_basis.x.length() > rest_basis.x.length() * 1.35,
			"stack hover presents an enlarged upright card")
		stack.set_hovered(inspected, false)
		_expect(inspected.global_basis.is_equal_approx(rest_basis), "hover exit restores the fan tilt and size")
		_expect(stack._stack_spacing(2) > stack._stack_spacing(5), "larger stacks tighten the fan spacing")
		_expect(inspected.global_position.distance_to(slot) < 0.001, "leaving the card restores its stack slot immediately")
	demo._preview_ability(3)
	var ability_copy: Card = stack.cards.back()
	var face := ability_copy.get_node_or_null("StackAbilityFace") as SubViewport
	_expect(face != null and face.get_node("Ability").text.replace("\n", " ") == "Choose 1 Forward. It cannot block this turn."
		and ability_copy.mat.get_shader_parameter("texture_albedo") == face.get_texture()
		and not ability_copy.effect_source.has_node("StackAbilityFace"), "Red Mage proxy displays only the chosen effect on its own face")
	demo._preview_ability(100)
	var earth := stack.cards.back() as Card
	var earth_face := earth.get_node("StackAbilityFace")
	_expect(earth_face.get_node("Panel").texture != face.get_node("Panel").texture
		and earth_face.get_node("Ability").text.begins_with("Choose 1 Forward blocking."),
		"Earth ability has its own palette and cost-free effect text")
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.PAYING_COST)
	var local_hand: Hand = demo.game.get_node("Player/Hand")
	var local_summon: Card = demo.game.create_card(62, "player")
	local_hand.add_card(local_summon)
	local_hand.begin_character_drag(local_summon)
	local_hand._character_drag_start_pointer_y = get_viewport().get_visible_rect().size.y * 0.9
	local_hand.update_character_drag(local_summon, get_viewport().get_visible_rect().size * Vector2(0.5, 0.1))
	var printed_face = local_summon.mat.get_shader_parameter("texture_albedo")
	local_hand.remove_card(local_summon)
	local_hand.charging_card = local_summon
	stack._on_hand_charge_start(local_summon)
	local_hand.begin_character_charge(local_summon)
	_expect(local_summon.get_parent() == local_hand and local_summon.current_zone == Card.Zone.HAND
		and local_summon.mat.get_shader_parameter("texture_albedo") == printed_face,
		"local Summon keeps its printed drag preview through payment and targeting")
	local_summon.set_effect_targets([demo.game.get_node("Field").get_all_cards().front()])
	var picked := local_summon.effect_targets.duplicate()
	var previous_local_top: Card = stack.cards.back()
	var previous_local_top_position := previous_local_top.position
	stack._commit_summon_to_stack()
	# RULES AT ONCE: the stack already holds the separate effect card (same picks); the printed card only fades.
	_expect(not stack.cards.has(local_summon) and stack.cards.back() != local_summon
		and stack.cards.back().effect_targets == picked and local_summon.get_parent() == local_hand,
		"confirmed local Summon commits at once as a new stack card while its printed preview fades in place")
	local_summon.teleport.tween.custom_step(0.30)
	var printed_summon := local_summon
	local_summon = stack.cards.back()
	_expect(local_summon != printed_summon and printed_summon.is_queued_for_deletion(),
		"local entrance creates a new stack card after fading the printed card")
	var entrance_camera := get_viewport().get_camera_3d()
	var entrance_screen := entrance_camera.unproject_position(local_summon.global_position)
	var entrance_size := get_viewport().get_visible_rect().size
	_expect(absf(entrance_screen.x - entrance_size.x * 0.5) < 1.0 and entrance_screen.y > entrance_size.y,
		"local effect card enters from below screen at horizontal center")
	_expect(previous_local_top.stack_tween != null, "local entrance starts shifting the existing stack at launch")
	if previous_local_top.stack_tween != null:
		previous_local_top.stack_tween.custom_step(0.15)
		var shifted_slot := stack.calculate_card_position(previous_local_top.index)
		_expect(previous_local_top.position.distance_to(previous_local_top_position) > 0.001
			and previous_local_top.position.distance_to(shifted_slot) < previous_local_top_position.distance_to(shifted_slot)
			and stack._local_summon_presentation == local_summon,
			"existing stack moves toward its new slots while the local effect card is still arriving")
	var entrance: Tween = stack._opponent_summon_flight
	_expect(entrance != null and local_summon.get_parent() == stack and local_summon.current_zone == Card.Zone.STACK,
		"local Summon changes to its stack face for the separate entrance")
	if entrance != null:
		var destination := stack.to_global(stack.calculate_card_position(local_summon.index))
		var destination_screen := entrance_camera.unproject_position(destination)
		_expect(local_summon.global_basis.y.normalized().dot(entrance_camera.global_basis.z) < -0.9, "local Summon starts with its back toward the camera")
		_expect(local_summon.global_basis.z.normalized().dot(entrance_camera.global_basis.y) > 0.9, "local Summon launches upside down with its bottom pointing up the screen")
		var highest_y := entrance_screen.y
		var has_descent := false
		var apex_facing := 1.0
		var apex_pitch_up := 0.0
		var previous_screen := entrance_screen
		var previous_rotation := local_summon.quaternion
		var continuous := true
		var captured_poses: Array = []
		var late_distance := 0.0
		var preceding_distance := 0.0
		var clears_existing_stack := true
		var late_rotation := 0.0
		var preceding_rotation := 0.0
		for _frame in range(49):
			entrance.custom_step(1.0 / 60.0)
			var screen := entrance_camera.unproject_position(local_summon.global_position)
			var stack_normal := (stack.global_basis.orthonormalized() * stack._stack_card_local_basis(local_summon)).y.normalized()
			var moving_bottom: float = stack._card_face_depth_range(local_summon, stack_normal).x
			for existing in stack.cards:
				if existing != local_summon:
					clears_existing_stack = clears_existing_stack and moving_bottom >= stack._card_face_depth_range(existing, stack_normal).y + 0.002

			if _frame == 19:
				var half_face := local_summon._card_face_size() * 0.5
				var top_mid := entrance_camera.unproject_position(local_summon.hand_mesh.to_global(Vector3(0, 0, -half_face.y)))
				var bottom_mid := entrance_camera.unproject_position(local_summon.hand_mesh.to_global(Vector3(0, 0, half_face.y)))
				var final_transform := stack.global_transform * Transform3D(stack._stack_card_local_basis(local_summon).scaled(Vector3.ONE * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE)), stack.calculate_card_position(local_summon.index)) * local_summon.hand_mesh.transform
				var final_top := entrance_camera.unproject_position(final_transform * Vector3(0, 0, -half_face.y))
				var final_bottom := entrance_camera.unproject_position(final_transform * Vector3(0, 0, half_face.y))
				_expect(absf(bottom_mid.y - top_mid.y) < absf(final_bottom.y - final_top.y) * 0.85,
					"early descent stays visibly foreshortened before opening to full height")
			if _frame == 25:
				var half_size := local_summon._card_face_size() * 0.5
				var top_left := entrance_camera.unproject_position(local_summon.hand_mesh.to_global(Vector3(-half_size.x, 0, -half_size.y)))
				var top_right := entrance_camera.unproject_position(local_summon.hand_mesh.to_global(Vector3(half_size.x, 0, -half_size.y)))
				_expect(absf((top_right - top_left).normalized().y) < 0.15,
					"by frame 26 the card top is nearly level while the face continues opening")
			if _frame == 31:
				var remaining_angle := local_summon.quaternion.angle_to(stack._stack_card_local_basis(local_summon).get_rotation_quaternion())
				_expect(remaining_angle > deg_to_rad(3.0) and remaining_angle < deg_to_rad(30.0),
					"card is still unfolding at frame 32 instead of already matching the final pose")
			if _frame == 43:
				_expect(local_summon.quaternion.angle_to(stack._stack_card_local_basis(local_summon).get_rotation_quaternion()) < deg_to_rad(2.0),
					"only a small orientation adjustment remains in the final six frames")
			if OS.get_cmdline_user_args().has("--capture-local-flight"):
				var half := local_summon._card_face_size() * 0.5
				var corners: Array = []
				for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
					var projected := entrance_camera.unproject_position(local_summon.hand_mesh.to_global(corner))
					corners.append([projected.x, projected.y])
				captured_poses.append({"frame": _frame + 1, "corners": corners, "angle_to_final": rad_to_deg(local_summon.quaternion.angle_to(stack._stack_card_local_basis(local_summon).get_rotation_quaternion()))})
			if _frame > 3 and _frame < 27:
				continuous = continuous and screen.distance_to(previous_screen) > 0.01 and local_summon.quaternion.angle_to(previous_rotation) > 0.0001
			if _frame >= 39:
				late_distance += screen.distance_to(previous_screen)
				late_rotation += local_summon.quaternion.angle_to(previous_rotation)
			elif _frame >= 29:
				preceding_distance += screen.distance_to(previous_screen)
				preceding_rotation += local_summon.quaternion.angle_to(previous_rotation)
			previous_screen = screen
			previous_rotation = local_summon.quaternion

			has_descent = has_descent or screen.y > highest_y + 2.0
			highest_y = minf(highest_y, screen.y)
			var facing_amount := absf(local_summon.global_basis.y.normalized().dot(entrance_camera.global_basis.z))
			if facing_amount < apex_facing:
				apex_facing = facing_amount
				apex_pitch_up = local_summon.global_basis.y.normalized().dot(entrance_camera.global_basis.y)
		if not captured_poses.is_empty():
			var capture := FileAccess.open("res://references/local_flight_poses.json", FileAccess.WRITE)
			capture.store_string(JSON.stringify(captured_poses))
		_expect(clears_existing_stack, "the entire arriving face clears the existing stack throughout its rotation")
		_expect(late_rotation < preceding_rotation * 0.35, "final rotation decays with the slow approach instead of making a late correction")
		_expect(late_distance < preceding_distance * 0.35, "final ten flight frames travel far less than the preceding ten")
		_expect(continuous, "local flight maintains movement and rotation through the peak without pausing")
		_expect(highest_y < destination_screen.y - entrance_size.y * 0.02 and has_descent,
			"local parabola rises visibly above its stack slot then descends into it")
		_expect(apex_facing < 0.2, "local Summon preserves its edge-on 90-degree Z waypoint")
		_expect(absf(apex_pitch_up) > 0.95, "combined Y/Z turn preserves the edge-on pose after lowering the path")
		_expect(stack._local_summon_presentation != null, "local flight is still active at frame 49 of the reference 50-frame duration")
		entrance.custom_step(1.0 / 60.0 + 0.01)
	_expect(local_summon.basis.orthonormalized().is_equal_approx(stack._stack_card_local_basis(local_summon)), "local Summon finishes its turn at the exact stack orientation")
	_expect(local_summon.effect_targets == picked and stack._local_summon_presentation == null,
		"local Summon entrance retains chosen targets and finishes presentation")
	_expect(local_summon.position.distance_to(stack.calculate_card_position(local_summon.index)) < 0.001,
		"local Summon entrance settles at its actual stack slot")
	var landing_pose := stack._stack_card_local_basis(local_summon).get_rotation_quaternion()
	if local_summon.stack_tween != null:
		local_summon.stack_tween.custom_step(0.15)
	var handoff_angle := local_summon.quaternion.angle_to(landing_pose)
	print("[FlowProbe] local landing handoff rotation error: %.3f degrees" % rad_to_deg(handoff_angle))
	_expect(handoff_angle < deg_to_rad(0.1), "landing handoff does not spin the card after it reaches its stack pose")
	demo._stage_local_summon()
	var demo_preview: Card = demo._local_preview
	_expect(demo_preview != null and stack.summon_casting_card == demo_preview,
		"demo stages a local Summon using the production cast preview")
	demo._toggle_pause()
	demo._confirm_local_summon()
	for _frame in range(85):
		demo._step_frame()
	_expect(not demo._casting and stack._local_summon_presentation == null and stack.cards.back() != demo_preview and stack.cards.back().current_zone == Card.Zone.STACK,
		"paused demo frame stepping completes the dissolve and local entrance")
	demo._toggle_pause()
	await _check_hover_shadow(demo.game.get_node("Player/Hand"))
	demo.queue_free()

func _shadow_slot_for(receiver: Card, caster_inverse: Transform3D) -> int:
	for slot in range(4):
		var prefix := "shadow_" if slot == 0 else "shadow%d_" % (slot + 1)
		if float(receiver.mat.get_shader_parameter(prefix + "strength")) > 0.0:
			var supplied: Transform3D = receiver.mat.get_shader_parameter(prefix + "inverse")
			if supplied.is_equal_approx(caster_inverse):
				return slot
	return -1

func _check_hover_shadow(hand: Hand) -> void:
	var cam := get_viewport().get_camera_3d()
	await get_tree().create_timer(0.4).timeout
	var fan := hand.cards.duplicate()
	fan.sort_custom(func(a, b): return cam.unproject_position(a.global_position).x < cam.unproject_position(b.global_position).x)
	var upper: Card = fan.back()
	var lower: Card = fan[-2]
	hand.set_hovered(upper, true)
	var hover_start := upper.global_position
	_expect(is_equal_approx(upper.scale.x, hand.HOVER_CARD_SCALE) and upper.rotation.is_zero_approx(),
		"hand hover enlarges and straightens immediately")
	await get_tree().create_timer(0.45).timeout
	_expect(upper.global_position.z > hover_start.z + 0.03 and is_equal_approx(upper.global_position.x, hover_start.x)
		and is_equal_approx(upper.global_position.y, hover_start.y), "enlarged hand card drifts slightly along world Z")
	# Reproduce a physics mouse-exit while the pointer is in the retained footprint.
	hand._pointer_hover_region = Rect2(hand.get_viewport().get_mouse_position() - Vector2.ONE * 5, Vector2.ONE * 10)
	hand._pointer_hover_active = true
	hand.pointer_hover(upper, false)
	_expect(hand.hovered_card == upper, "drift-induced mouse exit keeps the enlarged card open")
	var leave := InputEventMouseMotion.new()
	leave.position = Vector2(-100, -100)
	hand._input(leave)
	_expect(hand.hovered_card == null, "leaving the stable hover region dismisses the card")
	hand.set_hovered(upper, true)
	hand._pointer_hover_region = hand._card_screen_rect(upper).grow(3.0)
	hand._pointer_hover_active = true
	var move := InputEventMouseMotion.new()
	move.position = cam.unproject_position(hand.to_global(hand.calculate_card_position(fan[-3].index, false)))
	var underneath := hand._resting_card_at(move.position)
	hand._input(move)
	_expect(underneath != null and underneath != upper and hand.hovered_card == underneath,
		"mouse movement transfers hover to the frontmost resting card underneath")
	var transferred := hand.hovered_card
	hand.pointer_hover(upper, false)
	_expect(hand.hovered_card == transferred, "old card exit does not clear transferred hover")
	hand.set_hovered(transferred, false)
	hand.set_hovered(upper, true)
	await get_tree().create_timer(0.45).timeout
	var upper_inverse: Transform3D = upper.hand_mesh.global_transform.affine_inverse()
	var upper_slot := _shadow_slot_for(lower, upper_inverse)
	_expect(hand.hovered_card == upper and upper_slot >= 0, "hovered card supplies a full silhouette to its neighbour")
	if upper_slot >= 0:
		var prefix := "shadow_" if upper_slot == 0 else "shadow%d_" % (upper_slot + 1)
		var supplied: Transform3D = lower.mat.get_shader_parameter(prefix + "inverse")
		var shape: Vector3 = lower.mat.get_shader_parameter(prefix + "shape")
		var half := upper._card_face_size() * 0.5
		var source := upper.hand_mesh.to_global(Vector3(-half.x, 0, half.y))
		var pixel := cam.unproject_position(source)
		var plane := Plane(lower.hand_mesh.global_basis.y.normalized(), lower.hand_mesh.global_position)
		var hit: Vector3 = plane.intersects_ray(cam.project_ray_origin(pixel), cam.project_ray_normal(pixel))
		var ray := -cam.project_ray_normal(pixel)
		var origin_local: Vector3 = supplied * hit
		var ray_local: Vector3 = supplied.basis * ray
		var caster_hit := origin_local + ray_local * (-origin_local.y / ray_local.y)
		_expect(Vector2(caster_hit.x, caster_hit.z).distance_to(Vector2(-half.x, half.y)) < 0.001
			and is_equal_approx(shape.x, half.x) and is_equal_approx(shape.y, half.y),
			"silhouette projection follows the complete caster face including its far corner")
	var before_strength: float = lower.mat.get_shader_parameter("shadow_strength")
	var reversed := hand.cards.duplicate()
	reversed.reverse()
	preload("res://scripts/cards/card_overlap_shadow.gd").update(hand, reversed)
	_expect(is_equal_approx(before_strength, float(lower.mat.get_shader_parameter("shadow_strength"))),
		"actual depth determines shadow casting independently of list order")

	hand.set_hovered(upper, false)
	hand.set_hovered(fan[-3], true)
	await get_tree().create_timer(0.45).timeout
	_expect(_shadow_slot_for(lower, upper.hand_mesh.global_transform.affine_inverse()) >= 0
		and _shadow_slot_for(lower, fan[-3].hand_mesh.global_transform.affine_inverse()) >= 0,
		"hovering the left neighbour preserves silhouettes from both neighbours")
	hand.set_hovered(fan[-3], false)
	await get_tree().create_timer(0.45).timeout
	_expect(_shadow_slot_for(lower, fan[-3].hand_mesh.global_transform.affine_inverse()) < 0,
		"leaving hover removes the silhouette of the now-behind neighbour")


	var saved_upper := upper.global_transform
	upper.stop_hand_layout()
	upper.global_transform = lower.global_transform
	upper.global_position += cam.global_basis.x * 0.2 + cam.global_basis.z * 0.05
	var shadows := preload("res://scripts/cards/card_overlap_shadow.gd")
	shadows.update(hand, [lower, upper])
	var tight_width: float = lower.mat.get_shader_parameter("shadow_width")
	var tight_strength: float = lower.mat.get_shader_parameter("shadow_strength")
	upper.global_position += cam.global_basis.z * 0.5
	shadows.update(hand, [lower, upper])
	_expect(float(lower.mat.get_shader_parameter("shadow_width")) > tight_width
		and float(lower.mat.get_shader_parameter("shadow_strength")) < tight_strength,
		"larger card separation makes the shadow softer and lighter")
	upper.global_transform = lower.global_transform
	upper.global_position -= cam.global_basis.z * 0.3
	shadows.update(hand, [lower, upper])
	_expect(float(lower.mat.get_shader_parameter("shadow_strength")) == 0.0,
		"a card behind the receiver cannot cast onto it even when listed last")
	upper.global_transform = saved_upper
	hand._update_edge_shadows()

	# A preceding card can leave while the hovered card still has a drift callback.
	hand.set_hovered(upper, true)
	var removed: Card = hand.cards.front()
	if removed == upper:
		removed = hand.cards[1]
	hand.remove_card(removed)
	upper.index = hand.cards.size() # Reproduce the stale out-of-range index from the report.
	hand._apply_hover_drift(0.02)
	_expect(upper.index == hand.cards.find(upper) and upper.position.is_equal_approx(hand.calculate_card_position(upper.index)),
		"hover drift uses live hand membership after a preceding card leaves")
	hand.remove_card(upper)
	hand.set_hovered(upper, true)
	hand._apply_hover_drift(0.03)
	_expect(hand.hovered_card == null, "a cast preview still parented to Hand cannot restart hand hover")
	hand.add_card(removed)
	hand.add_card(upper)


func _check_opponent_translation(game) -> void:
	var stack: Stack = game.get_node("Stack")
	var hand: Hand = game.get_node("Opponent/Hand")
	var card: Card = game.create_card(62, "opponent")
	hand.add_card(card)
	var original = card.mat.get_shader_parameter("texture_albedo")
	# CHARGING IS PRIVATE: the Summon waits face down in the opponent's hand; a cancel leaves it there.
	if hand.charge(card):
		_expect(not card.revealed and card.get_parent() == hand and not card.has_node("StackAbilityFace"),
			"an opponent Summon being charged stays face down in their hand")
		game.get_node("Assistant").on_charge_cancelled()
		_expect(card.current_zone == Card.Zone.HAND and hand.cards.has(card) and not card.revealed
			and card.mat.get_shader_parameter("texture_albedo") == original, "a cancelled opponent Summon is back in their hand, unseen")
	var count_before := hand.cards.size()
	if not hand.charge(card):
		_expect(false, "opponent translation probe could start the cast")
		return
	var slot_in_hand: Vector3 = card.global_position
	_expect(hand.cards.size() == count_before - 1 and not hand.cards.has(card),
		"the opponent hand loses exactly the cast card")
	for i in range(hand.cards.size()):
		_expect(hand.cards[i].index == i, "remaining opponent card has its current fan index")
	# THE COMMIT MAKES IT PUBLIC: it flies from where it sat in their hand to the stack (queued presentation).
	stack._commit_summon_to_stack()
	var waited: int = 0
	while stack._opponent_summon_flight == null and waited < 60:
		await get_tree().process_frame
		waited += 1
	var flight := stack._opponent_summon_flight
	_expect(flight != null and stack._opponent_summon_flight_card == card and card.get_parent() == stack,
		"at commit the card leaves the hand and owns the flight to the stack")
	if flight == null:
		return
	flight.pause()
	var face = card.get_node_or_null("StackAbilityFace")
	_expect(face != null and card.revealed and card.hand_mesh.get_surface_override_material(0) == card.mat and face.get_node("Ability").text.contains("Forward"),
		"opponent Summon has its artwork material before its first flight frame")
	var launch := card.global_transform
	var path := stack.opponent_flight_path
	_expect(launch.origin.distance_to(slot_in_hand) < 0.05, "the flight launches from where the card sat in the opponent's hand")
	flight.custom_step(13.0 / 60.0)
	var launch_local := stack.global_basis.orthonormalized().inverse() * launch.basis.orthonormalized()
	var neutral := Basis(Vector3.RIGHT, PI + deg_to_rad(stack.stack_pitch_degrees))
	_expect(launch_local.is_equal_approx(neutral), "launch has zero stack yaw and roll")
	var partial_pose := stack._stack_card_local_basis(card, smoothstep(0.0, 1.0, 13.0 / 32.0))
	var flip_only := partial_pose.inverse() * card.basis.orthonormalized()
	var expected_flip := Basis(Vector3.RIGHT, PI - deg_to_rad(90.0 * 13.0 / 14.0))
	_expect(flip_only.is_equal_approx(expected_flip) and not partial_pose.is_equal_approx(stack._stack_card_local_basis(card)),
		"frame 131 combines partial stack tilt with the negative X pitch")
	flight.custom_step(1.0 / 60.0)
	var waypoint := path.to_global(path.curve.get_point_position(1))
	_expect(card.global_position.distance_to(waypoint) < 0.001 and waypoint.y < stack.global_position.y,
		"frame 132 reaches the authored waypoint below the stack")

	flight.custom_step(16.0 / 60.0)
	var before_settle := card.position
	flight.custom_step(1.0 / 60.0)
	var penultimate := card.position
	flight.custom_step(1.0 / 60.0)
	_expect(card.position.distance_to(penultimate) < penultimate.distance_to(before_settle) * 0.5,
		"the final frame travels less than half as far as the preceding frame")
	_expect(card.basis.orthonormalized().is_equal_approx(stack._stack_card_local_basis(card)),
		"frame 150 reaches the configured stack orientation")
	_expect(card.position.distance_to(stack.calculate_card_position(card.index)) < 0.001,
		"translation ends at the real stack slot")

	var spot: Vector3 = card.global_position
	stack.cancel_stack_card(card)
	_expect(card.current_zone == Card.Zone.GRAVEYARD and card.mat.get_shader_parameter("texture_albedo") == original,
		"leaving the stack restores the printed Break Zone face")
	# COUNTERED: the rules moved it at once; on screen a stand-in wearing its stack face stays on its spot, shorts
	# out, turns cyan and shatters (scripts/vfx/counter_cue.gd). The real card waits hidden in the Break Zone.
	var held: Array = game.find_children("HeldCard*", "Node3D", true, false)
	_expect(held.size() == 1 and not card.visible
		and (held[0] as Card).global_position.distance_to(spot) < 0.05
		and (held[0] as Card).current_zone == Card.Zone.STACK and (held[0] as Card).has_node("StackAbilityFace"),
		"a countered card is held on its stack spot by a stand-in with its stack face, the real card hidden")
	var countered := Vfx.get_events().filter(func(e) -> bool:
		return e.kind == VfxEvent.Kind.COUNTERED and e.targets.has(card))
	_expect(countered.size() == 1, "cancelling a stack object emits one COUNTERED event")
	# The cue plays in its turn in the presentation queue: time it from when it STARTS.
	var cue_wait := 0.0
	while cue_wait < 6.0 and game.find_children("CounterArcs", "MeshInstance3D", true, false).is_empty():
		await get_tree().process_frame
		cue_wait += get_process_delta_time()
	print("[FlowProbe] counter cue started %.2f s after the cancel" % cue_wait)
	await get_tree().create_timer(0.4).timeout
	_expect(game.find_children("CounterArcs", "MeshInstance3D", true, false).size() == 1 and not card.visible,
		"electric arcs crackle over the held card while the real card stays hidden")
	await get_tree().create_timer(1.2).timeout
	_expect(Vfx.find_children("CounterShard*", "MeshInstance3D", true, false).size() > 20
		and game.find_children("HeldCard*", "Node3D", true, false).is_empty() and card.visible,
		"it shatters into cyan pieces, the stand-in goes and the real card shows in the Break Zone")
	await Vfx.idle()
	await get_tree().process_frame
	_expect(Vfx.find_children("CounterShard*", "MeshInstance3D", true, false).is_empty(),
		"the pieces are gone when the cue finishes")

## GADOT 1-007: TWO enter-the-field auto-abilities are TWO stack objects, and their cards fly in STAGGERED, not together.
func _check_simultaneous_triggers() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.player_agent = MockAgent.new()      # MockAgent accepts a "may" and picks the first legal hand card
	game.player_agent.bind(game)
	game.opponent_agent = MockAgent.new()
	game.opponent_agent.bind(game)
	var field = game.field
	var stack: Stack = game.stack
	var gadot: Card = game.create_card(7, "player")
	game.add_child(gadot)
	field.play_card(gadot, false, false)       # setup placement: no ETB of its own
	var wol: Card = game.create_card(5, "player")   # Warrior of Light: Fire Forward, cost 2, no auto-ability
	game.add_child(wol)
	game.hand.add_card(wol)
	await get_tree().process_frame

	var started: Array = []    # [card, msec]
	var landed: Dictionary = {}  # card -> msec
	stack.trigger_flight_started.connect(func(c: Card) -> void: started.append([c, Time.get_ticks_msec()]))
	var queue_busy_at_landing: Array = []   # was the presentation queue still busy as each card landed?
	stack.trigger_entered.connect(func(c: Card) -> void:
		landed[c] = Time.get_ticks_msec()
		queue_busy_at_landing.append(not Vfx.is_idle()))

	field.execute_card_effect(gadot, EVENTS.Event.ENTER_FIELD)
	# RULES FIRST: both stack objects exist in the same frame the abilities trigger, before any animation.
	_expect(stack.cards.size() == 2, "Gadot entering puts TWO stack objects on the stack at once (%d)" % stack.cards.size())
	if stack.cards.size() != 2:
		return
	var top: Card = stack.cards[1]
	var bottom: Card = stack.cards[0]
	_expect(top.effect_ability_index == 0 and bottom.effect_ability_index == 1,
		"the FIRST printed ability is on top and resolves first (top %d, bottom %d)" % [top.effect_ability_index, bottom.effect_ability_index])
	_expect(not top.visible and not bottom.visible, "neither card is drawn before its flight starts")

	var waited := 0.0
	while landed.size() < 2 and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_expect(started.size() == 2 and landed.size() == 2, "both trigger cards flew in and landed (%d started, %d landed)" % [started.size(), landed.size()])
	if started.size() != 2 or landed.size() != 2:
		return
	var gap: float = (started[1][1] - started[0][1]) / 1000.0
	print("[FlowProbe] trigger launches %.3f s apart (stagger %.2f s)" % [gap, stack.trigger_stagger_seconds])
	_expect(gap > 0.1, "the two trigger cards do NOT spawn together (%.3f s apart)" % gap)
	_expect(absf(gap - stack.trigger_stagger_seconds) < 0.1,
		"the second launches one stagger after the first (%.3f s vs %.2f s)" % [gap, stack.trigger_stagger_seconds])
	_expect(started[1][1] < landed[started[0][0]],
		"the flights overlap: the second starts before the first has landed")
	_expect(started[0][0] == bottom and started[1][0] == top, "they launch in stack order, bottom first, top last")
	_expect(queue_busy_at_landing.size() == 2 and queue_busy_at_landing[0],
		"decisions still wait after the first landing: the group's presentation runs until the LAST card lands")
	await get_tree().create_timer(0.4).timeout
	for c in [bottom, top]:
		_expect(c.visible and not stack._incoming_triggers.has(c) and not stack._trigger_flights.has(c)
			and c.position.distance_to(stack.calculate_card_position(c.index)) < 0.01,
			"stack card %d settled visible in its own slot" % c.effect_ability_index)

	# THE FACE SAYS WHAT EACH ABILITY DOES, not "When Gadot enters the field". The face breaks short text into lines.
	var faces: Array[String] = []
	for c in [top, bottom]:
		var face = c.get_node_or_null("StackAbilityFace")
		faces.append(face.get_node("Ability").text.replace("
", " ") if face != null else "<no face>")
	print("[FlowProbe] Gadot stack faces: %s" % str(faces))
	_expect(faces[0] == "You may play 1 Fire Forward of cost 2 or less from your hand onto the field.",
		"the top stack card shows ONLY the play sentence")
	_expect(faces[1] == "All the Forwards you control gain +1000 power until the end of the turn.",
		"the bottom stack card shows ONLY the +1000 sentence")

	await stack.resolve_top_effect()
	await get_tree().process_frame
	_expect(wol.is_on_field(), "ability 0 resolves first: the Fire Forward is played from hand")
	await stack.resolve_top_effect()
	await get_tree().process_frame
	_expect(gadot.power == 5000 and wol.power == 6000,
		"ability 1 then gives +1000 to every Forward, including the one just played (Gadot %d, WoL %d)" % [gadot.power, wol.power])
	_expect(stack.cards.is_empty(), "both of Gadot's abilities have resolved")
	await Vfx.idle()
	game.queue_free()
	await get_tree().process_frame

## The REAL play: Gadot cast from hand, paid, teleported in, and his two abilities triggering while that presentation
## is still queued. Records each trigger card every frame so a missing flight shows up as "visible but never moved".
## TRIBUTE: an effect putting a field card into the Break Zone (not a break). The rules move is immediate; on screen a
## stand-in keeps the slot while a light orb bursts, RISES clear before it crosses (so it never slides through the
## card beside it or under the raised pile), and drops onto the pile, where the real card then shows.
func _check_tribute() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	var field = game.field
	var card: Card = game.create_card(5, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	var neighbour: Card = game.create_card(6, "player")
	game.add_child(neighbour)
	field.play_card(neighbour, false, false)
	await Vfx.idle()
	await get_tree().process_frame
	# DULL IT FIRST, as Black Mage's own cost does: put_card_into_graveyard() untaps it, and that untap tween once kept
	# turning the card after it reached the pile, so it lay there upside down.
	card.tap()
	await get_tree().create_timer(0.4).timeout
	var slot: Vector3 = card.global_position
	var pile: Node3D = game.player_graveyard
	Vfx.clear_events()
	game.put_card_into_graveyard(card)
	_expect(card.current_zone == Card.Zone.GRAVEYARD and pile.graveyard_cards.has(card),
		"RULES FIRST: the tributed card is in the Break Zone the moment the effect resolves")
	var held: Array = game.find_children("HeldCard*", "Node3D", true, false)
	_expect(held.size() == 1 and not card.visible and (held[0] as Card).global_position.distance_to(slot) < 0.01,
		"a stand-in keeps the field slot while the real card waits hidden in the pile")
	var events := Vfx.get_events().filter(func(e) -> bool: return e.kind == VfxEvent.Kind.TRIBUTE)
	_expect(events.size() == 1, "putting a card into the Break Zone emits one TRIBUTE event (%d)" % events.size())
	var stand_in: Card = held[0] if held.size() == 1 else null
	var peak := -INF
	var low_while_crossing := INF   # the lowest height while the card is away from BOTH the slot and the pile
	var saw_burst := false
	var waited := 0.0
	var card_w: float = card._card_face_size().x * card.global_basis.x.length()
	while is_instance_valid(stand_in) and waited < 5.0:
		saw_burst = saw_burst or not Vfx.find_children("TributeBurst", "MeshInstance3D", true, false).is_empty()
		var at: Vector3 = stand_in.global_position
		peak = maxf(peak, at.y)
		var flat_from_slot := Vector2(at.x - slot.x, at.z - slot.z).length()
		var flat_to_pile := Vector2(at.x - card.global_position.x, at.z - card.global_position.z).length()
		if flat_from_slot > card_w and flat_to_pile > card_w:
			low_while_crossing = minf(low_while_crossing, at.y)
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[FlowProbe] tribute flight: peak y %.2f, lowest while crossing %.2f, pile y %.2f, landed after %.2f s"
		% [peak, low_while_crossing, card.global_position.y, waited])
	_expect(saw_burst, "the light-orb burst quad plays on the slot")
	_expect(low_while_crossing > maxf(slot.y, card.global_position.y) + 0.3,
		"the card crosses ABOVE the board and the pile, never gliding through the cards beside it")
	_expect(not is_instance_valid(stand_in) and card.visible and waited > 0.4 and waited < 1.0,
		"after ~0.6 s the stand-in has landed and gone, and the real card shows in the pile")
	await Vfx.idle()
	await get_tree().process_frame
	_expect(Vfx.find_children("TributeBurst", "MeshInstance3D", true, false).is_empty(),
		"the burst quad is gone when the cue finishes")
	await get_tree().create_timer(0.5).timeout
	_expect(card.rotation.is_equal_approx(Card.ZONE_PRESENTATION[Card.Zone.GRAVEYARD]["rotation"]),
		"a card that was DULL lies straight in the pile, not upside down (rotation %s)" % str(card.rotation_degrees))
	# A BREAK is not a tribute: it keeps its own shatter.
	Vfx.clear_events()
	game.break_card(neighbour)
	_expect(Vfx.get_events().filter(func(e) -> bool: return e.kind == VfxEvent.Kind.TRIBUTE).is_empty(),
		"breaking a card does not play the tribute")
	await Vfx.idle()
	game.queue_free()
	await get_tree().process_frame

## THE MANA COST ROW sits at the SCREEN CENTRE (Assistant.cost_readout_screen_anchor: the river between the boards),
## not on the player's Backup row where card art swallowed it, inside a dark window that frames the whole row from
## BEHIND the crystals.
func _check_cost_row() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	var assistant = game.get_node("Assistant")
	assistant._on_field_card_activated_ability({"火": 1, "neutral": 2})
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Node3D = assistant.cost_readout
	var cam: Camera3D = get_viewport().get_camera_3d()
	var crystals: Array = row.crystals()
	_expect(row.visible and crystals.size() == 3, "a payment shows its cost row (%d crystals)" % crystals.size())
	if crystals.size() == 3 and cam != null:
		var screen: Vector2 = get_viewport().get_visible_rect().size
		var anchor: Vector2 = screen * assistant.cost_readout_screen_anchor
		# The middle crystal's MIDDLE (its origin is its base).
		var mid: Node3D = crystals[1]
		var middle: Vector2 = cam.unproject_position(mid.global_position + cam.global_basis.y * row.crystal_height_m * 0.5)
		print("[FlowProbe] cost row middle at %s, anchor %s (screen %s)" % [middle, anchor, screen])
		_expect(middle.distance_to(anchor) < 3.0, "the cost row's middle sits on the screen anchor (%.1f px off)" % middle.distance_to(anchor))
		var panel: MeshInstance3D = row.panel()
		_expect(panel != null and panel.visible, "the row has its backing panel")
		if panel != null:
			var half: Vector2 = (panel.mesh as QuadMesh).size * 0.5
			var left: float = cam.unproject_position(panel.global_transform * Vector3(-half.x, 0, 0)).x
			var right: float = cam.unproject_position(panel.global_transform * Vector3(half.x, 0, 0)).x
			var first_x: float = cam.unproject_position((crystals[0] as Node3D).global_position).x
			var last_x: float = cam.unproject_position((crystals[2] as Node3D).global_position).x
			_expect(left < first_x and right > last_x, "the panel frames every crystal (%.0f..%.0f around %.0f..%.0f)" % [left, right, first_x, last_x])
			var cam_to_panel: float = cam.global_position.distance_to(panel.global_position)
			var cam_to_crystal: float = cam.global_position.distance_to(mid.global_position)
			_expect(cam_to_panel > cam_to_crystal, "and sits BEHIND the crystals, so it never darkens them")
	game.queue_free()
	await get_tree().process_frame

func _check_gadot_played_from_hand() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.player_agent = AIAgent.new()        # pays the cost itself, like an opponent would
	game.player_agent.bind(game)
	game.opponent_agent = MockAgent.new()
	game.opponent_agent.bind(game)
	var field = game.field
	var stack: Stack = game.stack
	for id in [8, 10]:   # two Fire Backups to pay Gadot's 2
		var b: Card = game.create_card(id, "player")
		game.add_child(b)
		field.play_card(b, false, false)
	var gadot: Card = game.create_card(7, "player")
	game.add_child(gadot)
	game.hand.add_card(gadot)
	await get_tree().process_frame
	game.turn_owner = 1

	var started: Dictionary = {}
	stack.trigger_flight_started.connect(func(c: Card) -> void: started[c] = Time.get_ticks_msec())
	var played: bool = await game.play_card_for(1, gadot)
	_expect(played, "Gadot is cast from hand through the real payment path")
	# Watch the trigger cards until both landed (or give up).
	var seen: Dictionary = {}   # card -> {first_visible_ms, launched_ms, path_length, last_pos}
	var waited := 0.0
	while waited < 8.0:
		for c in stack.cards:
			if c.effect_source != gadot:
				continue
			var rec: Dictionary = seen.get(c, {"visible_at": -1, "path": 0.0, "last": c.global_position, "from": Vector3.ZERO})
			if c.visible and rec["visible_at"] < 0:
				rec["visible_at"] = Time.get_ticks_msec()
				rec["from"] = c.global_position
			if c.visible:
				rec["path"] += (c.global_position - rec["last"]).length()
			rec["last"] = c.global_position
			seen[c] = rec
		if seen.size() == 2 and started.size() == 2 and not stack._trigger_flights.has(seen.keys()[0]) 				and not stack._trigger_flights.has(seen.keys()[1]):
			break
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[FlowProbe] played Gadot: stack %d, flights started %d, records %s" % [stack.cards.size(), started.size(),
		str(seen.values().map(func(r): return "visible@%d path %.2f" % [r["visible_at"], r["path"]]))])
	_expect(seen.size() == 2, "playing Gadot puts his two abilities on the stack (%d)" % seen.size())
	for c in seen:
		_expect(started.has(c), "trigger card %d had a flight" % c.effect_ability_index)
		_expect(started.has(c) and seen[c]["visible_at"] >= started[c],
			"trigger card %d is not drawn before its flight starts" % c.effect_ability_index)
		var chord: float = (seen[c]["last"] - seen[c]["from"]).length()
		_expect(seen[c]["path"] > 1.0, "trigger card %d visibly travelled to the stack (%.2f m)" % [c.effect_ability_index, seen[c]["path"]])
		# Two flights in the air at once once leapfrogged each other toward the camera: a 168 m path for a 2.7 m trip.
		# The flight is an arc up the screen, so a normal one is about 2.4x its chord.
		_expect(seen[c]["path"] < chord * 4.0,
			"trigger card %d flew a sane path, not off toward the camera (%.2f m for a %.2f m trip)" % [c.effect_ability_index, seen[c]["path"], chord])
	if seen.size() == 2:
		var paths: Array = seen.values().map(func(r): return r["path"])
		_expect(absf(paths[0] - paths[1]) < 0.1 * maxf(paths[0], paths[1]),
			"both overlapping flights take the same path (%.2f m / %.2f m): neither disturbs the other" % [paths[0], paths[1]])
	await Vfx.idle()
	game.queue_free()
	await get_tree().process_frame

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
