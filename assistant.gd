extends Node3D
class_name Assistant

@onready var stack: Stack = get_parent().get_node("Stack")
@onready var hand: Hand = get_parent().get_node("Player/Hand")
@onready var confirmButton: BigButton = $ConfirmButton
@onready var cancelButton: BigButton = $CancelButton
@onready var passPhaseButton: BigButton = $PassPhaseButton

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

# ------------------------------------------------------------------
# Payment flow
# ------------------------------------------------------------------
func charge(amount: int, type: String):
	mana_acc[type] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)

func discharge(amount: int, type: String):
	mana_acc[type] -= amount
	if not can_pay_cost():
		confirmButton.set_disabled(true)

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

func _on_field_card_activated_ability(cost: Dictionary) -> void:
	mana_cost = cost
	show_modal("Confirm", "Cancel",
		func(): on_charge_complete(),
		func(): on_charge_cancelled(),
		can_pay_cost(), true)
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)

func _on_hand_selected_cards_for_mana_has_changed(amount: int, element: String) -> void:
	mana_acc[element] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)

func _on_field_selected_cards_for_mana_has_changed(amount: int, element: String) -> void:
	mana_acc[element] += amount
	if can_pay_cost():
		confirmButton.set_disabled(false)

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
func can_pay_cost() -> bool:
	# Create a copy of accumulated mana to track usage
	var remaining_mana = mana_acc.duplicate()

	# First, pay for specific elemental requirements
	for element in mana_cost:
		if element == "neutral":
			continue  # Handle neutral separately

		# Get cost and available mana
		var cost = mana_cost[element]
		var available = remaining_mana.get(element, 0)

		# Check if we have enough of this specific element
		if available < cost:
			return false

		# Deduct the mana used
		remaining_mana[element] = available - cost

	# Calculate neutral cost
	var neutral_cost = mana_cost.get("neutral", 0)
	if neutral_cost == 0:
		return true  # No neutral cost to pay

	# Calculate total remaining elemental mana (excluding neutral)
	var total_available_for_neutral = 0
	for element in remaining_mana:
		if element != "neutral":
			total_available_for_neutral += remaining_mana[element]

	# Check if we have enough for neutral costs
	return total_available_for_neutral >= neutral_cost
