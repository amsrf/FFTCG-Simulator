extends Node3D
@onready var player_graveyard: Node = $Graveyard
@onready var opponent_graveyard: Node = $OpponentGraveyard

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func add_card(card:Card):
	if(card.controller == 'player'):
		player_graveyard.add_card(card)
	else:
		opponent_graveyard.add_card(card)		
