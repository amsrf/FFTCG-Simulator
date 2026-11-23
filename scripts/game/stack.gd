extends Node3D
class_name Stack
const PRESENTATION := preload("res://scripts/core/presentation.gd")
const LOG := preload("res://scripts/core/log.gd")
## The Game this zone belongs to. Every call into the game goes through this one declared dependency rather
## than through get_parent() calls scattered around. A getter, not @onready, so it also works during _ready().
var game: Game:
	get:
		return get_parent()

const EVENTS := preload("res://scripts/effects/events.gd")
const TRIGGER_TEXT := preload("res://scripts/effects/trigger_text.gd")

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
## TRIGGERED ABILITIES WAITING FOR THEIR ENTRANCE. The rules put the stack card in its slot at once; the node stays
## hidden there until its queued flight starts (_present_trigger_entry), and the layout, arrows and shadows leave it
## alone meanwhile — exactly as they do for the card that is flying.
var _incoming_triggers: Array[Card] = []
## Triggered-ability cards whose entrance (queued wait + flight) has not finished; `trigger_entered` fires as each one
## ends, however it ends. What Game.run_ex_burst waits on before resolving.
var _trigger_flights: Array[Card] = []
## AN OPPONENT'S ABILITY BEING ACTIVATED. Its proxy exists for the rules (costs, targets) but nobody else may see it until
## everything is paid: hidden, and left out of the layout, until commit_skill_activation_costs_if_pending() flies it in.
## Untyped: a cancelled proxy can be freed while listed.
var _hidden_activations: Array = []
## TRIGGERED ABILITIES THAT STILL OWE THEIR CHOICE. An auto-ability that chooses (TriggerSpec.chooses) is on the stack
## from the moment it triggers, but its controller declares the targets the next time anyone would gain priority
## (declare_trigger_choices, called from Game.apply_rule_processes). Untyped: a copy can be freed while listed.
var _owed_trigger_choices: Array = []
var _declaring_trigger_choices: bool = false
signal trigger_entered(card: Card)
## A triggered-ability card's flight onto the stack has just STARTED (it is visible from this moment).
signal trigger_flight_started(card: Card)
## The trigger cards waiting for the next group presentation, and whether that presentation is already queued.
var _trigger_batch: Array[Card] = []
var _trigger_batch_posted: bool = false
## AN EX BURST'S STACK CARD WHILE IT FLIES IN (stage_ex_burst / commit_ex_burst). Purely for the eye: it is laid out on
## the stack like any effect, but it is NOT in `cards`, so no priority round can see it and nobody can respond to it.
var ex_burst_card: Card = null
## True while an effect resolution is still running (it may await a modal).
var resolution_pending: bool = false
## THE STACK OBJECT THAT IS RESOLVING. It has left `cards` (no priority round can see it, nothing can target it on the
## stack), but it stays LAID OUT in its slot until its effect has fully resolved — choices, modals and animations
## included — so the player still sees what is resolving while they decide (Gadot's "you may play a Forward").
## `resolving_slot` is where it sat; anything put on the stack during the resolution lands above it.
var resolving_card: Card = null
var resolving_slot: int = 0
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

## True while `card` is already committed to pay another cost of the activation in progress - including the SOURCE
## whose 《Dull》 is part of the cost: it is dulled only at commit, so until then it must not also produce the mana
## (Red Mage paying its own 《1》).
func is_reserved_for_cost(card: Card) -> bool:
	return card == s_cost_selected_card or pending_cost_sacrifices.has(card) or pending_cost_discards.has(card) \
		or card == _pending_dull_source()

func _pending_dull_source() -> Card:
	if not skill_mana_deferred_until_target_confirm or skill_activation_proxy == null \
			or not is_instance_valid(skill_activation_proxy):
		return null
	if not bool(skill_activation_proxy.skill_def_override.get("tap", false)):
		return null
	var source = skill_activation_proxy.effect_source
	return source if source is Card and is_instance_valid(source) else null
@onready var field: Field = game.get_node("Field") as Field
@onready var hand: Hand = game.get_node("Player/Hand") as Hand
@onready var assistant: Assistant = game.get_node("Assistant") as Assistant
@onready var card_scene = preload("res://scenes/cards/card.tscn")

signal execute_card_effect(card:Card)
signal request_priority()
## An ability activation paid everything and is on the stack (online play sends the draft now).
signal skill_activation_committed(proxy: Card)
## The human picked the same-named card for an S ability's cost.
signal s_cost_chosen(card: Card)
## Emitted by the game when a stack effect has fully finished resolving.
signal resolution_complete

func _ready() -> void:
	assistant.choose_card_finished.connect(_on_choose_card_finished)

## Cards to lay out: the legal stack objects plus the parked card (Summon or
## Character). Positioning MUST go through this — using `cards` alone leaves the
## parked card out of the row width, which offsets every card.
func layout_cards() -> Array:
	var list: Array = cards.duplicate()
	if _resolving_card_on_display() and not list.has(resolving_card):
		list.insert(clampi(resolving_slot, 0, list.size()), resolving_card)
	if ex_burst_card != null and is_instance_valid(ex_burst_card) and not list.has(ex_burst_card):
		list.append(ex_burst_card)
	var parked = summon_casting_card if summon_casting_card != null else casting_card
	if parked != null and parked.current_zone == Card.Zone.STACK:
		list.append(parked)
	for hidden in _hidden_activations:
		list.erase(hidden)
	return list

## The resolving card is shown only while it is still physically on the Stack: a resolved Summon is reparented into
## the Break Zone and a stack copy is queue_free'd, and from that moment it is no longer the stack's to lay out.
func _resolving_card_on_display() -> bool:
	return resolving_card != null and is_instance_valid(resolving_card) \
			and not resolving_card.is_queued_for_deletion() and resolving_card.get_parent() == self

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
@export_group("Triggered Abilities")
## SIMULTANEOUS TRIGGERS DO NOT SPAWN TOGETHER. Abilities put on the stack at the same moment fly in as one group: each
## flight starts this long after the previous one STARTED, so they overlap but still read as separate arrivals.
@export_range(0.05, 1.0, 0.01) var trigger_stagger_seconds: float = 0.25
## AN EFFECT OF A CARD ON THE FIELD COMES OUT OF THAT CARD (_fly_from_source): it appears over the source, small,
## upright and facing the camera, and travels to its stack slot, turning into the stack pose and growing as it goes.
@export_range(0.15, 1.5, 0.01) var source_flight_seconds: float = 0.45
## How long a blinking source stays up and lit at the top before it settles (triggers and committed abilities alike).
@export_range(0.0, 1.5, 0.01) var blink_hold_seconds: float = 0.3
## The pause after a source has blinked (and, for an ability, dulled) before its card leaves for the stack. Shared by
## committed abilities and triggers.
@export_range(0.0, 1.0, 0.01) var blink_to_flight_seconds: float = 0.2
## The effect card's size where it appears, as a fraction of its size on the stack.
@export_range(0.1, 1.0, 0.01) var source_flight_start_scale: float = 0.35
## How far in front of the source (toward the camera, metres) it appears, so the source does not cut through it.
@export_range(0.0, 1.5, 0.01) var source_flight_lift: float = 0.35
@export_group("Opponent Summon Flight")
@export_range(0.30, 2.0, 0.01) var opponent_flight_seconds: float = 32.0 / 60.0
@export var opponent_flight_path: Path3D
const OPPONENT_CENTER_TIME := 14.0 / 32.0

func _refresh_stack_pose() -> void:
	if is_inside_tree() and is_node_ready():
		update_card_positions()

## Shallow arc and per-card tilt, mirroring the hand: a plain row collapsed into one unreadable
## overlap as soon as a third card arrived.
const STACK_HOVER_SCALE := 1.15  # on top of STACK_CARD_SCALE 2.7 (was 1.4 on 1.35); 1.4 would cover half the screen
## Height between neighbours, so the card in front is visibly in front.
const FAN_HEIGHT_STEP := 0.016
## A selected card lifts within its slot so every newer card remains higher.
const FAN_RAISE := FAN_HEIGHT_STEP * 0.35
var _shadow_track_seconds := 0.0
## The review link's arrow, kept separate from the live targeting arrow and the block arc so the
## three can never re-aim or hide each other.
const LINK_ARROW_SCENE := preload("res://scenes/vfx/ballistic_arrow.tscn")

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
		if hovered_card == card or not cards.has(card) or card == _opponent_summon_flight_card \
				or _incoming_triggers.has(card):
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
	if field == null:
		return
	# A card still FLYING IN shows nothing yet: its arrows appear once it has arrived on the stack.
	if card == null or card == _local_summon_presentation or card == _opponent_summon_flight_card \
			or _incoming_triggers.has(card):
		_clear_target_display()
		return
	var targets: Array = card.effect_targets.duplicate()
	if targets.is_empty() and card.effect_target != null:
		targets = [card.effect_target]
	if targets.is_empty():
		_clear_target_display()
		return
	# The FIELD draws it, not the stack: BallisticArrow's points are LOCAL, and the stack node is
	# flipped and lifted, so an arrow parented here and given global points lands wherever that
	# transform carries it ("arrows in random places"). One arrow per target.
	field.show_review_links(card, targets)
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
		if card == _opponent_summon_flight_card or card == _local_summon_presentation or _incoming_triggers.has(card):
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
		_apply_chain_visibility(card, card.get("stack_tween"))

	# The stack just changed, so what is on display may have too: the default display is the TOP
	# of the stack, and after an add or a resolve that is a different card.
	refresh_target_display()
	refresh_top_aura()
	_refresh_chain_numbers()
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
	for card in _incoming_triggers:
		settled.erase(card)
	if is_instance_valid(hovered_card) and settled.has(hovered_card):
		settled.erase(hovered_card)
		settled.append(hovered_card)
	preload("res://scripts/cards/card_overlap_shadow.gd").update(self, settled)

## THE TOP SLOT (reference: ~/Desktop/Clips/damage 124-151, where the played card ends held up at the board's right edge,
## just above the river). A new top card PUSHES the older ones to the RIGHT (FAN_DIRECTION +1): they peek out from
## under its right edge. The board edge is right there, so the top slot starts at FAN_ANCHOR and slides LEFT only by
## as much of the fan as does not fit in FAN_FREE_ROOM (card widths of fan the right edge can take), keeping the
## longest fan on the wood. `_stack_spacing()` caps the fan at ~1.15 card widths however many cards there are.
const FAN_ANCHOR := Vector3(0.0, 0.0, -0.075)
## +1 = older cards peek out to the screen RIGHT of the newer one, -1 = to its LEFT.
const FAN_DIRECTION := 1.0
## How much fan (in card widths) fits right of a lone top card before the top slot has to move left.
const FAN_FREE_ROOM := 0.1

## Where the newest card sits for `count` cards on the stack: FAN_ANCHOR, moved against the fan direction by the part
## of the fan that would otherwise leave the wood.
func top_slot(count: int, pose: Basis) -> Vector3:
	var fan_length: float = maxi(0, count - 1) * _stack_spacing(count)
	var overflow: float = maxf(0.0, fan_length - FAN_FREE_ROOM * card_width)
	return FAN_ANCHOR - pose.x * FAN_DIRECTION * overflow

func calculate_card_position(i: int) -> Vector3:
	if CHAIN_LAYOUT:
		return _chain_position(i)
	return _fan_position(i)

## DRAFT (2026-11-21): THE STACK AS A CHAIN, after Master Duel. The local player's cards stand at the LEFT edge of the
## screen, the opponent's at the RIGHT, so the middle of the board stays clear. Every card has its OWN height, by its
## place in the whole chain (not in its side's column): the newest stands at CHAIN_Y (river height) and each older card,
## whichever side it is on, steps UP the screen, BACK from the camera and smaller. Only the newest CHAIN_VISIBLE cards are
## shown; older ones slide up out of the column and are hidden until the chain shrinks (browse arrows: later).
## Every card wears its chain number (1 = first on the stack, resolves last) just outside its outer edge, level with its
## header. The left side's yaw is the right side's mirrored (`_stack_card_local_basis`). Off = the single fan (`_fan_position`).
const CHAIN_LAYOUT := true
## How many of the newest chain links are on screen.
const CHAIN_VISIBLE := 3
## Card centre from the screen centre, as a fraction of the viewport width (0.365 -> x 259 / 1661 at 1920).
const CHAIN_SIDE_X := 0.365
## The newest card's centre, as a fraction of the viewport height.
const CHAIN_Y := 0.45
## Per chain link back from the newest: up the screen (fraction of height), outward (fraction of width), back from the
## camera (metres), and its size relative to the link above it.
const CHAIN_STEP_UP := 0.13
const CHAIN_STEP_OUT := 0.0
const CHAIN_STEP_BACK := 0.5
const CHAIN_SHRINK := 0.88
## Meta set on a stack card the chain has hidden (older than CHAIN_VISIBLE); Card.enter_zone() shows it again.
const CHAIN_HIDDEN_META := &"chain_hidden"

## -1 for the local player's side (left), +1 for the opponent's (right).
func chain_side(card) -> float:
	return -1.0 if card != null and card.get("controller") == Card.PLAYER else 1.0

## How many cards in the whole chain are newer than `card` (0 = the newest), whichever side they are on.
func chain_rank(card) -> int:
	var list := layout_cards()
	var index := list.find(card)
	if index < 0:
		return 0
	return list.size() - 1 - index

func chain_shown(card) -> bool:
	return not CHAIN_LAYOUT or chain_rank(card) < CHAIN_VISIBLE

## The size of a stack card relative to STACK_CARD_SCALE: 1 for the newest link.
func chain_scale(card) -> float:
	if not CHAIN_LAYOUT:
		return 1.0
	return pow(CHAIN_SHRINK, mini(chain_rank(card), CHAIN_VISIBLE))

func _chain_position(i: int) -> Vector3:
	var list := layout_cards()
	if i < 0 or i >= list.size():
		return FAN_ANCHOR
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return FAN_ANCHOR
	var card = list[i]
	var side := chain_side(card)
	# A hidden link waits one step past the last shown one: it slides up and back out of the column, and back in.
	var rank: int = mini(chain_rank(card), CHAIN_VISIBLE)
	var size := get_viewport().get_visible_rect().size
	var screen := Vector2(size.x * (0.5 + side * (CHAIN_SIDE_X + rank * CHAIN_STEP_OUT)),
		size.y * (CHAIN_Y - rank * CHAIN_STEP_UP))
	# Depth of the old anchor, so the newest card sits as far from the lens as the tuned single card did.
	var base_depth: float = (to_global(FAN_ANCHOR) - camera.global_position).dot(-camera.global_basis.z)
	return to_local(camera.project_position(screen, base_depth + rank * CHAIN_STEP_BACK))

## Shows the newest CHAIN_VISIBLE links; an older one hides once its tween has carried it out of the column.
func _apply_chain_visibility(card, tween: Tween) -> void:
	if not CHAIN_LAYOUT or not is_instance_valid(card):
		return
	if chain_shown(card):
		if card.has_meta(CHAIN_HIDDEN_META):
			card.remove_meta(CHAIN_HIDDEN_META)
			card.visible = true
		return
	if card.has_meta(CHAIN_HIDDEN_META) and not card.visible:
		return
	# Re-attached on EVERY layout pass while it is still drawn: a newer layout tween (another link arriving, a hover)
	# kills the one that carried the previous hide callback, and returning early here left the link on screen forever.
	card.set_meta(CHAIN_HIDDEN_META, true)
	if tween != null and tween.is_valid():
		tween.chain().tween_callback(func():
			if is_instance_valid(card) and card.has_meta(CHAIN_HIDDEN_META):
				card.visible = false)
	else:
		card.visible = false

const CHAIN_NUMBER_NAME := "ChainNumber"

## The chain number beside a stack card's header, on its outer side. Card.enter_zone() frees it when the card leaves the stack.
func _refresh_chain_numbers() -> void:
	var list := layout_cards()
	for index in range(list.size()):
		var card = list[index]
		if not is_instance_valid(card):
			continue
		var label: Label3D = card.get_node_or_null(CHAIN_NUMBER_NAME)
		if not CHAIN_LAYOUT:
			if label != null:
				label.queue_free()
			continue
		if label == null:
			label = Label3D.new()
			label.name = CHAIN_NUMBER_NAME
			label.font_size = 160
			label.outline_size = 36
			label.pixel_size = 0.0012
			label.modulate = Color(0.86, 0.98, 1.0)
			label.outline_modulate = Color(0.02, 0.18, 0.28)
			label.render_priority = 20
			label.outline_render_priority = 19
			label.double_sided = false
			# Label3D draws in its XY plane facing +Z; the card face is its XZ plane facing +Y, top at -Z.
			label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			card.add_child(label)
		label.text = str(index + 1)
		var face: Vector2 = card._card_face_size()
		var outer := chain_side(card)
		# Just OUTSIDE the card's outer edge, level with its header: an older card's header is the part a newer card
		# leaves showing, so its number stays readable. Aligned so the digits grow outward, away from the card.
		label.position = Vector3(outer * (face.x * 0.5 + 0.015), 0.012, -face.y * 0.5 + 0.07)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if outer > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT

func _fan_position(i: int) -> Vector3:
	var list := layout_cards()
	if list.is_empty():
		return FAN_ANCHOR
	var top := list.size() - 1
	var pose := _stack_card_local_basis(list[top])
	var spacing := _stack_spacing(list.size())
	var fraction: float = spacing / card_width
	var camera := get_viewport().get_camera_3d()
	var slot := top_slot(list.size(), pose)
	var center := slot
	# The slot's sideways part is carried by `center` (the search below works along pose.x from it); the rest is
	# added to each layer.
	var anchor_off_axis := slot - pose.x * slot.dot(pose.x)
	for index in range(top - 1, i - 1, -1):
		var layer := anchor_off_axis - pose.y * ((top - index) * FAN_HEIGHT_STEP) + pose.z * ((top - index) * spacing * 0.25)
		# `along` is the card's axis pointing the way the fan grows, so the search below is written once for both sides.
		var along: Vector3 = pose.x * FAN_DIRECTION
		var sideways := center.dot(along) + spacing
		if camera != null:
			# Screen x grows to the right; a left-growing fan (FAN_DIRECTION -1) measures in mirrored units (-x).
			var sx := func(p: Vector3) -> float: return camera.unproject_position(to_global(p)).x * FAN_DIRECTION
			var covering_edge: float = sx.call(center + along * card_width * 0.5)
			var low: float = center.dot(along) - card_width * 2.0
			var high: float = center.dot(along) + card_width * 3.0
			# Solve the exposed fraction in camera space with the newest card fixed.
			for iteration in range(24):
				sideways = (low + high) * 0.5
				var candidate := layer + along * sideways
				var near_edge: float = sx.call(candidate - along * card_width * 0.5)
				var far_edge: float = sx.call(candidate + along * card_width * 0.5)
				var exposed := (far_edge - covering_edge) / (far_edge - near_edge)
				if exposed < fraction:
					low = sideways
				else:
					high = sideways
		center = layer + along * sideways
	return center

func animate_card(card, target_position, hover_transition := false):
	# ONE LAYOUT TWEEN PER CARD. The old one has to die before a new target is
	# written, and the card has to own the reference so enter_zone() can stop it
	# when the card leaves the stack.
	if card.has_method("stop_stack_layout"):
		card.stop_stack_layout()
	var pose := _stack_card_local_basis(card)
	var size := Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE * chain_scale(card)
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
func _stack_card_local_basis(card, yaw_roll_weight: float = 1.0) -> Basis:
	# THE CARD IS HELD UP AND ANGLED, NOT SQUARE TO THE CAMERA. Start from the local pitch/roll,
	# then rotate the whole thing around the CAMERA'S UP AXIS. That last rotation is the one that
	# moves the card's left edge into the screen and its right edge out (or the reverse); the local
	# Euler angles alone only spin it inside its own plane, which is why it read as flat.
	# The chain's LEFT column (the local player's) is the right column's mirror image: every yaw/roll flips sign.
	var mirror: float = chain_side(card) if CHAIN_LAYOUT else 1.0
	var target_basis := Basis.from_euler(Vector3(
		deg_to_rad(stack_pitch_degrees),
		deg_to_rad(stack_local_yaw_degrees) * yaw_roll_weight * mirror,
		deg_to_rad(stack_roll_degrees) * yaw_roll_weight * mirror))
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var parent_basis: Basis = global_transform.basis.orthonormalized()
		var cam_up_local: Vector3 = (parent_basis.inverse() * cam.global_transform.basis.y).normalized()
		target_basis = Basis(cam_up_local, deg_to_rad(stack_screen_yaw_degrees) * yaw_roll_weight * mirror) * target_basis
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
	if casting_card.type == Card.SUMMON:
		# It is being played, so it is public now. (A Character is revealed as it dissolves, below.)
		reveal_parked(casting_card)
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
		# before the ~1.3 s teleport. A Character does not use the stack, so the
		# caster KEEPS priority (Game.note_character_cast).
		game.note_character_cast(landing)
		var owner_hand: Hand = _owner_hand(landing)
		# DISCARD FIRST: the payment cards' flights must be QUEUED before the dissolve, so they play first. Flushing
		# here makes that order explicit instead of depending on which charge_complete handler runs first.
		if owner_hand != null:
			owner_hand.flush_mana_discard()
		# The gold aura has done its job; let it fade with the card.
		landing.set_cast_pending_highlight(false)
		# PRESENTATION, queued: shine and dissolve IN PLACE, where the player sees the card. Nothing travels across the
		# board. The dissolve plays on a stand-in (play_out_ghost), so this step only holds the queue for the short
		# head start: Field's materialise (queued behind this) then begins WHILE the source is still dissolving.
		var crystal: bool = field.use_crystal_teleport
		var shine: float = field.teleport_shine_seconds
		var fade: float = field.teleport_fade_seconds
		var head_start: float = field.teleport_overlap_delay_seconds if crystal else field.hologram_head_start_seconds
		Vfx.present(func() -> void:
			if is_instance_valid(landing):
				# Public from here: the opponent's card turns face up as it dissolves out of their hand.
				landing.set_revealed(true)
				if crystal:
					landing.teleport.play_out_ghost(shine, fade)
				else:
					landing.hologram.play_out()
				if head_start > 0.0:
					await landing.get_tree().create_timer(head_start).timeout)
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
	var card: Card = summon_casting_card
	var owner_hand: Hand = _owner_hand(card)
	var local_preview := card.controller == Card.PLAYER and card.get_parent() == owner_hand
	if local_preview:
		_local_summon_presentation = card
	# Target is confirmed: finalize mana payment now (discard hand mana,
	# tap backup mana), then put the summon on the stack.
	field.apply_deferred_skill_mana_payment()
	owner_hand.apply_deferred_skill_mana_payment()
	summon_mana_deferred_until_target_confirm = false
	summon_casting_card = null
	card.key_word_effect = "when_cast"
	card.effect_kind = "Summon"
	owner_hand.finish_summon_cast(card)
	# The card is already parked on the stack node; now it legally enters
	# the stack list and resolves as a normal stack object.
	cards.append(card)
	card.index = cards.size() - 1
	card.set_cast_pending_highlight(false)
	if local_preview:
		reveal_parked(card)
		_queue_local_summon(card)
	elif card.get_parent() is Hand:
		# THE OPPONENT'S SUMMON IS PUBLIC NOW: it leaves their hand, turns face up and flies to the stack (queued, so it
		# follows whatever is still playing). Until it lands it is the flight card, which the layout leaves alone and
		# which shows no target arrow.
		var start: Transform3D = card.global_transform
		_opponent_summon_flight_card = card   # BEFORE park_card(), whose layout pass would otherwise slide it in now
		park_card(card)
		card.global_transform = start
		Vfx.present(func() -> void:
			if is_instance_valid(card) and cards.has(card):
				await _fly_opponent_summon(card, card.global_transform))
	else:
		reveal_parked(card)
		update_card_positions()
	# Casting a Summon is a priority action: it is on the stack now, so priority
	# moves to the opponent. (Emitting in the Agent's case is harmless — no one
	# is awaiting the signal; the agent reports through take_priority().)
	game.note_action_taken()


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
	s_cost_chosen.emit(chosen)
	# S cost chosen. The mana stage follows ONLY if there is mana to pay: when the cost is empty the discarded card WAS the
	# whole payment, so asking for a Confirm on an empty screen is a button that exists only to be pressed.
	var def: Dictionary = s_cost_source.activation_skill(s_cost_skill_index)
	var cost: Dictionary = def.get("cost", {})
	if field.cost_is_free(cost):
		field.continue_skill_activation_after_mana(skill_activation_proxy)
		return
	field.card_activated_ability.emit(cost, s_cost_source)

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
	# NOT an action yet: the priority window stays open while costs and targets are chosen, and a cancel leaves it as
	# if nothing happened. The action is the commit (commit_skill_activation_costs_if_pending).
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
	# NOTHING GOES ON THE STACK UNTIL IT IS PAID FOR. The proxy exists for the rules (costs, targets) but stays hidden
	# and off the layout for EVERYONE until commit_skill_activation_costs_if_pending() flies it out of the source. While
	# the local player pays, the source card itself stands raised and lit: that is what they are paying for
	# (card_activation_fx.gd). An opponent's source does not move until their play is committed.
	proxy.visible = false
	_hidden_activations.append(proxy)
	if _is_local_play(source):
		source.activation_fx.raise()
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
		# The rules dull it NOW; a source on the field shows the turn only after it has settled and blinked
		# (_present_activation_entry calls present_tap()).
		src.tap(_source_point(src) == Vector3.INF or PRESENTATION.fast_mode)

## Skill stack commit: activation is legally complete (costs paid, target on proxy if required).
## Resolution (execute instructions) happens later in resolve_top_effect -> game._on_stack_execute_card_effect.
func commit_skill_activation_costs_if_pending() -> void:
	if not skill_mana_deferred_until_target_confirm:
		return
	# An opponent's hidden proxy is revealed below, once paid. Its flight starts where the source WAS: a cost below may
	# return the source to hand or put it into the Break Zone.
	var reveal: Card = skill_activation_proxy if _hidden_activations.has(skill_activation_proxy) else null
	var reveal_from: Vector3 = _source_point(reveal.effect_source) if reveal != null else Vector3.INF
	var payer_hand: Hand = hand
	if skill_activation_proxy != null and skill_activation_proxy.effect_source != null \
			and is_instance_valid(skill_activation_proxy.effect_source):
		payer_hand = _owner_hand(skill_activation_proxy.effect_source)
	field.apply_deferred_skill_mana_payment()
	payer_hand.apply_deferred_skill_mana_payment()
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
		payer_hand.discard_card(s_cost_selected_card)
		s_cost_selected_card = null
	# The copied-skill permission is one use. Consume only the exact permission this proxy was created from; a newer
	# Ronso Rage may have replaced the slot while this activation was waiting.
	if skill_activation_proxy != null and skill_activation_proxy.copied_skill_activation:
		var copied_source: Card = skill_activation_proxy.effect_source
		if copied_source != null:
			copied_source.consume_copied_skill(skill_activation_proxy.copied_skill_token)
	skill_mana_deferred_until_target_confirm = false
	if reveal != null and is_instance_valid(reveal):
		_hidden_activations.erase(reveal)
		# Kept off the layout until its flight starts, exactly like a queued trigger card.
		_incoming_triggers.append(reveal)
		update_card_positions()
		Vfx.present(_present_activation_entry.bind(reveal, reveal_from, reveal.effect_source))
	# THE ACTIVATION IS THE ACTION: everything is paid and it sits on the stack, so priority moves on.
	skill_activation_committed.emit(skill_activation_proxy)
	game.note_action_taken()

func _clear_skill_proxy() -> void:
	# WAS THIS ACTIVATION STILL PENDING? `skill_mana_deferred_until_target_confirm` is set when the proxy is created and
	# cleared by commit_skill_activation_costs_if_pending(), so it is still true here only when the player backed out.
	# Nothing was spent (the 《Dull》 too is paid only at commit); the raised source just settles.
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
		if src != null and is_instance_valid(src):
			src.activation_fx.lower()   # backed out: the raised source settles, no flash
	cards.erase(p)
	_hidden_activations.erase(p)
	_drop_incoming(p)
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
		# IT WAITS IN ITS HAND while it is paid for and targeted, for both players: yours in the cast stance, the
		# opponent's face down where it sits. Nothing of it is public until it COMMITS: then the opponent's flies to the
		# stack face up (_commit_summon_to_stack), and the stack shows where it points.
		card.stop_hand_layout()
		card.set_cast_pending_highlight(true)
	else:
		# THE CHARACTER IS NOT A STACK CARD, for either player. It stays parented to its hand through payment (yours in
		# the latched cast stance, the opponent's where it sits in their face-down hand); the Stack only holds the
		# reference that cast_card() will fade from. The thin gold aura marks it as the play. It used to be parked in
		# the stack area for the opponent, which showed a stack trip that Characters never make.
		casting_card = card
		card.stop_hand_layout()
		card.set_cast_pending_highlight(true)




func opponent_launch_offset(owner_hand: Hand) -> Vector3:
	if opponent_flight_path == null or opponent_flight_path.curve == null or opponent_flight_path.curve.point_count < 3:
		return Vector3.ZERO
	return opponent_flight_path.to_global(opponent_flight_path.curve.get_point_position(0)) - owner_hand.global_position

## The first two curve points are the launch and the frame-132 waypoint.
## The final point follows the actual slot, including any fan layout changes.
## `shared` = this is THE Summon flight (one at a time, held in _opponent_summon_flight so a cancel can kill it). A
## triggered ability's flight passes false: several fly at once, so it must neither kill nor claim that slot.
func _fly_opponent_summon(card: Card, start: Transform3D, entrance_curve: Curve3D = null, shared: bool = true) -> void:
	if opponent_flight_path == null or opponent_flight_path.curve == null:
		return
	var curve := opponent_flight_path.curve
	if curve.point_count < 3:
		return
	if shared:
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
	# IT LEAVES THE HAND AT HAND SIZE and grows into the stack card on the way to the centre (~/Desktop/Clips/damage
	# 124-133). Starting at the stack size popped a card twice the hand's size out of the hand once STACK_CARD_SCALE
	# became 2.7. `start` is the card's world pose in the hand; Stack-local scale = world / the Stack's own scale.
	var start_scale: float = start.basis.get_scale().x / global_basis.get_scale().x
	var full_scale: float = Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE
	card.scale = Vector3.ONE * start_scale
	card.global_position = opponent_flight_path.to_global(flight_curve.get_point_position(0))
	var flight := create_tween()
	_end_flight_with_card(card, flight)
	if shared:
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
		var grow: float = smoothstep(0.0, 1.0, minf(1.0, p / OPPONENT_CENTER_TIME))
		card.scale = Vector3.ONE * lerpf(start_scale, full_scale * chain_scale(card), grow)
		card.global_position = opponent_flight_path.to_global(flight_curve.samplef(segment))
	, 0.0, 1.0, opponent_flight_seconds)
	# Presentation only: nothing in the rules awaits this flight (the cast commits at once).
	await flight.finished
	if shared:
		_opponent_summon_flight = null
		_opponent_summon_flight_card = null
	if is_instance_valid(card) and card.get_parent() == self and layout_cards().has(card):
		if cards.has(card):
			reveal_parked(card)
			reveal_targets(card)
		update_card_positions()

## THE OPPONENT'S CHOICE BECOMES VISIBLE once their play is on the stack: every card it targets gets the red ring, and
## keeps it until the stack has resolved (Field.clear_targeted_highlights). The arrows come from the stack display.
func reveal_targets(card: Card) -> void:
	if card == null or not is_instance_valid(card) or card.controller == Card.PLAYER:
		return
	for target in card.effect_targets:
		if target != null and is_instance_valid(target):
			target.set_targeted_highlight(true)

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
	# The size the player was holding it at: the stack card launches at that size and grows into the stack's.
	var held_scale: float = printed.global_basis.get_scale().x if is_instance_valid(printed) else -1.0
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
		await _fly_local_summon_translation(effect_card, launch.origin, true, held_scale)
	_local_summon_presentation = null
	update_card_positions()
	local_summon_landed.emit()

## Local Summon: rise through a parabolic arc, turn edge-on at its apex, then reveal.
func local_summon_flight_seconds() -> float:
	return 50.0 / 60.0

## `shared`: as for _fly_opponent_summon — a triggered ability's flight passes false.
## `start_world_scale` > 0: launch at that WORLD size and grow to the stack size by the apex (a Summon leaves the hand
## at the size it was held; starting at STACK_CARD_SCALE 2.7 made a huge card rise over the Backups). Triggers omit it.
func _fly_local_summon_translation(card: Card, launch: Vector3, shared: bool = true, start_world_scale: float = -1.0) -> void:
	if shared:
		_stop_opponent_summon_flight()
	card.stop_stack_layout()
	card.set_revealed(true)
	var full_scale: float = Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE
	var launch_scale: float = start_world_scale / global_basis.get_scale().x if start_world_scale > 0.0 else full_scale
	card.basis = _stack_card_local_basis(card).scaled(Vector3.ONE * launch_scale)
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
		# The turns were authored for a stack on the RIGHT of the screen. The local player's chain column is on the
		# LEFT, so their sense flips with the column (as _stack_card_local_basis mirrors the resting pose); unmirrored,
		# the card rolled against its own travel and wrenched through a distorted flip to reach the mirrored pose.
		var mirror: float = chain_side(card) if CHAIN_LAYOUT else 1.0
		var y_turn := turn * (1.0 - smoothstep(0.0, 0.30, rotation_descent)) * mirror
		var z_turn := turn * mirror
		# The reference stays foreshortened after the reveal: its upper edge
		# recedes in depth before the card opens fully. This is a small depth
		# tilt, not the earlier full X-axis flip.
		var depth_tilt := deg_to_rad(40.0) * rotation_descent * rotation_descent * pow(1.0 - rotation_descent, 8.0) / (0.04 * pow(0.8, 8.0))
		var size: float = lerpf(launch_scale, full_scale * chain_scale(card), smoothstep(0.0, peak_t, t)) \
			if launch_scale != full_scale else full_scale
		card.basis = (base * Basis(Vector3.UP, y_turn) * Basis(Vector3.BACK, z_turn) * Basis(Vector3.RIGHT, depth_tilt)).scaled(Vector3.ONE * size)
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
	_end_flight_with_card(card, flight)
	if shared:
		_opponent_summon_flight = flight
		_opponent_summon_flight_card = card
	flight.tween_method(sample, 0.0, 1.0, local_summon_flight_seconds())
	await flight.finished
	if shared:
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
		# Only SETTLED cards. Another card still flying (a staggered trigger group) is itself being lifted above the
		# rest: measuring against it makes the two leapfrog each other toward the camera every frame, off the screen.
		if _incoming_triggers.has(other) or other == _local_summon_presentation or other == _opponent_summon_flight_card:
			continue
		# THE CHAIN: only links in THIS card's column that are drawn can be flown through. Measuring the other column
		# (or a hidden link) pushed the card ~1.45x its size toward the camera for the whole descent, and it shrank
		# back the moment it landed.
		if CHAIN_LAYOUT and (chain_side(other) != chain_side(card) or not other.visible):
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

## A FLIGHT ENDS WITH ITS CARD. The flight's per-frame lambda captures the card; if the card is freed mid-flight (it
## resolved, or the match ended) the tween would go on calling it with a freed capture. When the card leaves the tree
## (still valid at that moment) the flight is run to its end, which also emits `finished` for whoever awaits it.
func _end_flight_with_card(card: Card, flight: Tween) -> void:
	card.tree_exiting.connect(func() -> void:
		if flight.is_valid() and flight.is_running():
			flight.custom_step(60.0), CONNECT_ONE_SHOT)

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
		# Back to its owner's hand. It never left it, and the opponent's was never shown, so nothing is revealed.
		summon_casting_card.set_cast_pending_highlight(false)
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
	# EVERY TRIGGERED ABILITY FLIES IN: out of its source when that card is on the field (_fly_from_source), otherwise
	# from below the screen for ours and from the top for the opponent's. The rules are not kept waiting — the card is
	# on the stack now — only the node is.
	card.visible = false
	_incoming_triggers.append(card)
	_trigger_flights.append(card)
	# ONE PRESENTATION PER GROUP. Every trigger created before the group starts joins it (_present_trigger_batch), so
	# simultaneous abilities are staggered instead of each waiting for the previous one to land. A METHOD, not a
	# lambda: a lambda capturing a card that resolves before its turn would be called with a freed capture.
	_trigger_batch.append(card)
	if not _trigger_batch_posted:
		_trigger_batch_posted = true
		Vfx.present(_present_trigger_batch)
	update_card_positions()
	
	return card

## TRIGGERED ABILITIES, PRESENTATION half (queued): fly a GROUP of stack cards in, staggered. The Vfx queue may start
## this job synchronously inside the first create_card(), before the rest of a simultaneous group exists, so it waits
## one frame first; everything enqueued until then flies in this group, in stack order (bottom first, top last).
func _present_trigger_batch() -> void:
	await get_tree().process_frame
	var group: Array[Card] = []
	for card in _trigger_batch:
		if is_instance_valid(card):
			group.append(card)
	_trigger_batch.clear()
	_trigger_batch_posted = false
	await _flash_trigger_sources(group)
	for i in range(group.size()):
		if i > 0:
			await PRESENTATION.wait(get_tree().create_timer(trigger_stagger_seconds))
		_present_trigger_entry(group[i])   # not awaited: the next flight starts while this one is in the air
	# The group's job ends when its LAST card has landed, so decisions (which wait for the queue) see a settled stack.
	while group.any(func(c) -> bool: return is_instance_valid(c) and _trigger_flights.has(c)):
		await get_tree().process_frame

## One trigger card's flight in from its controller's edge of the screen. Ours uses the local Summon's flight from
## below the screen; the opponent's uses their Summon's flight from the top. The card stays in `_incoming_triggers`
## while it flies, which keeps layout, hover, arrows and shadows off it, exactly as for a flying Summon.
func _present_trigger_entry(card: Card) -> void:
	# Resolved (or cancelled) before its turn came: nothing to show.
	if not is_instance_valid(card) or card.get_parent() != self or not layout_cards().has(card):
		_forget_trigger(card)
		update_card_positions()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		card.visible = true
		_forget_trigger(card)
		update_card_positions()
		return
	# A SOURCE ON THE FIELD: the ability comes out of the card that triggered it. Anything else (a card that just went
	# to the Break Zone, an EX BURST from the Damage Zone) still enters from its controller's edge of the screen.
	var from: Vector3 = _source_point(card.effect_source)
	if from != Vector3.INF:
		card.visible = true
		trigger_flight_started.emit(card)
		await _fly_from_source(card, from)
		_forget_trigger(card)
		update_card_positions()
		return
	var ours: bool = card.controller == Card.PLAYER
	var size := get_viewport().get_visible_rect().size
	var pixel := size * Vector2(0.5, 1.05 if ours else -0.05)
	var plane := Plane(Vector3.UP, global_position.y - 0.35)
	var hit = plane.intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
	var launch: Vector3 = hit if hit != null else camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * 6.0
	card.visible = true
	trigger_flight_started.emit(card)
	# shared = false: several trigger flights are in the air at once, so none may kill the Summon flight slot.
	if ours:
		await _fly_local_summon_translation(card, launch, false)
	else:
		var start := card.global_transform
		start.origin = launch
		await _fly_opponent_summon(card, start, null, false)
	_forget_trigger(card)
	update_card_positions()

## Where an effect of `source` comes out of: the centre of its face, while it is drawn on the field; Vector3.INF when it
## is not (in hand, in a pile, already gone). Untyped: the source of a waiting effect may have been freed.
func _source_point(source) -> Vector3:
	if source == null or not is_instance_valid(source) or not (source is Card):
		return Vector3.INF
	var card: Card = source
	if not card.is_drawn_on_field() or not card.is_visible_in_tree():
		return Vector3.INF
	return card.get_global_face_centre()

## Is `source` the LOCAL human's card? Only they see their own ability while it is still being paid for.
func _is_local_play(source: Card) -> bool:
	if source == null or not is_instance_valid(source) or source.controller != Card.PLAYER or game == null:
		return false
	var agent = game.agent_for(1)
	return agent != null and agent.is_human()

## Take `card` off the in-flight list (and any freed entry with it). Untyped for the same reason as _forget_trigger.
func _drop_incoming(card) -> void:
	for i in range(_incoming_triggers.size() - 1, -1, -1):
		if not is_instance_valid(_incoming_triggers[i]) or _incoming_triggers[i] == card:
			_incoming_triggers.remove_at(i)

## A COMMITTED ABILITY LEAVES ITS SOURCE, in beats: the raised source SETTLES back into its slot, BLINKS (the ordinary
## flash every trigger gets) and settles again, turns DULL if the 《Dull》 was part of the cost (the rules dulled it at
## commit; Card.present_tap()), and after `blink_to_flight_seconds` its card flies out to the stack. An opponent's
## source was never raised, so it only blinks and dulls. A source no longer on the field (a cost returned or
## sacrificed it) skips all that; the card still leaves where the source was.
func _present_activation_entry(card, from: Vector3, source) -> void:   # untyped: either may be gone by now
	if not (source is Card and is_instance_valid(source)):
		await _present_source_entry(card, from)
		return
	var src: Card = source
	if _source_point(src) == Vector3.INF:
		src.activation_fx.normalize()
		src.present_tap()
		await _present_source_entry(card, from)
		return
	if src.activation_fx.lift_amount() > 0.0:
		src.activation_fx.lower()
		await src.activation_fx.wait_idle()
	await src.activation_fx.flash(blink_hold_seconds)
	await src.activation_fx.wait_idle()
	if not is_instance_valid(src):
		await _present_source_entry(card, from)
		return
	src.present_tap()
	await PRESENTATION.wait(get_tree().create_timer(blink_to_flight_seconds))
	await _present_source_entry(card, _source_point(src) if is_instance_valid(src) else from)

## Blink every distinct field source in `group` ONCE, together, and return once the blink is OVER and
## `blink_to_flight_seconds` have passed - the same beat as a committed ability (_present_activation_entry): several
## triggers of one card (Gadot) share one blink, and several cards triggering off the same event blink at the same time.
func _flash_trigger_sources(group: Array[Card]) -> void:
	var sources: Array[Card] = []
	for card in group:
		var source = card.effect_source if is_instance_valid(card) else null
		if source is Card and is_instance_valid(source) and not sources.has(source) and _source_point(source) != Vector3.INF:
			sources.append(source)
	if sources.is_empty() or PRESENTATION.fast_mode:
		return
	for source in sources:
		source.activation_fx.flash(blink_hold_seconds)   # not awaited: they blink together
	for source in sources:
		if is_instance_valid(source):
			await source.activation_fx.wait_idle()
	await PRESENTATION.wait(get_tree().create_timer(blink_to_flight_seconds))

## An ability's card comes out of its source `from` (see _fly_from_source) and settles into the fan. With no source on
## the field, in fast mode or without a camera it simply appears in its slot.
func _present_source_entry(card, from: Vector3) -> void:   # untyped: a queued entry may outlive its card
	if not is_instance_valid(card) or card.get_parent() != self:
		_drop_incoming(card)
		return
	if from == Vector3.INF or PRESENTATION.fast_mode or get_viewport().get_camera_3d() == null:
		card.visible = true
		_drop_incoming(card)
		update_card_positions()
		return
	if not _incoming_triggers.has(card):
		_incoming_triggers.append(card)
	card.visible = true
	await _fly_from_source(card, from)
	_drop_incoming(card)
	if is_instance_valid(card):
		update_card_positions()

## THE EFFECT LEAVES ITS SOURCE. The card appears `source_flight_lift` in front of `from` at `source_flight_start_scale`
## of its stack size, upright and facing the camera, and travels to its slot in the fan while turning into the stack
## pose and growing to full size, all on one eased progress. The slot is re-read every frame, so a fan that reflows
## mid-flight is followed. Near the end the card is kept above the settled cards so it lands on top, not through them.
func _fly_from_source(card: Card, from: Vector3) -> void:
	card.stop_stack_layout()
	card.set_revealed(true)
	var camera := get_viewport().get_camera_3d()
	var full: float = Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE
	var small: float = full * source_flight_start_scale
	var launch: Vector3 = from + (camera.global_position - from).normalized() * source_flight_lift
	# Held in an array: a lambda captures locals by value, and the last slot seen must survive between frames.
	var destination: Array = [to_global(calculate_card_position(card.index))]
	var sample := func(p: float) -> void:
		if not is_instance_valid(card) or card.get_parent() != self:
			return
		# Resolved while flying: keep heading for the last slot it had.
		if layout_cards().has(card):
			destination[0] = to_global(calculate_card_position(card.index))
		var t: float = 1.0 - pow(1.0 - p, 3.0)
		var axes := camera.global_basis.orthonormalized()
		var facing := global_basis.orthonormalized().inverse() * Basis(axes.x, axes.z, -axes.y)
		var turn := facing.get_rotation_quaternion().slerp(_stack_card_local_basis(card).get_rotation_quaternion(), t)
		card.basis = Basis(turn).scaled(Vector3.ONE * lerpf(small, full, t))
		var straight: Vector3 = launch.lerp(destination[0], t)
		card.global_position = straight
		if p >= 1.0:
			card.global_position = destination[0]
			return
		# Clear the settled fan only on the approach: measured from the field, the whole stack is "above" the card,
		# and clearing from the start would lift it off its source.
		_clear_local_flight_from_stack(card, camera)
		card.global_position = straight.lerp(card.global_position, smoothstep(0.25, 0.85, t))
	sample.call(0.0)
	# THE START POSE IS DRAWN FOR ONE FRAME before the flight moves. A tween created from a timer or a process_frame
	# resume is stepped in that same frame (tweens are processed after both), so the card would first be seen a frame
	# into its flight, ~20 px off its source and already growing.
	await get_tree().process_frame
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	var flight := create_tween()
	_end_flight_with_card(card, flight)
	flight.tween_method(sample, 0.0, 1.0, source_flight_seconds)
	await flight.finished

## The trigger's entrance is over, however it ended. Freed cards are dropped too: erasing a freed object from a typed
## array is an engine error, so the lists are swept rather than erased by value.
func _forget_trigger(card) -> void:   # untyped: it is called with cards that may already be freed
	for list in [_incoming_triggers, _trigger_flights, _trigger_batch]:
		for i in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[i]) or list[i] == card:
				list.remove_at(i)
	if is_instance_valid(card):
		trigger_entered.emit(card)

## EX BURST, PRESENTATION ONLY. The burst's effect card was just put on the stack by execute_card_effect(); take it
## back OUT of `cards` (so the priority loop cannot see a stack object and nobody may respond) while keeping it laid
## out on the stack, so it can fly in like any triggered ability before it resolves. Returns the card, or null.
func stage_ex_burst(source: Card) -> Card:
	for i in range(cards.size() - 1, -1, -1):
		var card: Card = cards[i]
		if card != null and card.effect_source == source:
			cards.remove_at(i)
			ex_burst_card = card
			return card
	return null

## Wait for a triggered-ability card's entrance to finish. Capped, so a lost presentation can never stall a burst.
## Wait until nothing is entering the stack (cards_still_entering), at most `cap_seconds`.
func await_stack_settled(cap_seconds: float = 6.0) -> void:
	if PRESENTATION.fast_mode:
		return
	var waited := 0.0
	while cards_still_entering() and waited < cap_seconds:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if waited >= cap_seconds:
		push_warning("[Stack] resolving although something is still marked as entering the stack after %.1f s" % cap_seconds)

## IS ANYTHING STILL ON ITS WAY ONTO THE STACK? The local Summon's presentation (fade, then flight), the opponent's
## Summon flight, trigger cards still to fly in or flying, and an ability's card coming out of its source. Each of
## those clears its marker when the card has landed (or is dropped), so this is the "has the stack settled" question.
func cards_still_entering() -> bool:
	if _local_summon_presentation != null and is_instance_valid(_local_summon_presentation):
		return true
	if _opponent_summon_flight_card != null and is_instance_valid(_opponent_summon_flight_card):
		return true
	for list in [_incoming_triggers, _trigger_flights]:
		for c in list:
			if is_instance_valid(c):
				return true
	return false

func await_trigger_entry(card: Card, cap_seconds: float = 4.0) -> void:
	if PRESENTATION.fast_mode:
		return
	var waited := 0.0
	while is_instance_valid(card) and _trigger_flights.has(card) and waited < cap_seconds:
		await get_tree().process_frame
		waited += get_process_delta_time()

## The flight is over: the EX BURST card goes back on top of the stack to be resolved AT ONCE by the caller (in the
## same frame, so there is still no window in which anyone could respond).
func commit_ex_burst(card: Card) -> void:
	if ex_burst_card == card:
		ex_burst_card = null
	if is_instance_valid(card) and not cards.has(card):
		cards.append(card)
		card.index = cards.size() - 1

## A code-defined triggered ability. Its effect object is stateless; the stack copy carries the event name and a small
## event payload until Game resolves it through CardEffect.dispatch.
## ONE STACK OBJECT PER AUTO-ABILITY. `ability_index` is the ability's position in CardEffect.auto_abilities().
func enqueue_code_trigger(source: Card, event, data: Dictionary = {}, ability_index: int = -1) -> Card:
	var event_id := EVENTS.normalize(event)
	# THE FACE SAYS WHAT THE ABILITY DOES, not what triggered it. No match keeps the full printed text, loudly.
	var wording := ""
	var effect_obj = source.effect()
	if effect_obj != null and ability_index >= 0:
		wording = effect_obj.stack_text(source.text, ability_index)
		if wording.is_empty():
			push_warning("[Stack] %s (%d): no printed ability matches %s #%d; the stack face shows the full text"
				% [source.card_name, source.id, EVENTS.name_of(event_id), ability_index])
	var card: Card = create_card(source.id, source.controller, "__code_event", source, wording)
	card.effect_event = event_id
	card.effect_event_data = data.duplicate(true)
	card.effect_ability_index = ability_index
	card.effect_kind = "Ability"
	update_card_positions()
	return card

## Every auto-ability of `source` that this event triggers, each as its OWN stack object. `event_ctx` is given for
## board events, whose spec filters must accept it; the card's own events (enter, attack, break, ...) pass null and
## match on the event id alone. Returns the new stack cards in the order they were put on the stack.
##
## ORDER: the rules let the controller order simultaneous auto-abilities. Until that choice exists, the FIRST printed
## ability resolves first, so it is put on the stack LAST (on top). For Gadot that plays the Fire Forward before the
## +1000, which is what the text reads as and what the player would choose.
func enqueue_code_triggers(source: Card, event, data: Dictionary = {}, event_ctx = null) -> Array[Card]:
	var out: Array[Card] = []
	var effect_obj = source.effect() if source != null else null
	if effect_obj == null:
		return out
	var event_id := EVENTS.normalize(event)
	var indices: Array[int] = effect_obj.triggered_abilities(event_id, event_ctx, source)
	indices.reverse()
	var abilities: Array = effect_obj.auto_abilities()
	for index in indices:
		# NO LEGAL CHOICE, NO STACK OBJECT (rules 11.8.4 / 11.8.9). The rules put it on the stack and remove it at once
		# with no response window, which on screen is exactly "nothing happens"; no prompt, no empty resolution.
		var choice = abilities[index].choice
		if choice != null and field != null and not field.has_viable_target(choice, source, "Ability"):
			LOG.info("Stack", "%s: auto-ability %d has no legal target and is not put on the stack" % [source.card_name, index])
			continue
		var copy: Card = enqueue_code_trigger(source, event_id, data, index)
		out.append(copy)
		if choice != null:
			_owed_trigger_choices.append(copy)
	return out


## DECLARE THE CHOICES of every triggered ability put on the stack since priority was last given (11.8.7, 11.11.2):
## the TURN player's first, then the other player's, each in the order they went on the stack. Each waits for its card
## to land, so the arrow is drawn from the stack card, then its controller chooses; the picks are stored on the card,
## which then shows them like a Summon's. With no legal target left by now the ability is removed at once (11.8.4).
## Re-entrant calls (a choice that triggers something) are absorbed: the running loop picks the new ones up.
func declare_trigger_choices() -> void:
	if _declaring_trigger_choices:
		return
	_declaring_trigger_choices = true
	while true:
		var card = _next_owed_choice()
		if card == null:
			break
		await _declare_trigger_choice(card)
	_declaring_trigger_choices = false


## The next copy to declare: still on the stack, turn player's before the other player's, oldest first.
func _next_owed_choice():
	for i in range(_owed_trigger_choices.size() - 1, -1, -1):
		var owed = _owed_trigger_choices[i]
		if not is_instance_valid(owed) or not cards.has(owed):
			_owed_trigger_choices.remove_at(i)
	if _owed_trigger_choices.is_empty():
		return null
	var turn_controller: String = game.controller_for(game.turn_owner) if game != null else Card.PLAYER
	for owed in _owed_trigger_choices:
		if owed.controller == turn_controller:
			_owed_trigger_choices.erase(owed)
			return owed
	return _owed_trigger_choices.pop_front()


func _declare_trigger_choice(card: Card) -> void:
	var source: Card = card.effect_source
	if source == null or not is_instance_valid(source) or source.effect() == null:
		return
	var abilities: Array = source.effect().auto_abilities()
	var index: int = card.effect_ability_index
	if index < 0 or index >= abilities.size() or abilities[index].choice == null:
		return
	await await_trigger_entry(card)
	if not is_instance_valid(card) or not cards.has(card):
		return
	var ctx = source.make_effect_context(card.effect_event, card.effect_event_data, card, [])
	var picks: Array = await ctx.choose_targets(abilities[index].choice)
	if not is_instance_valid(card) or not cards.has(card):
		return
	if picks.is_empty():
		# 11.8.4: nothing it could choose any more, so it is removed from the stack at once and nobody can respond.
		LOG.info("Stack", "%s: no legal target as its ability is put on the stack; removed (11.8.4)" % source.card_name)
		cards.erase(card)
		_forget_trigger(card)
		card.queue_free()
		update_card_positions()
		return
	card.set_effect_targets(picks)
	card.trigger_targets_declared = true
	LOG.info("Stack", "%s's ability targets %s" % [source.card_name, str(picks.map(func(c): return c.card_name))])
	# Shows the new arrow if this card is the one on display.
	refresh_target_display()


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
		# The card goes to the Break Zone NOW; on screen it stays on its spot, malfunctions and shatters (Vfx).
		Vfx.countered(card, func() -> void: pile.add_card(card))
	update_card_positions()

## THE RESOLUTION'S RHYTHM: after the resolve pulse, a beat before the effect runs; after the effect (and its
## animations) has finished, a beat before the next stack object. Presentation waits - fast mode skips them.
@export_group("Resolution")
@export var resolve_lead_seconds: float = 0.5
@export var resolve_trail_seconds: float = 0.5

func resolve_top_effect() -> void:
	# NOTHING RESOLVES WHILE A CARD IS STILL FLYING ONTO THE STACK. This used to assume every priority decision waited
	# for the presentation queue (Agent._settle), so a flight had always landed by then. It does not: the AI and mock
	# agents pass after their think time, and the React / Smart auto-pass after AUTO_PASS_DELAY, none of them waiting.
	# A Summon cast in React mode against a passing opponent resolved mid-flight. Wait here, at the one choke point,
	# whoever passed. Capped so a lost marker cannot hang the game; fast mode has no flights.
	await await_stack_settled()
	## Stack resolution: run effect instructions only; costs were applied at
	## commit for skills. The effect handler may await a modal (e.g. Auron's
	## "may play a Backup" choice), so resolution waits for the game to signal
	## resolution_complete before continuing.
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
	# THE CARD STAYS ON SCREEN WHILE IT RESOLVES. It is out of `cards` (the rules object is resolving, nobody gets
	# priority on it), but it keeps its slot until the effect has fully finished — target picks, "may" prompts and the
	# animations the handler awaits — and only then does the fan close the gap. Popping it from the layout here made a
	# Gadot leave the stack before the player had even chosen whether to play a Forward.
	resolving_card = card
	resolving_slot = cards.size()
	if card == skill_activation_proxy:
		skill_activation_proxy = null
		skill_mana_deferred_until_target_confirm = false
	LOG.info("Stack", str("resolve ", card.card_name))
	# ANNOUNCE IT, THEN GIVE IT ROOM. The card pulses (it grows, its aura flares, a rectangle launches from its outline
	# and fades with distance) and settles back; then a beat before the effect runs. These are presentation waits
	# (PRESENTATION.wait), so fast mode / AI simulation runs straight through. The card is still on the stack for all
	# of it, because nothing has resolved yet.
	refresh_top_aura()
	await _present_resolve_lead(card)
	resolution_pending = true
	execute_card_effect.emit(card)
	if resolution_pending:
		await resolution_complete
	resolution_pending = false
	if resolving_card == card:
		resolving_card = null
	# CLOSE THE GAP. A card leaving the stack is the same event as a card leaving the hand: the remaining fan has to
	# reflow, or every resolved effect leaves a hole where its card used to be. It also refreshes the hover/review link
	# (update_card_positions ends with refresh_target_display).
	update_card_positions()
	if len(cards) == 0:
		# The stack is done, so any "the opponent chose this" reveal is spent. Clearing it
		# here — rather than never — is what stops the red ring from outliving the effect.
		field.clear_targeted_highlights()
		GlobalVariables.refresh_mode()
	# The beat AFTER the effect is taken by Game before the card is disposed of (hold_resolved_card), so the card is
	# still on the stack while its animations finish; nothing more to wait for here.

	


## THE CARD WATCHES ITS EFFECT LAND, THEN LEAVES. Called by Game after an effect's handler returns and its targeting
## session is cleared, but BEFORE the card is freed or sent to the Break Zone: wait for the effect's animations (the
## Vfx queue: strikes, bursts, tributes...), then `resolve_trail_seconds`. Presentation only - fast mode skips it.
func hold_resolved_card() -> void:
	await PRESENTATION.wait_for_queue()
	await PRESENTATION.wait(get_tree().create_timer(resolve_trail_seconds))

## The resolve pulse and the pause after it. Presentation only: in fast mode the pulse still plays but nothing waits.
func _present_resolve_lead(card: Card) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	if PRESENTATION.fast_mode:
		card.stack_aura.pulse()
		return
	await card.stack_aura.pulse()
	await PRESENTATION.wait(get_tree().create_timer(resolve_lead_seconds))

## THE TOP OF THE STACK WEARS THE AURA: the card resolving now, or else the one that will resolve next. Called from
## update_card_positions() (every stack change ends there) and when a resolution starts.
func refresh_top_aura() -> void:
	var top: Card = resolving_card if is_instance_valid(resolving_card) else null
	if top == null:
		# The top that can be SEEN: an opponent's ability still being paid for is not on display yet.
		for i in range(cards.size() - 1, -1, -1):
			if not _hidden_activations.has(cards[i]):
				top = cards[i]
				break
	for c in layout_cards():
		if is_instance_valid(c):
			c.stack_aura.set_top(c == top)

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
		# THE AIMING ARROWS ARE DONE: the cast succeeded, and the stack shows its arrows once the card has landed.
		field._clear_target_arrows()
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
	# Same for an ability: committed, so its aiming arrows go; the stack shows its arrows from here.
	field._clear_target_arrows()
	_shatter_paid_cost()          # activation committed: costs paid, target chosen
	# Same as the no-target path below: clear the button that got us here, then put the player's pass button back. Hiding the
	# rack alone leaves the parked priority round with nothing to be answered by.
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	request_priority.emit()

## The damage pool for an ability that says "divide N damage among them" (AbilitySpec.divide_total), or -1.
func _divide_damage_total(proxy: Card) -> int:
	if proxy == null:
		return -1
	if proxy.ability_spec != null and proxy.ability_spec.divide_total > 0:
		return proxy.ability_spec.divide_total
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
		# tapped, and the summon stays in its hand without entering the stack.
		var cancelled: Card = summon_casting_card
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		cancelled.set_cast_pending_highlight(false)
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
