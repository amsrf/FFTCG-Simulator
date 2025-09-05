extends Node3D
class_name Assistant


@onready var stack: Stack = get_parent().get_node("Stack")
@onready var hand: Hand = get_parent().get_node("Hand")

signal charge_complete
signal process_next_instruction
var charge_cost: ManaCost
var charging : ManaCost  = ManaCost.new()
var target_locked = false
var charge_follow_up_state


func set_charging(cost: ManaCost):
	charge_cost = cost
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
	
func toggle_lock_target():
	target_locked =  not target_locked
	var diff: ManaCost = charging.sub(charge_cost)
	print('amanda', diff.is_fully_paid())
	if(target_locked and diff.is_fully_paid()):
		$BigButton.visible = true
		$BigButton.set_on_press_callback(
			func():  # Lambda function
				lock_and_loaded()
		)

func generate_confirm_button(on_confirm: Callable) -> void:
	$BigButton.visible = true
	$BigButton.set_on_press_callback(
		func():
			on_confirm.call()
			$BigButton.visible = false  # Optional: hide after press
	)
	
func hide_confirm_button():
	$BigButton.visible = false

func charge(amount: int, type: String):
	var mana = ManaCost.new()
	print(amount,type,'ajajajaaj')
	if mana.cost.has(type):
		mana.cost[type] = amount
	else:
		push_error("Invalid mana type: '%s'. Valid types are: %s" % [
			type, 
			mana.cost.keys()
	])
	charging = charging.add(mana)
	print('charge ', mana,charging, charging.contains(charge_cost))
	if(charging.contains(charge_cost)):
		if(charge_follow_up_state):
			GlobalVariables.set_player_mode(charge_follow_up_state)
		else:
			$BigButton.visible = true
			$BigButton.set_on_press_callback(
				func():  # Lambda function
					lock_and_loaded()
		)
func lock_and_loaded():  # Lambda function
	charging = ManaCost.new()
	charge_cost = ManaCost.new()
	$BigButton.visible = false
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	emit_signal("charge_complete")
	
func discharge(mana):
	charging -= mana
	if( not charging.engulfs(charge_cost)):
		$BigButton.visible = false
		
func _on_hand_charge_start(card: Variant) -> void:
	charge_cost = card.cost
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.PAYING_COST)
