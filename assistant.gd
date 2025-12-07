extends Node3D
class_name Assistant


@onready var stack: Stack = get_parent().get_node("Stack")
@onready var hand: Hand = get_parent().get_node("Hand")
@onready var confirmButton: BigButton = $ConfirmButton
@onready var cancelButton: BigButton = $CancelButton

signal charge_complete
var charge_cost: ManaCost
var charging : ManaCost  = ManaCost.new()
var target_locked = false
var charge_follow_up_state
var onConfirm
var onCancel

var on_cost_payed;

func await_mana_pay(cost: ManaCost, on_cost_payed_temp):
	charge_cost = cost
	on_cost_payed = on_cost_payed_temp
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
	
	

func set_charging(cost: ManaCost):
	charge_cost = cost
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
	
func toggle_lock_target():
	target_locked =  not target_locked
	var diff: ManaCost = charging.sub(charge_cost)
	if(target_locked and diff.is_fully_paid()):
		confirmButton.visible = true
		confirmButton.set_on_press_callback(
			func():  # Lambda function
				on_charge_complete()
		)

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
	var mana = ManaCost.new()
	if mana.cost.has(type):
		mana.cost[type] = amount
	else:
		push_error("Invalid mana type: '%s'. Valid types are: %s" % [
			type, 
			mana.cost.keys()
	])
	charging = charging.add(mana)
	if(charging.contains(charge_cost)):
		if(charge_follow_up_state):
			GlobalVariables.set_player_mode(charge_follow_up_state)
		else:
			confirmButton.visible = true
			confirmButton.set_on_press_callback(
				func():  # Lambda function
					on_charge_complete()
		)
func on_charge_complete():  # Lambda function
	charging = ManaCost.new()
	charge_cost = ManaCost.new()
	confirmButton.visible = false
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	emit_signal("charge_complete")
	
func discharge(mana):
	charging -= mana
	if( not charging.engulfs(charge_cost)):
		confirmButton.visible = false
		
func _on_hand_charge_start(card: Variant) -> void:
	charge_cost = card.cost
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
