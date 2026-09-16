extends Node3D
class_name Assistant

@onready var stack: Stack = get_parent().get_node("Stack")
@onready var hand: Hand = get_parent().get_node("Player/Hand")
# The three match buttons hang off ButtonRack, which owns their SHARED position; each button carries
# only its own slot offset. So moving all three is one transform on the rack, and Confirm and PassPhase
# share a slot by construction rather than by two numbers happening to agree. These paths go through
# ButtonRack for that reason — the buttons are no longer direct children of Assistant.
@onready var buttonRack: Node3D = $ButtonRack
@onready var confirmButton: BigButton = $ButtonRack/ConfirmButton
@onready var cancelButton: BigButton = $ButtonRack/CancelButton
@onready var passPhaseButton: BigButton = $ButtonRack/PassPhaseButton

# The "Pay ..." crystal cost readout. Built in code rather than added to game.tscn so the whole payment
# UI stays owned by one node.
const COST_READOUT := preload("res://crystal_cost.tscn")
## Where the readout sits relative to the player's hand, in WORLD terms — so the hand's own 180-degree
## frame is irrelevant. +z is up the screen (the hand sits at the bottom, nearest the camera) and +y
## lifts it clear of the cards. Screen-up is 0.985 of +z and 0.174 of +y at this camera angle, so z does
## nearly all the work; measured against a shot, this lands it just above the hand's cards.
@export var cost_readout_offset: Vector3 = Vector3(0.0, 0.25, 0.55)
## Icon size in metres, matched to the SOURCE ART: the icons in references/icons.png are about 26 px across,
## and at this camera's 187 px per metre that is 0.14 m — so they are drawn at roughly their native pixel
## size rather than upscaled, which is what made the earlier 0.40 m version read as oversized. The label is
## sized from this as well (see the setter) so the word can never end up bigger than the icons it
## introduces. Sized with a setter so changing one number keeps the two in proportion.
@export var cost_readout_badge_size_m: float = 0.14:
	set(value):
		cost_readout_badge_size_m = value
		if cost_readout == null:
			return
		cost_readout.badge_size_m = value
		cost_readout.label_height_m = value * 0.72
var cost_readout: CrystalCost = null

const MANA_ZERO : Dictionary = {
		'火': 0, '風': 0, '土': 0, '水': 0, 
		'雷': 0, '闇': 0, '光': 0, '氷': 0, 
		'neutral': 0
	}

signal charge_complete
signal charge_cancelled
signal target_complete
signal target_cancel
signal pressed_pass_priority
signal pressed_next_phase
signal advance_blocker_declaration_step
signal advance_attack_declaration_step
signal choose_card_play
signal choose_card_decline
## Emitted when the choose-card modal closes, with the player's decision.
signal choose_card_finished(play: bool)

var mana_acc : Dictionary = MANA_ZERO.duplicate()
var mana_cost : Dictionary = MANA_ZERO.duplicate()
var onConfirm: Callable
var onCancel: Callable
var confirm_text := "Confirm"
var cancel_text := "Cancel"

func _ready():
	passPhaseButton.set_text('Next Phase')
	passPhaseButton.set_on_press_callback(func(): _pass_priority())
	GlobalVariables.player_mode_change.connect(_on_player_mode_change)
	# The choose-card "Play" button enables as soon as a legal hand card is selected.
	hand.effect_card_selection_changed.connect(func(has_selection: bool): set_play_card_enabled(has_selection))
	cost_readout = COST_READOUT.instantiate()
	cost_readout.badge_size_m = cost_readout_badge_size_m
	add_child(cost_readout)
	cost_readout.visible = false

## Keeps the readout above the hand while it is up. It faces the camera by itself; this only places it,
## and only while visible, so there is no cost when no payment is happening.
func _process(_delta: float) -> void:
	if cost_readout == null or not cost_readout.visible:
		return
	cost_readout.global_position = hand.global_position + cost_readout_offset

# ------------------------------------------------------------------
# Unified modal API. All flows configure the two main buttons through
# this so visibility + input + callbacks stay in sync.
# ------------------------------------------------------------------
func show_modal(p_confirm_text: String, p_cancel_text: String = "", p_on_confirm: Callable = Callable(), p_on_cancel: Callable = Callable(), confirm_enabled: bool = true, show_cancel: bool = true) -> void:
	passPhaseButton.hide_button()
	if p_confirm_text.is_empty():
		confirmButton.hide_button()
	else:
		confirmButton.configure(p_confirm_text, p_on_confirm, confirm_enabled)
		confirmButton.show_button()
	if show_cancel and not p_cancel_text.is_empty():
		cancelButton.configure(p_cancel_text, p_on_cancel)
		cancelButton.show_button()
	else:
		cancelButton.hide_button()

func hide_buttons():
	confirmButton.hide_button()
	cancelButton.hide_button()

func show_choose_card_buttons(p_confirm_text: String = "Play card", p_cancel_text: String = "Don't play card"):
	show_modal(p_confirm_text, p_cancel_text,
		func():
			choose_card_play.emit()
			choose_card_finished.emit(true),
		func():
			choose_card_decline.emit()
			choose_card_finished.emit(false),
		false, true)

func set_play_card_enabled(enabled: bool):
	confirmButton.set_disabled(not enabled)

func set_declare_attack_button(button_text: String):
	show_modal(button_text, "",
		func():
			advance_attack_declaration_step.emit()
			confirmButton.hide_button(),
		Callable(), true, false)

func set_declare_block_button(button_text: String):
	show_modal(button_text, "",
		func():
			advance_blocker_declaration_step.emit()
			confirmButton.hide_button(),
		Callable(), true, false)

func generate_confirm_button(on_confirm: Callable) -> void:
	show_modal("Confirm", "",
		func():
			on_confirm.call()
			confirmButton.hide_button(),
		Callable(), true, false)

## Cancel is available as soon as targeting starts (not only after a target is chosen).
func prepare_targeting_phase_cancel():
	show_modal("", "Cancel", Callable(), func(): on_target_cancel(), true, true)

# ------------------------------------------------------------------
# Legacy two-button API used by the game-level targeting flow.
# ------------------------------------------------------------------
func set_confirm_button(on_confirm: Callable) -> void:
	onConfirm = on_confirm

func set_cancel_button(on_cancel: Callable) -> void:
	onCancel = on_cancel

func set_confirm_text(text):
	confirm_text = text

func set_cancel_text(text):
	cancel_text = text

func show_buttons():
	show_modal(confirm_text, cancel_text,
		func():
			if onConfirm.is_valid():
				onConfirm.call()
			hide_buttons(),
		func():
			if onCancel.is_valid():
				onCancel.call()
			hide_buttons())

func hide_confirm_button():
	confirmButton.hide_button()

# ------------------------------------------------------------------
# Priority / pass button
# ------------------------------------------------------------------
func show_pass_priority_button():
	# Only show the pass button when players actually hold priority. It must
	# stay hidden during modal flows (targeting, choose-card, paying cost).
	# ATTACKING is allowed because the attack declaration step runs a priority
	# window right after the attack button is pressed.
	var pm = GlobalVariables.get_player_mode()
	var modal_mode: bool = (
		pm == GlobalVariables.Player_Mode.PAYING_COST
		or pm == GlobalVariables.Player_Mode.TARGET
		or pm == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND
		or pm == GlobalVariables.Player_Mode.NO_PRIORITY
	)
	if modal_mode:
		passPhaseButton.hide_button()
	else:
		passPhaseButton.show_button()

func _pass_priority():
	passPhaseButton.hide_button()
	pressed_pass_priority.emit()

func _on_player_mode_change(pm: GlobalVariables.Player_Mode):
	if pm == GlobalVariables.Player_Mode.FREE or pm == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		passPhaseButton.show_button()
	else:
		passPhaseButton.hide_button()
	# The cost readout belongs to the payment modal alone: no crystals are being chosen during
	# targeting, and nothing is owed outside a payment. Driving it off the MODE means every exit —
	# confirm, cancel, or anything that pops the modal — takes it down without extra bookkeeping.
	if pm == GlobalVariables.Player_Mode.PAYING_COST:
		_show_cost_readout()
	else:
		_hide_cost_readout()

# ------------------------------------------------------------------
# Crystal cost readout
# ------------------------------------------------------------------
func _show_cost_readout() -> void:
	if cost_readout == null:
		return
	_refresh_cost_readout()
	cost_readout.visible = true

func _hide_cost_readout() -> void:
	if cost_readout != null:
		cost_readout.visible = false

## Rebuilds the row from what is STILL owed. Called whenever the amount selected changes, so the row
## shrinks as crystals are chosen rather than sitting there showing the full cost.
func _refresh_cost_readout() -> void:
	if cost_readout == null:
		return
	cost_readout.cost = remaining_cost()

# ------------------------------------------------------------------
# Payment flow
# ------------------------------------------------------------------
func charge(amount: int, type: String):
	mana_acc[type] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)
	_refresh_cost_readout()

func discharge(amount: int, type: String):
	mana_acc[type] -= amount
	if not can_pay_cost():
		confirmButton.set_disabled(true)
	_refresh_cost_readout()

func reset_buttons():
	mana_acc = MANA_ZERO.duplicate()
	mana_cost = MANA_ZERO.duplicate()
	hide_buttons()

func clear_payment_accumulator():
	mana_acc = MANA_ZERO.duplicate()

func on_charge_complete():
	# Payment finished: closing the modal reveals the phase's base mode again.
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.PAYING_COST)
	reset_buttons()
	charge_complete.emit()

func on_charge_cancelled():
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.PAYING_COST)
	reset_buttons()
	charge_cancelled.emit()

func on_target_complete():
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.TARGET)
	reset_buttons()
	target_complete.emit()

func on_target_cancel():
	target_cancel.emit()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.TARGET)
	reset_buttons()

func _on_hand_charge_start(card: Card) -> void:
	mana_cost = card.get_cost()
	show_modal("Confirm", "Cancel",
		func(): on_charge_complete(),
		func(): on_charge_cancelled(),
		false, true)
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)
	_refresh_cost_readout()

func _on_field_card_activated_ability(cost: Dictionary) -> void:
	mana_cost = cost
	show_modal("Confirm", "Cancel",
		func(): on_charge_complete(),
		func(): on_charge_cancelled(),
		can_pay_cost(), true)
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)
	_refresh_cost_readout()

func _on_hand_selected_cards_for_mana_has_changed(amount: int, element: String) -> void:
	mana_acc[element] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)
	_refresh_cost_readout()

func _on_field_selected_cards_for_mana_has_changed(amount: int, element: String) -> void:
	mana_acc[element] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)
	_refresh_cost_readout()

# ------------------------------------------------------------------
# Targeting confirmation
# ------------------------------------------------------------------
func _on_field_request_target_confirmation(_target_card: Card, allow_cancel: bool = false) -> void:
	show_modal("Confirm", "Cancel" if allow_cancel else "",
		func(): on_target_complete(),
		func(): on_target_cancel(),
		true, allow_cancel)

# ------------------------------------------------------------------
# Mana payment checking
# ------------------------------------------------------------------

## What is STILL owed, given the crystals chosen so far. Elemental requirements are met first and
## whatever is left over then pays the neutral part — the same order, and therefore the same answer,
## as the payment check below. Keys come back exactly as they went in (an element may be spelled "火"
## or ["火"] depending on where the cost came from), and crystal_cost.tscn accepts both.
func remaining_cost() -> Dictionary:
	var left: Dictionary = {}
	var pool: Dictionary = mana_acc.duplicate()
	for element in mana_cost:
		if element == "neutral":
			continue
		var need: int = int(mana_cost[element])
		var have: int = int(pool.get(element, 0))
		pool[element] = maxi(0, have - need)
		if need > have:
			left[element] = need - have
	var neutral: int = int(mana_cost.get("neutral", 0))
	var spare: int = 0
	for element in pool:
		if element != "neutral":
			spare += int(pool[element])
	if neutral > spare:
		left["neutral"] = neutral - spare
	return left

func can_pay_cost() -> bool:
	# ONE definition of "can pay": nothing is still owed. This used to be the element-then-neutral
	# arithmetic written out a second time, which meant the readout and the Confirm button could in
	# principle disagree about the same selection.
	return remaining_cost().is_empty()
