extends Node3D
class_name Assistant


@onready var stack: Stack = get_parent().get_node("Stack")
@onready var hand: Hand = get_parent().get_node("Hand")
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
signal advance_attack_declaration_step

var mana_acc : Dictionary = MANA_ZERO.duplicate()
var mana_cost : Dictionary = MANA_ZERO.duplicate()
var target_locked = false
var charge_follow_up_state
var onConfirm
var onCancel

func _ready():
	passPhaseButton.set_text('Next Phase')
	passPhaseButton.set_on_press_callback(func():_pass_priority())
	GlobalVariables.player_mode_change.connect(_on_player_mode_change)
	pass
	
func set_declare_attack_button(button_text:String):
	confirmButton.visible = true
	confirmButton.set_text(button_text)
	confirmButton.set_on_press_callback(func():
		advance_attack_declaration_step.emit()
		confirmButton.visible = false
	)
func _on_player_mode_change(pm:GlobalVariables.Player_Mode):
	if(pm == GlobalVariables.Player_Mode.FREE or pm == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME):
		passPhaseButton.visible = true
	else:
		passPhaseButton.visible = false
	pass
'''func toggle_lock_target():
	target_locked =  not target_locked
	var diff: ManaCost = charging.sub(charge_cost)
	if(target_locked and diff.is_fully_paid()):
		confirmButton.visible = true
		confirmButton.set_on_press_callback(
			func():  # Lambda function
				on_charge_complete()
		)'''

func generate_confirm_button(on_confirm: Callable) -> void:
	confirmButton.visible = true
	confirmButton.set_on_press_callback(
		func():
			on_confirm.call()
			confirmButton.visible = false  # Optional: hide after press
	)
	
func show_buttons():
	confirmButton.visible = true
	confirmButton.set_on_press_callback(
		func():
			onConfirm.call()
			hide_buttons()
			onConfirm = null  # Optional: hide after press
	)
	cancelButton.visible = true
	cancelButton.set_on_press_callback(
		func():
			onCancel.call()
			hide_buttons()  # Optional: hide after press
			onCancel = null
	)
	
func set_confirm_button(on_confirm: Callable) -> void:
	onConfirm = on_confirm
	
func set_cancel_button(on_cancel: Callable) -> void:
	onCancel = on_cancel

func set_confirm_text(text):
		confirmButton.set_text(text)
		
func set_cancel_text(text):
		cancelButton.set_text(text)
		
func hide_confirm_button():
	confirmButton.visible = false
	
func hide_buttons():
	confirmButton.visible = false
	cancelButton.visible = false
	
func charge(amount: int, type: String):
	mana_acc[type] += amount
	if(can_pay_cost()):
		confirmButton.visible = true
		
func reset_buttons():
	mana_acc  = MANA_ZERO.duplicate()
	mana_cost  = MANA_ZERO.duplicate()
	confirmButton.visible = false
	cancelButton.visible = false
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)

func clear_payment_accumulator():
	mana_acc = MANA_ZERO.duplicate()
	
func on_charge_complete():  # Lambda function
	reset_buttons()
	charge_complete.emit()
	
func on_charge_cancelled():  # Lambda function
	reset_buttons()
	charge_cancelled.emit()
	
func on_target_complete():
	reset_buttons()
	target_complete.emit()
	
func on_target_cancel():
	target_cancel.emit()
	reset_buttons()

## Cancel is available as soon as targeting starts (not only after a target is chosen).
func prepare_targeting_phase_cancel():
	passPhaseButton.visible = false
	confirmButton.visible = false
	cancelButton.visible = true
	cancelButton.set_text("Cancel")
	cancelButton.set_on_press_callback(func(): on_target_cancel())
	
func discharge(amount: int,type: String):
	mana_acc[type] -= amount
	if( not can_pay_cost()):
		confirmButton.visible = false
		

func show_pass_priority_button():
	passPhaseButton.visible = true

func _pass_priority():
	passPhaseButton.visible = false
	pressed_pass_priority.emit()
	
func show_confirm():
	confirmButton.visible = true
	passPhaseButton.visible = false
	
func show_cancel():
	cancelButton.visible = true
	passPhaseButton.visible = false


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
	
func _on_hand_charge_start(card: Card) -> void:
	mana_cost = card.get_cost()
	confirmButton.set_on_press_callback(func():on_charge_complete())
	cancelButton.set_on_press_callback(func():on_charge_cancelled())
	confirmButton.set_text("Confirm")
	cancelButton.set_text("Cancel")
	cancelButton.visible = true
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST) #perhaps only the assistant should make state changes


func _on_hand_selected_cards_for_mana_has_changed(amount:int, element:String) -> void:
	mana_acc[element] += amount
	if(can_pay_cost()):
		confirmButton.visible = true


func _on_field_selected_cards_for_mana_has_changed(amount:int, element:String) -> void:
	mana_acc[element] += amount
	if(can_pay_cost()):
		confirmButton.visible = true


func _on_field_request_target_confirmation(_target_card: Card, allow_cancel: bool = false) -> void:
	confirmButton.visible = true
	confirmButton.set_text("Confirm")
	confirmButton.set_on_press_callback(func(): on_target_complete())
	cancelButton.visible = allow_cancel
	if allow_cancel:
		cancelButton.set_text("Cancel")
		cancelButton.set_on_press_callback(func(): on_target_cancel())
	else:
		cancelButton.set_on_press_callback(func(): pass)


func _on_field_card_activated_ability(cost: Dictionary) -> void:
	mana_cost = cost
	confirmButton.set_on_press_callback(func():on_charge_complete())
	cancelButton.set_on_press_callback(func():on_charge_cancelled())
	confirmButton.set_text("Confirm")
	cancelButton.set_text("Cancel")
	cancelButton.visible = true
	if can_pay_cost():
		confirmButton.visible = true
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
