extends Node3D

class_name Card

@export var id: int = 0  # Make this editable in the Inspector
# Scale factor when hovered
# Original scale of the card
var original_scale: Vector3
var code: String
var power: int
var cost: int

func initialize(card_id: int):
	id = card_id
	load_card_data()
	assign_card_texture()
	
func load_card_data():
	var card_data = CardDatabase.card_database[id]

	if card_data:
		name = card_data.get("name_en", "Unknown")
		power = int(card_data.get("power", 0))
		cost = int(card_data.get("cost", 0))
		code = card_data.get("code", "Unknown")
		print("Card Loaded: ", name, " | Damage: ", power, " | Mana Cost: ", cost)
	else:
		print("Card with ID '%s' not found in database." % id)
		
func assign_card_texture():
	
	var texture_path = "res://assets/cards/%s.jpg" % code
	var texture = load(texture_path)
	if texture:
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		if has_node("MeshInstance3D"):  # Check if the node exists
			$MeshInstance3D.set_surface_override_material(0, material)
		else:
			print("No MeshInstance3D for card class.")
	else:
		print("Failed to load texture for card: ", code)
		


func _on_card_area_3d_mouse_entered():
	var tween = create_tween()
	#tween.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.2)


func _on_card_area_3d_mouse_exited():
	var tween = create_tween()  # Stop any ongoing tweens
	#tween.tween_property(self, "scale", Vector3(1,1,1), 0.2)
