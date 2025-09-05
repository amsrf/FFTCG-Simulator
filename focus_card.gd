extends Card

func _ready():
	GlobalVariables.focus_card.connect(_on_update)

func _on_update(value):
	visible = true
	initialize(value, 'player')
