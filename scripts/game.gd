extends Node3D

func _ready():
	var card_scene = preload("res://Card.tscn")  # Load the card scene
	var card = card_scene.instantiate()          # Instantiate the scene
	card.initialize(33)                          # Initialize the card with ID 6
	add_child(card)                           # Add the card to the scene
