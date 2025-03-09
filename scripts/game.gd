extends Node3D
@onready var deck = $Deck
@onready var hand = $Hand
func _ready():

	var card_scene = preload("res://Card.tscn")

	for i in range(5):
		var card = card_scene.instantiate()  
		card.initialize(i + 1)          
		hand.add_card(card)

	var deck_cards = []
	for i in range(50):
		var card = card_scene.instantiate()  
		card.initialize(i + 1)
		deck_cards.append(card)
	deck.add_cards(deck_cards)
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var focus_card = get_tree().get_nodes_in_group("focus_card")[0]
		focus_card.visible = false  # Hide the focus card
		print("Hide Focus")
		
func _input(event):
	# Check if the "D" key is pressed
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_D:
		var target_position = hand.position + Vector3(hand.last_card_position(),0,0)
		deck.draw_card(target_position, on_card_drawn)
		#var card = deck.get_children()[0]
		#hand.add_card(card)
		
func on_card_drawn(card):
	# Add the card to the hand after the animation finishes
	hand.add_card(card)
