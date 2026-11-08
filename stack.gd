extends Node3D
class_name Stack
const PRESENTATION := preload("res://scripts/presentation.gd")
const LOG := preload("res://scripts/log.gd")
## The Game this zone belongs to. Every call into the game goes through this one declared dependency rather
## than through get_parent() calls scattered around. A getter, not @onready, so it also works during _ready().
var game: Game:
	get:
		return get_parent()

const EVENTS := preload("res://scripts/effects/events.gd")

var cards = []
## Layout pitch in STACK-LOCAL units. It has to follow the card's VISUAL width, not a separate
## hand-picked number: the container is scaled 2.305, so the local face width is
## 0.429 * (STACK_CARD_SCALE / STACK_CONTAINER_SCALE). A fixed pitch would spread the fan into
## separate cards whenever the stack is resized.
var card_width = 0.429 * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE)
var player_mode = GlobalVariables.get_player_mode();
var start_x: float = 0.0
var _local_summon_presentation: Card
## The printed local Summon while it fades out in the hand (presentation only; already off the stack list).
var _local_summon_fading: Card
signal local_summon_landed
var casting_card: Card
## Stack copy for skill activation. The node exists early for UI; the activation is not
## de facto committed until commit_skill_activation_costs_if_pending runs (after final Confirm).
var skill_activation_proxy: Card = null
## While true, mana/hand discard and JSON tap on source are deferred until stack commit (final Confirm).
var skill_mana_deferred_until_target_confirm: bool = false
## Summon being cast from hand. It is parked on the Stack while its cost is paid
## and targets are chosen; only then does it legally enter the stack.
var summon_casting_card: Card = null
## While true, summon mana payment is deferred until the target is confirmed.
var summon_mana_deferred_until_target_confirm: bool = false
## OPPONENT SUMMON FLIGHT. The one-shot tween that carries the card from the middle of the
## opponent's hand to the centre of the screen and then into the stack. Held so a cancel or a
## commit can kill it instead of letting it keep writing transforms.
var _opponent_summon_flight: Tween = null
var _opponent_summon_flight_card: Card = null
## True while an effect resolution is still running (it may await a modal).
var resolution_pending: bool = false
## Special ability (S) cost state: a card sharing a name with the source,
## selected from hand and discarded at the final skill commit.
var s_cost_active: bool = false
var s_cost_source: Card = null
var s_cost_skill_index: int = -1
var s_cost_selected_card: Card = null
## SACRIFICE / DISCARD COSTS chosen for the pending activation. FFTCG pays every cost together: these are only PICKED
## during activation and leave at commit_skill_activation_costs_if_pending(); backing out (_clear_skill_proxy) costs
## nothing. While pending they are spoken for and cannot also pay the mana.
var pending_cost_sacrifices: Array[Card] = []
var pending_cost_discards: Array[Card] = []

## True while `card` is already committed to pay another cost of the activation in progress.
func is_reserved_for_cost(card: Card) -> bool:
	return card == s_cost_selected_card or pending_cost_sacrifices.has(card) or pending_cost_discards.has(card)
@onready var field: Field = game.get_node("Field") as Field
@onready var hand: Hand = game.get_node("Player/Hand") as Hand
@onready var assistant: Assistant = game.get_node("Assistant") as Assistant
@onready var card_scene = preload("res://card.tscn")

signal execute_card_effect(card:Card)
signal request_priority()
## Emitted by the game when a stack effect has fully finished resolving.
signal resolution_complete

func _ready() -> void:
	assistant.choose_card_finished.connect(_on_choose_card_finished)

## Cards to lay out: the legal stack objects plus the parked card (Summon or
## Character). Positioning MUST go through this — using `cards` alone leaves the
## parked card out of the row width, which offsets every card.
func layout_cards() -> Array:
	var list: Array = cards.duplicate()
	var parked = summon_casting_card if summon_casting_card != null else casting_card
	if parked != null and parked.current_zone == Card.Zone.STACK:
		list.append(parked)
	return list

func calculate_total_width():
	var n: int = layout_cards().size()
	return card_width + (n - 1) * _stack_spacing(n) if n > 0 else 0.0
	
func stack_length() -> int:
	return len(cards)

## The stack's 3D pose is EXPORTED so it can be dialled in by eye instead of edited in code.
## Select the Stack node in game.tscn (or open the Remote tab while the game is running) and use
## the "Stack Rotation" sliders; every change re-lays the fan immediately.
@export_group("Stack Rotation")
## +X pitch tips the card's face normal toward local +Z; the Stack node is yawed 180 degrees, so
## that is world -Z — the camera side. 19 deg leaves the card a little short of square-on, so the
## top/bottom edges still show perspective instead of reading as a flat UI card.
@export_range(-60.0, 90.0, 0.5) var stack_pitch_degrees: float = 19.0:
	set(value):
		stack_pitch_degrees = value
		_refresh_stack_pose()
## A rotation around the card's own vertical axis, in the card's local frame. This is the
## art-plane turn; -27.5 is the value dialled in against the reference.
@export_range(-45.0, 45.0, 0.5) var stack_local_yaw_degrees: float = -27.5:
	set(value):
		stack_local_yaw_degrees = value
		_refresh_stack_pose()
## The in-plane (screen-plane) roll.
@export_range(-45.0, 45.0, 0.5) var stack_roll_degrees: float = 6.0:
	set(value):
		stack_roll_degrees = value
		_refresh_stack_pose()
## THE ONE THAT MOVES THE SIDES IN DEPTH: a rotation around the CAMERA'S UP AXIS. Negative makes
## the LEFT edge go into the screen and the RIGHT edge come toward the viewer, as in the reference.
@export_range(-60.0, 60.0, 0.5) var stack_screen_yaw_degrees: float = -3.5:
	set(value):
		stack_screen_yaw_degrees = value
		_refresh_stack_pose()

## Translation timeline: launch at reference frame 118, land at 150 (60 fps).
@export_group("Opponent Summon Flight")
@export_range(0.30, 2.0, 0.01) var opponent_flight_seconds: float = 32.0 / 60.0
@export var opponent_flight_path: Path3D
const OPPONENT_CENTER_TIME := 14.0 / 32.0

func _refresh_stack_pose() -> void:
	if is_inside_tree() and is_node_ready():
		update_card_positions()

## Shallow arc and per-card tilt, mirroring the hand: a plain row collapsed into one unreadable
## overlap as soon as a third card arrived.
const STACK_HOVER_SCALE := 1.4
## Height between neighbours, so the card in front is visibly in front.
const FAN_HEIGHT_STEP := 0.016
## A selected card lifts within its slot so every newer card remains higher.
const FAN_RAISE := FAN_HEIGHT_STEP * 0.35
var _shadow_track_seconds := 0.0
## The review link's arrow, kept separate from the live targeting arrow and the block arc so the
## three can never re-aim or hide each other.
const LINK_ARROW_SCENE := preload("res://ballistic_arrow.tscn")

## Tilt/arc angle for a SLOT (0 = leftmost). Same shape as the hand's fan.
func _stack_spacing(count: int) -> float:
	return card_width * minf(0.38, 1.15 / maxi(1, count - 1))

## ----- reviewing the stack's targets ---------------------------------------------------------
## Every card in the stack keeps the target it was given (`Card.effect_target`), so the stack can
## re-draw any of those links on demand. That is the only way to see what an older ability was
## pointed at once a newer one has been put on top.
##
## The card on display is the one the mouse is OVER, and otherwise the TOP of the stack. Hovering
## is transient, so leaving a card restores the top with no "clicked elsewhere?" rule to remember.
var hovered_card: Card = null

func displayed_card() -> Card:
	if hovered_card != null and is_instance_valid(hovered_card) and cards.has(hovered_card):
		return hovered_card
	return cards.back() if not cards.is_empty() else null

func set_hovered(card: Card, entered: bool) -> void:
	var previous := hovered_card
	if entered:
		if hovered_card == card or not cards.has(card) or card == _opponent_summon_flight_card:
			return
		hovered_card = card
	elif hovered_card == card:
		hovered_card = null
	else:
		return
	update_card_positions(previous, true)

## Draw — or clear — the link for `displayed_card()`. DISPLAY ONLY: it opens no session and
## changes no game state; it exists so the player can look at what is already on the stack.
func refresh_target_display() -> void:
	# Never draw over a live targeting session. While one is open the arrow and the rings belong
	# to the choice being made, and a review link would fight them.
	var mode = GlobalVariables.get_player_mode()
	if mode == GlobalVariables.Player_Mode.TARGET \
			or mode == GlobalVariables.Player_Mode.PAYING_COST \
			or mode == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		return
	var card: Card = displayed_card()
	var target: Card = card.effect_target if card != null else null
	if field == null:
		return
	if target == null or not is_instance_valid(target):
		_clear_target_display()
		return
	# The FIELD draws it, not the stack: BallisticArrow's points are LOCAL, and the stack node is
	# flipped and lifted, so an arrow parented here and given global points lands wherever that
	# transform carries it ("arrows in random places").
	field.show_review_link(card, target)
	# NOTE: the link draws the ARROW ONLY — it deliberately does NOT paint the target's aura.
	# The aura already has an owner (the live pick, and the reveal that holds until the stack
	# resolves). An earlier version painted it here too, and because "clear only what I lit" is
	# indistinguishable when both writers light the SAME card, the review link stole the reveal's
	# ring and then cleared it. The arrowhead lands exactly on the target, so the link needs no
	# second signal to be readable.
	# If a hover aura is wanted later, the right change is to make the aura DERIVED in one place
	# that decides which card is marked and why — not to add a third writer of the same flags.

func _clear_target_display() -> void:
	if field != null:
		field.hide_review_link()

## Hide the review arrow before a live session opens: it draws the same arrow shape, and the
## session is about to draw its own from the same card. Done deterministically at the START of the
## session so "there is only ever one arrow on screen" does not depend on who refreshes first.
func release_target_display() -> void:
	if hovered_card != null:
		set_hovered(hovered_card, false)
	_clear_target_display()

## Which card the player is looking at. null means "the top of the stack"; see select_card().
var selected_card: Card = null

func selected_or_top() -> Card:
	if selected_card != null and is_instance_valid(selected_card) and cards.has(selected_card):
		return selected_card
	return cards.back() if not cards.is_empty() else null

## Clicking a card in the fan raises it, and makes it the card whose targeting is displayed.
func select_card(card: Card) -> void:
	if card == null or not cards.has(card):
		return
	selected_card = card
	update_card_positions()

## Back to the top of the stack — what any click outside the stack does.
func select_top() -> void:
	selected_card = null
	update_card_positions()

func update_card_positions(previous_hover: Card = null, hover_changed := false):
	var list: Array = layout_cards()
	for i in range(list.size()):
		var card = list[i]
		card.index = i
		if card == _opponent_summon_flight_card or card == _local_summon_presentation:
			continue
		var slot := calculate_card_position(i)
		if card == hovered_card:
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				# Follow the viewing ray so lifting the card keeps its centre under the cursor.
				var world_slot := to_global(slot)
				var toward_camera := -camera.project_ray_normal(camera.unproject_position(world_slot))
				var top_offset := to_global(calculate_card_position(list.size() - 1)) - world_slot
				var lift := 0.55 + maxf(0.0, top_offset.dot(toward_camera))
				slot = to_local(world_slot + toward_camera * lift)
		var hover_transition: bool = hover_changed and (card == previous_hover or card == hovered_card)
		animate_card(card, slot, hover_transition)

	# The stack just changed, so what is on display may have too: the default display is the TOP
	# of the stack, and after an add or a resolve that is a different card.
	refresh_target_display()
	_shadow_track_seconds = 0.35
	_update_stack_shadows()

func _process(delta: float) -> void:
	if _shadow_track_seconds > 0.0:
		_shadow_track_seconds -= delta
		_update_stack_shadows()

func _update_stack_shadows() -> void:
	var settled := layout_cards()
	settled.erase(_opponent_summon_flight_card)
	settled.erase(_local_summon_presentation)
	if is_instance_valid(hovered_card) and settled.has(hovered_card):
		settled.erase(hovered_card)
		settled.append(hovered_card)
	preload("res://scripts/card_overlap_shadow.gd").update(self, settled)

func calculate_card_position(i: int) -> Vector3:
	var list := layout_cards()
	if list.is_empty():
		return Vector3.ZERO
	var top := list.size() - 1
	var pose := _stack_card_local_basis(list[top])
	var spacing := _stack_spacing(list.size())
	var fraction: float = spacing / card_width
	var half_width: Vector3 = pose.x * card_width * 0.5
	var camera := get_viewport().get_camera_3d()
	var center := Vector3.ZERO
	for index in range(top - 1, i - 1, -1):
		var layer := -pose.y * ((top - index) * FAN_HEIGHT_STEP) + pose.z * ((top - index) * spacing * 0.85)
		var sideways := center.dot(pose.x) + spacing
		if camera != null:
			var covering_edge := camera.unproject_position(to_global(center + half_width)).x
			var low: float = center.dot(pose.x) - card_width * 2.0
			var high: float = center.dot(pose.x) + card_width * 3.0
			# Solve the exposed fraction in camera space with the newest card fixed.
			for iteration in range(24):
				sideways = (low + high) * 0.5
				var candidate := layer + pose.x * sideways
				var left := camera.unproject_position(to_global(candidate - half_width)).x
				var right := camera.unproject_position(to_global(candidate + half_width)).x
				var exposed := (right - covering_edge) / (right - left)
				if exposed < fraction:
					low = sideways
				else:
					high = sideways
		center = layer + pose.x * sideways
	return center

func animate_card(card, target_position, hover_transition := false):
	# ONE LAYOUT TWEEN PER CARD. The old one has to die before a new target is
	# written, and the card has to own the reference so enter_zone() can stop it
	# when the card leaves the stack.
	if card.has_method("stop_stack_layout"):
		card.stop_stack_layout()
	var pose := _stack_card_local_basis(card)
	var size := Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE
	var camera := get_viewport().get_camera_3d()
	if card == hovered_card and camera != null:
		var screen := camera.global_basis.orthonormalized()
		pose = global_basis.orthonormalized().inverse() * Basis(screen.x, screen.z, -screen.y)
		size *= STACK_HOVER_SCALE
	if hover_transition and card != hovered_card:
		card.transform = Transform3D(pose.scaled(Vector3.ONE * size), target_position)
		return
	var duration := 0.1 if hover_transition else 0.3
	var tween = create_tween()
	card.set("stack_tween", tween)
	tween.set_parallel(true)
	if hover_transition:
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", target_position, duration)
	tween.tween_property(card, "scale", Vector3.ONE * size, duration)
	tween.tween_property(card, "rotation", pose.get_euler(), duration)


## The local orientation of a stack card, from the tuned Stack Rotation exports. One owner, so
## the opponent flight can land on EXACTLY the pose the layout uses instead of a lookalike.
func _stack_card_local_basis(_card, yaw_roll_weight: float = 1.0) -> Basis:
	# THE CARD IS HELD UP AND ANGLED, NOT SQUARE TO THE CAMERA. Start from the local pitch/roll,
	# then rotate the whole thing around the CAMERA'S UP AXIS. That last rotation is the one that
	# moves the card's left edge into the screen and its right edge out (or the reverse); the local
	# Euler angles alone only spin it inside its own plane, which is why it read as flat.
	var target_basis := Basis.from_euler(Vector3(
		deg_to_rad(stack_pitch_degrees),
		deg_to_rad(stack_local_yaw_degrees) * yaw_roll_weight,
		deg_to_rad(stack_roll_degrees) * yaw_roll_weight))
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var parent_basis: Basis = global_transform.basis.orthonormalized()
		var cam_up_local: Vector3 = (parent_basis.inverse() * cam.global_transform.basis.y).normalized()
		target_basis = Basis(cam_up_local, deg_to_rad(stack_screen_yaw_degrees) * yaw_roll_weight) * target_basis
	return target_basis
	

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	card.reparent(self,false)
	card.global_transform = trans
	card.enter_zone(Card.Zone.STACK)
	_clear_top_energized()

## THE ENERGIZED GLOW ENDS WHEN THE CARD IS PLAYED.
##
## A glowing card is one the mana was spent on. The moment it sits on top of the stack it IS the signal — it needs no
## badge saying it was paid for — so the glow has done its job and stops there. On a Character, which never enters the
## stack at all, the zone change clears it instead (Card.enter_zone).
##
## Safe to call anywhere: it only clears a flag that is already set.
func _clear_top_energized() -> void:
	if cards.is_empty():
		return
	var top: Card = cards.back()
	if top != null:
		top.set_energized_highlight(false)
	
func add_created_card_to_tree(card: Card, wording: String):
	cards.append(card)
	card.index = cards.size()-1
	var trans := card.transform
	add_child(card)
	if(card.key_word_effect):
		LOG.info("Stack", "adding effect to the stack")
	card.global_transform = trans
	card.enter_zone(Card.Zone.STACK, wording)
	
func cast_card():
	# It is being played, so it is public now, whichever branch runs.
	reveal_parked(casting_card)
	if casting_card.type == Card.SUMMON:
		# Summons stay on the stack and resolve as effects. Resolution
		# (game._on_stack_execute_card_effect) sends them to the graveyard.
		casting_card.key_word_effect = "when_cast"
		# HISTORY AT THE CAST, not at resolution: "if you have cast X this turn" becomes true the moment the card is
		# played, and a Summon that is invalidated before it resolves was still cast.
		game.record_action("Casted %s" % casting_card.card_name, [],
			1 if casting_card.controller == Card.PLAYER else 2)
		# Board-wide "when a Summon is cast" triggers (Yuna 214, Lenne 215) fire at the cast, not at resolution.
		field.trigger_event(EVENTS.Event.SUMMON_CAST, {"card": casting_card})
	else:
		# Character cards go straight to the field: they are never stack objects,
		# so nothing is popped and no stack slot is consumed. play_card() needs
		# the side explicitly — it cannot infer it from card.controller.
		#
		# THE CARD IS PARKED IN THE FAKE STACK. It stayed there through the
		# payment with the thin gold aura, so this is the "marked" card the player
		# can see. Break the crystals concurrently, then fade the card out where
		# it sits and rebuild it on the field.
		var landing: Card = casting_card
		if landing == null or not is_instance_valid(landing):
			return
		_shatter_paid_cost()
		# The CAST is the action, not the end of its presentation. Record it
		# before the ~1.3 s teleport so priority sees the action immediately.
		game.note_action_taken()
		var owner_hand: Hand = _owner_hand(landing)
		# DISCARD FIRST: the payment cards' flights must be QUEUED before the dissolve, so they play first. Flushing
		# here makes that order explicit instead of depending on which charge_complete handler runs first.
		if owner_hand != null:
			owner_hand.flush_mana_discard()
		# The gold aura has done its job; let it fade with the card.
		landing.set_cast_pending_highlight(false)
		# PRESENTATION, queued: shine and dissolve IN PLACE, where the player sees the card. Nothing travels across the
		# board; Field then materialises it at its slot (also queued, behind this).
		var shine: float = field.teleport_shine_seconds
		var fade: float = field.teleport_fade_seconds
		Vfx.present(func() -> void:
			if is_instance_valid(landing):
				await landing.teleport.play_out(shine, fade).finished)
		# RULES, at once: the Character is on the field.
		field.play_card(landing, landing.controller != Card.PLAYER, true, true, false, true)
	
	
func _on_assistant_charge_complete() -> void:
	if summon_casting_card != null:
		_continue_summon_after_mana(summon_casting_card)
		return
	if casting_card:
		# cast_card() reads `casting_card` synchronously before its first await,
		# then owns the local `landing` reference for the rest of the teleport.
		cast_card()
		casting_card = null
		# The Character is still in hand, not in this row; the hand re-lays out
		# itself when it is removed after the fade.
		update_card_positions()
	elif skill_activation_proxy != null:
		field.continue_skill_activation_after_mana(skill_activation_proxy)

func _continue_summon_after_mana(card: Card) -> void:
	# Payment is only committed when the summon actually enters the stack
	# (after target confirmation). If the summon needs a target, target
	# selection happens now and may still be cancelled.
	var criteria = card.get_cast_target_criteria()
	if criteria.is_empty():
		_commit_summon_to_stack()
		request_priority.emit()
		return
	field.request_target(criteria, card, true, "Summon")

## The Hand that owns `card`. The `hand` member above is the LOCAL player's
## hand, which is the wrong one for an opponent's card now that agents can cast
## Summons too: committing through the wrong hand would leave a stale
## `charging_card` there, which can later pull the card back off the stack.
func _owner_hand(card: Card) -> Hand:
	return game.hand_for(1 if card.controller == Card.PLAYER else 2)

func _commit_summon_to_stack() -> void:
	if summon_casting_card == null:
		return
	# If an opponent flight is still in the air, do NOT snap it now: the rules commit at once,
	# but the visual is allowed to finish and settle into the stack when the tween completes.
	var flighting: bool = _opponent_summon_flight != null and _opponent_summon_flight_card == summon_casting_card
	var card: Card = summon_casting_card
	var owner_hand: Hand = _owner_hand(card)
	var local_preview := card.controller == Card.PLAYER and card.get_parent() == owner_hand
	if local_preview:
		_local_summon_presentation = card
	# Target is confirmed: finalize mana payment now (discard hand mana,
	# tap backup mana), then put the summon on the stack.
	field.apply_deferred_skill_mana_payment()
	owner_hand.apply_deferred_skill_mana_payment()
	# Opponent flights install the face at launch. A stationary parked card is
	# revealed when its cast commits.
	if not flighting:
		reveal_parked(card)
	summon_mana_deferred_until_target_confirm = false
	summon_casting_card = null
	card.key_word_effect = "when_cast"
	card.effect_kind = "Summon"
	owner_hand.finish_summon_cast(card)
	# The card is already parked on the stack node; now it legally enters
	# the stack list and resolves as a normal stack object.
	cards.append(card)
	card.index = cards.size() - 1
	if local_preview:
		_queue_local_summon(card)
	elif not flighting:
		update_card_positions()
	# Casting a Summon is a priority action: it is on the stack now, so priority
	# moves to the opponent. (Emitting in the Agent's case is harmless — no one
	# is awaiting the signal; the agent reports through take_priority().)
	game.note_action_taken()


func begin_triggered_ability(source: Card, keyword: String) -> void:
	## Triggered auto-abilities go on the stack during rules processing,
	## before a player receives priority. Any "may" choice (e.g. Auron's
	## "play a Fire Backup") is made when the ability RESOLVES.
	if source == null or not source.card_effects.has(keyword):
		return
	_add_triggered_effect_to_stack(source, keyword)
	request_priority.emit()

func _add_triggered_effect_to_stack(source: Card, keyword: String) -> void:
	create_card(source.id, source.controller, keyword, source)
	update_card_positions()

func _mark_resolution_complete() -> void:
	resolution_pending = false
	resolution_complete.emit()

## Special ability (S) cost step 1: choose a card in hand that shares a name
## with the source. The actual discard is deferred until the skill commits.
func begin_s_cost_selection(source: Card, skill_index: int) -> void:
	var criteria: Dictionary = {"is_named": source.card_name}
	if not hand.has_card_matching_criteria(criteria):
		# Cannot pay the S cost: abort the whole activation.
		_clear_skill_proxy()
		GlobalVariables.refresh_mode()
		assistant.show_pass_priority_button()
		return
	s_cost_active = true
	s_cost_source = source
	s_cost_skill_index = skill_index
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card(criteria)
	assistant.show_choose_card_buttons("Discard", "Cancel")

func _on_choose_card_finished(play: bool) -> void:
	if not s_cost_active:
		return
	s_cost_active = false
	var chosen: Card = hand.selected_card_for_effect
	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	assistant.show_pass_priority_button()

	if not play or chosen == null:
		_clear_skill_proxy()
		return

	s_cost_selected_card = chosen
	# S cost chosen. The mana stage follows ONLY if there is mana to pay: when the cost is empty the discarded card WAS the
	# whole payment, so asking for a Confirm on an empty screen is a button that exists only to be pressed.
	var def: Dictionary = s_cost_source.activation_skill(s_cost_skill_index)
	var cost: Dictionary = def.get("cost", {})
	if field.cost_is_free(cost):
		field.continue_skill_activation_after_mana(skill_activation_proxy)
		return
	field.card_activated_ability.emit(cost)

func add_skill_activation_proxy(source: Card, skill_index: int, x_value: int = -1) -> bool:
	## Physical stack object for UI (pay + target). Costs apply later at de facto stack commit.
	if skill_activation_proxy != null:
		return false
	var definition: Dictionary = source.activation_skill(skill_index)
	if definition.is_empty():
		return false
	var proxy := create_skill_proxy(source, skill_index, definition, x_value)
	skill_activation_proxy = proxy
	skill_mana_deferred_until_target_confirm = true
	game.note_action_taken()
	return true

func create_skill_proxy(source: Card, skill_index: int, definition: Dictionary, x_value: int = -1) -> Card:
	var proxy: Card = card_scene.instantiate()
	proxy.initialize(source.id, source.controller)
	proxy.skill_activation_index = skill_index
	# Snapshot the definition. The source's copied-skill slot may be overwritten or cleared while this object is
	# still on the stack, and an ability already on the stack must resolve independently of its source.
	proxy.skill_def_override = definition.duplicate(true)
	if x_value >= 0:
		# The declared X belongs to THIS activation, not to the card's reusable ability definition.
		proxy.ability_x_value = x_value
		proxy.skill_def_override["x_value"] = x_value
		proxy.skill_def_override["cost"] = {"neutral": x_value}
	proxy.ability_spec = source.activation_ability_spec(skill_index)
	proxy.copied_skill_activation = bool(definition.get("copied", false))
	proxy.copied_skill_token = source.copied_skill_token if proxy.copied_skill_activation else 0
	proxy.key_word_effect = "skill"
	proxy.effect_source = source
	proxy.effect_kind = "Ability"
	add_created_card_to_tree(proxy, preload("res://scripts/effects/ability_spec.gd").stack_wording(proxy.skill_def_override))
	update_card_positions()
	return proxy

func _apply_skill_source_tap_from_proxy() -> void:
	## Part of stack commit: JSON "tap" is a cost, not tied to resolution (instructions run in game._on_stack_execute_card_effect).
	if skill_activation_proxy == null:
		return
	var src: Card = skill_activation_proxy.effect_source
	if src == null or not src.is_inside_tree():
		return
	var def: Dictionary = skill_activation_proxy.skill_def_override
	if def.is_empty():
		def = src.activation_skill(skill_activation_proxy.skill_activation_index)
	if def.is_empty():
		return
	if def.get("tap", false):
		src.tap()

## Skill stack commit: activation is legally complete (costs paid, target on proxy if required).
## Resolution (execute instructions) happens later in resolve_top_effect -> game._on_stack_execute_card_effect.
func commit_skill_activation_costs_if_pending() -> void:
	if not skill_mana_deferred_until_target_confirm:
		return
	field.apply_deferred_skill_mana_payment()
	hand.apply_deferred_skill_mana_payment()
	_apply_skill_source_tap_from_proxy()
	# RETURN-THIS-CARD-TO-HAND COST (Onion Knight 181). Done at commit, not activation, so backing out of payment
	# leaves the source on the field. The ability proxy already owns the spec, so the source may leave safely.
	if skill_activation_proxy != null:
		var return_def: Dictionary = skill_activation_proxy.skill_def_override
		if bool(return_def.get("return_self", false)):
			var return_src: Card = skill_activation_proxy.effect_source
			if return_src != null and is_instance_valid(return_src):
				var owner_hand: Hand = game.hand_for(1 if return_src.controller == Card.PLAYER else 2)
				if owner_hand != null:
					field.remove_card(return_src)
					owner_hand.add_card(return_src)
		# DEFERRED SELF-SACRIFICE (Tama 111). Paying it at commit means backing out of the mana modal leaves Tama on
		# the field instead of losing it before the payment is confirmed.
		if bool(return_def.get("defer_sacrifice", false)):
			var sacrifice: Dictionary = return_def.get("sacrifice", {})
			if bool(sacrifice.get("is_source", false)):
				var sac_src: Card = skill_activation_proxy.effect_source
				if sac_src != null and is_instance_valid(sac_src) and sac_src.is_on_field():
					LOG.info("Sacrifice", "%s -> Break Zone (deferred)" % sac_src.card_name)
					game.put_card_into_graveyard(sac_src)
	# SACRIFICE AND DISCARD COSTS, paid now with everything else (they were only picked during activation).
	for sacrificed in pending_cost_sacrifices:
		if sacrificed != null and is_instance_valid(sacrificed) and sacrificed.is_on_field():
			LOG.info("Sacrifice", "%s -> Break Zone" % sacrificed.card_name)
			game.put_card_into_graveyard(sacrificed)
	pending_cost_sacrifices.clear()
	for discarded in pending_cost_discards:
		if discarded != null and is_instance_valid(discarded):
			var discard_hand: Hand = game.hand_for(1 if discarded.controller == Card.PLAYER else 2)
			if discard_hand != null and discard_hand.cards.has(discarded):
				LOG.info("Discard", "%s (cost)" % discarded.card_name)
				discard_hand.discard_card(discarded)
	pending_cost_discards.clear()
	# Special ability (S) cost: discard the card chosen from hand.
	if s_cost_selected_card != null:
		hand.discard_card(s_cost_selected_card)
		s_cost_selected_card = null
	# The copied-skill permission is one use. Consume only the exact permission this proxy was created from; a newer
	# Ronso Rage may have replaced the slot while this activation was waiting.
	if skill_activation_proxy != null and skill_activation_proxy.copied_skill_activation:
		var copied_source: Card = skill_activation_proxy.effect_source
		if copied_source != null:
			copied_source.consume_copied_skill(skill_activation_proxy.copied_skill_token)
	skill_mana_deferred_until_target_confirm = false

func _clear_skill_proxy() -> void:
	# WAS THIS ACTIVATION STILL PENDING? If so its cost never committed, and the tap that
	# begin_skill_activation() applied has to be refunded — otherwise a cancelled ability leaves the card tapped and
	# silently spent for the rest of the turn.
	#
	# `skill_mana_deferred_until_target_confirm` is exactly that flag: set when the proxy is created, cleared by
	# commit_skill_activation_costs_if_pending(). So it is still true here only when the player backed out.
	var was_pending: bool = skill_mana_deferred_until_target_confirm
	s_cost_active = false
	s_cost_source = null
	s_cost_skill_index = -1
	s_cost_selected_card = null
	# Backing out costs nothing: the picked sacrifice / discard cards simply stay where they are.
	pending_cost_sacrifices.clear()
	pending_cost_discards.clear()
	if skill_activation_proxy == null:
		return
	var p = skill_activation_proxy
	skill_activation_proxy = null
	skill_mana_deferred_until_target_confirm = false
	# A damage split chosen for THIS ability must not outlive it: the next divide-damage ability would inherit it.
	game.clear_damage_division()
	if was_pending:
		var src: Card = p.effect_source
		if src != null and is_instance_valid(src) and src.tapped:
			src.untap()
	cards.erase(p)
	if is_instance_valid(p):
		p.queue_free()
	update_card_positions()


## A SUMMON awaiting its cost is only PARKED on this node — a visual placeholder.
## It is not in `cards`, so it is not legally on the stack, and it is not public
## knowledge yet: only its owner sees which card it is. A Character never comes
## here at all: it is paid for in hand, then fades from the hand straight to the
## field. Only a Summon becomes a stack card, and only at
## _commit_summon_to_stack().
func park_card(card: Card) -> void:
	var trans = card.global_transform
	card.stop_hand_layout()
	card.reparent(self, false)
	card.global_transform = trans
	# Parked cards are flat and plain: no hand tilt and no field readout.
	card.enter_zone(Card.Zone.STACK)
	# Face-down for anyone but the owning player. Every exit from this node must
	# call reveal_parked().
	card.set_revealed(card.controller == Card.PLAYER)
	update_card_positions()

## A parked card is leaving this node (committed to the stack, played to the
## field, or handed back to its owner), so it becomes public again.
func reveal_parked(card: Card) -> void:
	if card != null:
		card.set_revealed(true)

func _on_hand_charge_start(card: Card) -> void:
	if card.type == Card.SUMMON:
		# Paid for (and targeted) before it legally enters the stack.
		summon_casting_card = card
		summon_mana_deferred_until_target_confirm = true
		# OPPONENT SUMMONS GET A DEDICATED FLIGHT. Hand.charge() has already staged the cast
		# card at the middle of the face-down fan, so this transform is already the hand
		# middle — and the card is visibly leaving the hand rather than appearing there.
		var opponent_cast: bool = card.controller == Card.OPPONENT
		var start: Transform3D = card.global_transform
		if opponent_cast:
			park_card(card)
			_fly_opponent_summon(card, start)
		else:
			card.stop_hand_layout()
			card.set_cast_pending_highlight(true)
	else:
		# A CHARACTER IS PARKED IN THE FAKE STACK while its cost is paid. It is
		# not in `cards`, so it is not legally on the stack; `park_card()` gives
		# it the Stack presentation, then the thin gold aura marks it as the play.
		casting_card = card
		if card.controller == Card.PLAYER:
			# THE CHARACTER IS NOT A STACK CARD. It stays parented to the hand,
			# in the latched cast stance, through payment; the Stack only holds the
			# reference that cast_card() will fade from.
			card.stop_hand_layout()
		else:
			park_card(card)
		card.set_cast_pending_highlight(true)




func opponent_launch_offset(owner_hand: Hand) -> Vector3:
	if opponent_flight_path == null or opponent_flight_path.curve == null or opponent_flight_path.curve.point_count < 3:
		return Vector3.ZERO
	return opponent_flight_path.to_global(opponent_flight_path.curve.get_point_position(0)) - owner_hand.global_position

## The first two curve points are the launch and the frame-132 waypoint.
## The final point follows the actual slot, including any fan layout changes.
func _fly_opponent_summon(card: Card, start: Transform3D, entrance_curve: Curve3D = null) -> void:
	if opponent_flight_path == null or opponent_flight_path.curve == null:
		return
	var curve := opponent_flight_path.curve
	if curve.point_count < 3:
		return
	_stop_opponent_summon_flight()
	card.stop_stack_layout()
	# The mesh's reverse side hides the artwork until the pitch turns the front
	# toward the viewer. Install the stack face before the first flight frame.
	card.set_revealed(true)
	var flight_curve: Curve3D = entrance_curve if entrance_curve != null else curve.duplicate()
	flight_curve.set_point_position(0, opponent_flight_path.to_local(start.origin))
	var last := flight_curve.point_count - 1
	var slot := calculate_card_position(card.index)
	flight_curve.set_point_position(last, opponent_flight_path.to_local(to_global(slot)))
	# Start half a turn from the landing pose, then unwind around the card's
	# local +X (screen right). Keeping the angle signed fixes the flip direction.
	var launch_pose := _stack_card_local_basis(card, 0.0)
	card.quaternion = (launch_pose * Basis(Vector3.RIGHT, PI)).get_rotation_quaternion()
	card.scale = Vector3.ONE * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE)
	card.global_position = opponent_flight_path.to_global(flight_curve.get_point_position(0))
	var flight := create_tween()
	_opponent_summon_flight = flight
	_opponent_summon_flight_card = card
	flight.tween_method(func(p: float) -> void:
		if not is_instance_valid(card) or card.get_parent() != self:
			return
		if not layout_cards().has(card):
			return
		var destination := opponent_flight_path.to_local(to_global(calculate_card_position(card.index)))
		if not destination.is_equal_approx(flight_curve.get_point_position(last)):
			flight_curve.set_point_position(last, destination)
		var segment: float
		var remaining_pitch: float
		if p <= OPPONENT_CENTER_TIME:
			var approach := p / OPPONENT_CENTER_TIME
			segment = approach
			remaining_pitch = lerpf(PI, PI * 0.5, approach)
		else:
			var t := (p - OPPONENT_CENTER_TIME) / (1.0 - OPPONENT_CENTER_TIME)
			# Match the linear start of this leg, then arrive with zero speed.
			var settle := t + t * t * (1.0 - t)
			segment = lerpf(1.0, float(last), settle)
			remaining_pitch = lerpf(PI * 0.5, 0.0, settle)
		var stack_pose := _stack_card_local_basis(card, smoothstep(0.0, 1.0, p))
		card.quaternion = (stack_pose * Basis(Vector3.RIGHT, remaining_pitch)).get_rotation_quaternion()
		card.global_position = opponent_flight_path.to_global(flight_curve.samplef(segment))
	, 0.0, 1.0, opponent_flight_seconds)
	# Presentation only: nothing in the rules awaits this flight (the cast commits at once).
	await flight.finished
	_opponent_summon_flight = null
	_opponent_summon_flight_card = null
	if is_instance_valid(card) and card.get_parent() == self and layout_cards().has(card):
		if cards.has(card):
			reveal_parked(card)
		update_card_positions()

## LOCAL SUMMON, RULES half (at commit): the cast moves to a separate stack card that keeps its picks; the printed
## card only fades. The swap happens NOW, so the stack's contents never change in the middle of an animation.
func _queue_local_summon(card: Card) -> void:
	card.set_cast_pending_highlight(false)
	var effect_card: Card = game.create_card(card.id, card.controller, card.uid)
	effect_card.key_word_effect = card.key_word_effect
	effect_card.effect_kind = card.effect_kind
	effect_card.set_effect_targets(card.effect_targets)
	var slot_index: int = cards.find(card)
	cards[slot_index] = effect_card
	effect_card.index = slot_index
	add_child(effect_card)
	effect_card.enter_zone(Card.Zone.STACK)
	# Not drawn until its flight starts; layout leaves it alone meanwhile (_local_summon_presentation).
	effect_card.visible = false
	_local_summon_presentation = effect_card
	# Reserve the incoming top slot now, so the existing fan shifts.
	update_card_positions()
	_local_summon_fading = card
	Vfx.present(func() -> void: await _present_local_summon(card, effect_card))

## LOCAL SUMMON, PRESENTATION half (queued): fade the printed card where it is, then fly the stack card in.
func _present_local_summon(printed: Card, effect_card: Card) -> void:
	if is_instance_valid(printed):
		await printed.teleport.play_out(0.08, 0.20).finished
		if is_instance_valid(printed):
			printed.queue_free()
	_local_summon_fading = null
	if is_instance_valid(effect_card) and effect_card.get_parent() == self:
		var camera := get_viewport().get_camera_3d()
		var size := get_viewport().get_visible_rect().size
		var pixel := size * Vector2(0.5, 1.05)
		var plane := Plane(Vector3.UP, global_position.y - 0.35)
		var hit = plane.intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
		var launch := effect_card.global_transform
		launch.origin = hit if hit != null else camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * 6.0
		effect_card.visible = true
		await _fly_local_summon_translation(effect_card, launch.origin)
	_local_summon_presentation = null
	update_card_positions()
	local_summon_landed.emit()

## Local Summon: rise through a parabolic arc, turn edge-on at its apex, then reveal.
func local_summon_flight_seconds() -> float:
	return 50.0 / 60.0

func _fly_local_summon_translation(card: Card, launch: Vector3) -> void:
	_stop_opponent_summon_flight()
	card.stop_stack_layout()
	card.set_revealed(true)
	card.basis = _stack_card_local_basis(card).scaled(Vector3.ONE * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE))
	var camera := get_viewport().get_camera_3d()
	var screen_start := camera.unproject_position(launch)
	var screen_height := get_viewport().get_visible_rect().size.y
	var sample := func(p: float) -> void:
		if not is_instance_valid(card) or card.get_parent() != self:
			return
		# The rules may have moved on while this flight waited its turn (the card already resolved): stop following it.
		if not layout_cards().has(card):
			return
		var destination := to_global(calculate_card_position(card.index))
		var destination_screen := camera.unproject_position(destination)
		# Preserve the established rotation waypoint while lowering translation only.
		var peak_t := clampf(0.5 + (screen_start.y - destination_screen.y) / (8.0 * screen_height * 0.32), 0.1, 0.95)
		# The reference spends most of its final 30 frames settling very slowly.
		# One continuous exponential ease, normalized to land exactly at frame 50.
		var motion_p := (1.0 - exp(-3.2 * p)) / (1.0 - exp(-3.2))
		var t := motion_p + motion_p * motion_p * (1.0 - motion_p)
		# Hermite segments share a nonzero angular velocity at the peak.
		var before_peak := t <= peak_t
		var span := peak_t if before_peak else 1.0 - peak_t
		var u := t / span if before_peak else (t - peak_t) / span
		var from_angle := PI if before_peak else PI * 0.5
		var to_angle := PI * 0.5 if before_peak else 0.0
		var from_slope := -PI * span
		var to_slope := -PI * span if before_peak else 0.0
		var turn := (2.0 * u * u * u - 3.0 * u * u + 1.0) * from_angle \
			+ (u * u * u - 2.0 * u * u + u) * from_slope \
			+ (-2.0 * u * u * u + 3.0 * u * u) * to_angle \
			+ (u * u * u - u * u) * to_slope
		# Rotation uses elapsed descent time rather than the heavily eased spatial
		# progress, so it continues unfolding during the long settling approach.
		var low := 0.0
		var high := 1.0
		for _iteration in range(18):
			var middle := (low + high) * 0.5
			var m := (1.0 - exp(-3.2 * middle)) / (1.0 - exp(-3.2))
			if m + m * m * (1.0 - m) < peak_t:
				low = middle
			else:
				high = middle
		var peak_time := (low + high) * 0.5
		var rotation_descent := clampf((p - peak_time) / (1.0 - peak_time), 0.0, 1.0)
		if not before_peak:
			var peak_m := (1.0 - exp(-3.2 * peak_time)) / (1.0 - exp(-3.2))
			var spatial_speed := (1.0 + 2.0 * peak_m - 3.0 * peak_m * peak_m) * 3.2 * exp(-3.2 * peak_time) / (1.0 - exp(-3.2))
			var power := maxf(1.1, 2.0 * spatial_speed * (1.0 - peak_time))
			turn = PI * 0.5 * pow(1.0 - rotation_descent, power)
		var axes := camera.global_basis.orthonormalized()
		var facing := global_basis.orthonormalized().inverse() * Basis(axes.x, axes.z, -axes.y)
		var final_pose := _stack_card_local_basis(card)
		var settling := 1.0 - pow(1.0 - rotation_descent, 2.0)
		var base := Basis(facing.get_rotation_quaternion().slerp(final_pose.get_rotation_quaternion(), settling))
		# Local Y turns the artwork upside down in its own plane; local Z
		# brings the back through edge-on to the front. No animated X turn.
		var y_turn := turn * (1.0 - smoothstep(0.0, 0.30, rotation_descent))
		var z_turn := turn
		# The reference stays foreshortened after the reveal: its upper edge
		# recedes in depth before the card opens fully. This is a small depth
		# tilt, not the earlier full X-axis flip.
		var depth_tilt := deg_to_rad(40.0) * rotation_descent * rotation_descent * pow(1.0 - rotation_descent, 8.0) / (0.04 * pow(0.8, 8.0))
		card.basis = (base * Basis(Vector3.UP, y_turn) * Basis(Vector3.BACK, z_turn) * Basis(Vector3.RIGHT, depth_tilt)).scaled(Vector3.ONE * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE))
		var screen := screen_start.lerp(camera.unproject_position(destination), t)
		screen.y -= screen_height * 0.24 * 4.0 * t * (1.0 - t)
		var plane := Plane(Vector3.UP, lerpf(launch.y, destination.y, t))
		var hit = plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
		if hit != null:
			card.global_position = hit
		_clear_local_flight_from_stack(card, camera)
		if p >= 1.0:
			card.global_position = destination
	sample.call(0.0)
	var flight := create_tween()
	_opponent_summon_flight = flight
	_opponent_summon_flight_card = card
	flight.tween_method(sample, 0.0, 1.0, local_summon_flight_seconds())
	await flight.finished
	_opponent_summon_flight = null
	_opponent_summon_flight_card = null

## Keep the entire rotating face above the existing stack, not just its centre.
## Moving on the viewing ray preserves the centre's screen-space trajectory.
func _clear_local_flight_from_stack(card: Card, camera: Camera3D) -> void:
	var normal := (global_basis.orthonormalized() * _stack_card_local_basis(card)).y.normalized()
	var ceiling := -INF
	for other in cards:
		if other == card or not is_instance_valid(other) or other.get_parent() != self:
			continue
		ceiling = maxf(ceiling, _card_face_depth_range(other, normal).y)
	if ceiling == -INF:
		return
	var bottom := _card_face_depth_range(card, normal).x
	var missing := ceiling + 0.003 - bottom
	if missing <= 0.0:
		return
	var toward_camera := -camera.project_ray_normal(camera.unproject_position(card.global_position))
	var alignment := toward_camera.dot(normal)
	if alignment > 0.05:
		card.global_position += toward_camera * (missing / alignment)

func _card_face_depth_range(card: Card, normal: Vector3) -> Vector2:
	var half := card._card_face_size() * 0.5
	var result := Vector2(INF, -INF)
	for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		var depth: float = card.hand_mesh.to_global(corner).dot(normal)
		result.x = minf(result.x, depth)
		result.y = maxf(result.y, depth)
	return result

func _stop_opponent_summon_flight() -> void:
	if _opponent_summon_flight != null and _opponent_summon_flight.is_valid():
		_opponent_summon_flight.kill()
	_opponent_summon_flight = null
	_opponent_summon_flight_card = null


func _on_assistant_charge_cancelled() -> void:
	if skill_activation_proxy != null:
		# BACK ONE STEP, NOT OUT. A special ability is a TWO-STEP payment — pick the card that shares its name, then pay
		# the mana — so backing out of the MANA step returns to the s-cost step inside the same activation. The proxy is
		# kept, and with it the tap: cancelling AT the s-cost step is what abandons the activation, which is the branch
		# below. The previous pick is redone from scratch — its pink ring goes with it and begin_s_cost_selection()
		# re-prompts.
		if s_cost_selected_card != null:
			var src: Card = s_cost_source
			var idx: int = s_cost_skill_index
			if is_instance_valid(s_cost_selected_card):
				s_cost_selected_card.set_s_cost_highlight(false)
			s_cost_selected_card = null
			begin_s_cost_selection(src, idx)
			return
		_clear_skill_proxy()
		return
	if summon_casting_card != null:
		# It goes back to its owner's hand, so it must be face-up again.
		_stop_opponent_summon_flight()
		reveal_parked(summon_casting_card)
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		return
	if casting_card != null:
		# The Character is parked on the Stack: make it public again, remove the
		# gold aura, and let its own Hand take it back.
		reveal_parked(casting_card)
		casting_card.set_cast_pending_highlight(false)
		casting_card = null
		update_card_positions()
		return
	if cards.is_empty():
		return
	var card = cards.pop_back()
	if card.is_effect_card():
		card.queue_free()
	update_card_positions()


func _on_field_add_card_effect_to_stack(card_id: int, keyword: String, source: Card) -> void:
	create_card(card_id, source.controller, keyword, source)
	update_card_positions()

func create_card(id, controller, keyword, source, wording: String = "") -> Card:
	var card: Card = card_scene.instantiate()  
	card.initialize(id,controller)
	# A stack object is something the rules can target (a counter), so it gets a stable uid like any card.
	game.assign_uid(card)
	card.key_word_effect = keyword
	card.effect_source = source
	card.effect_kind = "Ability"
	add_created_card_to_tree(card, wording)
	update_card_positions()
	
	return card

## Enqueue a board-wide event trigger as a normal stack object. It must be a Card so the UI can show it and the
## ordinary priority loop can let either player respond; `event_trigger`/`event_context` make it resolve differently.
## A code-defined triggered ability. Its effect object is stateless; the stack copy carries the event name and a small
## event payload until Game resolves it through CardEffect.dispatch.
func enqueue_code_trigger(source: Card, event, data: Dictionary = {}) -> Card:
	var event_id := EVENTS.normalize(event)
	var card: Card = create_card(source.id, source.controller, "__code_event", source)
	card.effect_event = event_id
	card.effect_event_data = data.duplicate(true)
	card.effect_kind = "Ability"
	update_card_positions()
	return card

func enqueue_event_trigger(source: Card, trigger: Dictionary, context: Dictionary) -> Card:
	var wording := str(trigger.get("text", ""))
	var card: Card = create_card(source.id, source.controller, "__event_trigger", source, wording)
	card.event_trigger = trigger.duplicate(true)
	card.event_context = context.duplicate()
	card.effect_kind = "Ability"
	update_card_positions()
	return card

## CANCEL a stack object without resolving it (Summoner 53 countering a Summon). It was already paid for, so the card
## goes to its owner's Break Zone. Removing it from `cards` is enough to stop it resolving — the priority loop takes
## the top of that list — and the fan is re-laid out immediately.
func cancel_stack_card(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not cards.has(card):
		return
	LOG.info("Counter", "%s is cancelled" % card.card_name)
	cards.erase(card)
	if summon_casting_card == card:
		summon_casting_card = null
	if casting_card == card:
		casting_card = null
	var pile = game.get("player_graveyard") if card.controller == Card.PLAYER else game.get("opponent_graveyard")
	if pile != null:
		pile.add_card(card)
	update_card_positions()

func resolve_top_effect() -> void:
	# No wait for a Summon's flight here: resolution always follows a priority decision, and every decision waits
	# for the presentation queue (Agent._settle), so the flight has landed before anyone sees it resolve.
	## Stack resolution: run effect instructions only; costs were applied at
	## commit for skills. The effect handler may await a modal (e.g. Auron's
	## "may play a Backup" choice), so resolution waits for the game to signal
	## resolution_complete before continuing.
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
	# CLOSE THE GAP. A card leaving the stack is the same event as a card leaving the hand: the remaining fan has to
	# reflow, or every resolved effect leaves a hole where its card used to be. Same call the skill-proxy teardown
	# above already makes, and it also refreshes the hover/review link (update_card_positions ends with
	# refresh_target_display).
	update_card_positions()
	if card == skill_activation_proxy:
		skill_activation_proxy = null
		skill_mana_deferred_until_target_confirm = false
	LOG.info("Stack", str("resolve ", card.card_name))
	resolution_pending = true
	execute_card_effect.emit(card)
	if resolution_pending:
		await resolution_complete
	resolution_pending = false
	if len(cards) == 0:
		# The stack is done, so any "the opponent chose this" reveal is spent. Clearing it
		# here — rather than never — is what stops the red ring from outliving the effect.
		field.clear_targeted_highlights()
		GlobalVariables.refresh_mode()

	


func _on_field_request_target_confirmation(target_card: Card, _allow_cancel: bool = false) -> void:
	if summon_casting_card != null:
		# A STAGED SUMMON records every pick, not just the last (Hades: Forward + Backup). The single-target
		# assignment stays for the ordinary case.
		var summon_picks: Array = game.field.targeting_picked
		if summon_picks.size() > 1:
			summon_casting_card.set_effect_targets(summon_picks)
		else:
			summon_casting_card.effect_target = target_card
		return
	# AN EMPTY STACK IS NOT AN ERROR HERE. A multi-target session emits this once per pick, and by a later pick the effect
	# may already have resolved and been popped — there is simply no stack object left to record a target on, and
	# `cards[-1]` on an empty array is what threw "Invalid access of index '-1' on a base object of type: 'Array'".
	# NOTE for whoever reads this next: `effect_target` can only ever hold ONE card, so it is the LAST pick. An effect
	# that wants all of them reads Field.targeting_picked instead (see Game.untap_targets for 1-064).
	if cards.is_empty():
		return
	var effect_card: Card = cards[-1]
	# THE WHOLE SESSION, not just the card this call carries. A multi-target session calls this once per pick, so
	# assigning the single card would leave only the last one — which is exactly the wall this had. The session's picks
	# are captured HERE, at the moment of the pick: from then on the EFFECT owns them, and nothing downstream has to go
	# looking in the targeting UI's state, which the next session overwrites.
	var picks: Array = game.field.targeting_picked
	if picks.size() > 1:
		effect_card.set_effect_targets(picks)
	else:
		effect_card.effect_target = target_card

## THE PLAY HAS LANDED, so break the crystals that paid for it — and take the row down with them.
##
## This is the moment a play becomes legal, and it is deliberately NOT Assistant.on_charge_complete(): that fires when
## the payment modal is confirmed, which for a Summon is BEFORE its target is chosen, and for an ability is BEFORE its
## activation is committed. Both of those steps can still be cancelled — and cancelling REFUNDS the mana — so
## breaking the crystals there meant they shattered for a play that never happened.
##
## The row is HELD on screen between those two moments (Assistant.cost_row_hold) precisely so the crystals are still
## visible here. Breaking them while they are up is the whole point: the shards come out of something the player can
## see, instead of appearing out of nothing after the crystals have already gone.
##
## Called from the three places a play actually lands: a Character going to the field, a Summon entering the stack,
## and an ability whose costs are paid and whose target, if any, is chosen. The shatter is now the whole payment
## effect — there are no payment orbs to wait for — so callers may let it run alongside the card presentation.
func _shatter_paid_cost() -> void:
	if assistant != null:
		await assistant.commit_cost_readout()

func _on_assistant_target_complete() -> void:
	# AN EX BURST IS NOT A SKILL ACTIVATION. With no Summon parked and no skill proxy there is nothing to commit:
	# the target belonged to a damage card's ex burst, which resolves itself and never touches this node. Without
	# this guard the handler hid the buttons and emitted request_priority, which reads exactly like "the effect
	# went to the stack" - and it never set the Game's _targets, so the ex burst's damage then resolved against
	# nothing at all. That was both halves of the report.
	#
	# BUT A TRIGGERED ABILITY CAN HAVE SEVERAL TARGETS ("choose up to 5 Backups you control", Rikku). A single target
	# is already attached by request_target_confirmation as each pick is made; a LIST has to be copied onto the stack
	# object here, or the effect resolves against only the last one.
	if summon_casting_card == null and skill_activation_proxy == null:
		var chosen: Array = game.field.targeting_picked
		var top: Card = cards.back() if not cards.is_empty() else null
		if top != null and chosen.size() > 1:
			top.set_effect_targets(chosen)
		return
	if summon_casting_card != null:
		_commit_summon_to_stack()
		_shatter_paid_cost()      # the Summon is on the stack
		request_priority.emit()
		return
	# DIVIDE DAMAGE IS CHOSEN BEFORE THE ABILITY COMMITS. "Divide 6000 damage among them as you like" (Yuffie's
	# Bloodfest) is part of PLAYING the ability, not of resolving it — which is exactly what lets Cancel on the
	# distribution screen step back to target selection instead of stranding a committed effect.
	var pool: int = _divide_damage_total(skill_activation_proxy)
	if pool >= 0:
		var field_ref = game.field
		var picks: Array = field_ref.targeting_picked.duplicate()
		var owner_id: int = 1 if skill_activation_proxy.controller == Card.PLAYER else 2
		var agent: Agent = game.agent_for(owner_id)
		var split: Array = await agent.choose_damage_split(owner_id, picks, pool)
		if split.is_empty():
			# BACK ONE STEP. The targeting session was never torn down — picks and arcs are intact — so the only thing
			# missing is the TARGET modal and its Confirm button. Costs already paid stay paid: the ability is still
			# being activated, the player is only redoing this choice.
			GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
			field_ref.request_target_confirmation.emit(
				picks.back() if not picks.is_empty() else null, field_ref.targeting_allow_cancel)
			return
		game.set_damage_division(split)
	commit_skill_activation_costs_if_pending()
	_shatter_paid_cost()          # activation committed: costs paid, target chosen
	# Same as the no-target path below: clear the button that got us here, then put the player's pass button back. Hiding the
	# rack alone leaves the parked priority round with nothing to be answered by.
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	request_priority.emit()

## The damage pool for an ability that says "divide N damage among them", or -1 when it says no such thing.
## Read from the SKILL DEF of the source, because the stack object is a proxy with no skill array of its own.
func _divide_damage_total(proxy: Card) -> int:
	if proxy == null:
		return -1
	if proxy.ability_spec != null and proxy.ability_spec.divide_total > 0:
		return proxy.ability_spec.divide_total
	var def: Dictionary = proxy.skill_def_override
	if def.is_empty():
		if proxy.skill_activation_index < 0:
			return -1
		var src: Card = proxy.effect_source
		if src == null:
			return -1
		def = src.activation_skill(proxy.skill_activation_index)
	if def.is_empty():
		return -1
	for instruction in def.get("instructions", []):
		if str(instruction.get("name", "")) == "divide_damage":
			var args: Array = instruction.get("argument", [])
			return int(args[0]) if not args.is_empty() else 0
	return -1

func confirm_skill_without_target_then_priority() -> void:
	commit_skill_activation_costs_if_pending()
	_shatter_paid_cost()          # activation committed: a skill with no target needs no confirmation
	# REPLACE THE CONFIRM WITH THE PASS BUTTON — do not just clear the rack.
	#
	# The confirm that got here came from generate_confirm_button() and shares the rack with the pass button. Left standing,
	# it hides the pass button and the player has no control. But HIDING THE WHOLE RACK IS JUST AS BAD, and worse in a way
	# that is easy to miss: the priority round that is PARKED on the human is still waiting for a pass, and clearing the
	# buttons takes away the very button it is waiting for. That version of this fix left the player staring at an empty
	# screen with the effect on the stack — which is exactly what happened.
	#
	# hide_buttons() then show_pass_priority_button(): the first removes the stale confirm, the second puts the player's
	# only remaining control back. Both skill paths do this so neither can forget.
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	request_priority.emit()

func _on_assistant_target_cancel() -> void:
	## Only activated-ability (skill) flow may abort and remove the stack copy; ETB is mandatory.
	if skill_activation_proxy != null:
		_clear_skill_proxy()
	elif summon_casting_card != null:
		# Payment was deferred and is now refunded: nothing is discarded or
		# tapped, and the summon returns to hand without entering the stack.
		_stop_opponent_summon_flight()
		var cancelled: Card = summon_casting_card
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		# It is going back to its owner's hand, so reveal it again.
		reveal_parked(cancelled)
		_owner_hand(cancelled).cancel_summon_cast()

## CARD INPUT. Card forwards a click and a hover to whichever zone it sits in; these are the Stack's.
##
## A stack object is resolved by the game rather than played by a player, so its only interaction is a click: that
## selects it, which raises it in the fan and puts ITS targeting on display (see select_card).
##
## ONE EXCEPTION: while a targeting session asks for a STACK card (Summoner 53 countering a Summon), a click on a
## legal candidate means "choose this", not "raise this". `is_valid_target` is the same flag every other candidate
## uses, and the Field owns the session, so this branch only forwards the click.
func on_card_grabbed(card: Card) -> void:
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET and card.is_valid_target:
		var field = game.get("field")
		if field != null:
			field.set_target_card(card)
			_mark_input_handled(card)
			return
	select_card(card)
	# Mark the event handled so the "a click anywhere else returns the display to the top of the
	# stack" fallback cannot immediately undo the selection the player just made.
	_mark_input_handled(card)

func on_card_hovered(card: Card, entered: bool) -> void:
	set_hovered(card, entered)

func _mark_input_handled(card: Card) -> void:
	var viewport: Viewport = card.get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
