extends MeshInstance3D

var hand_center = GlobalVariables.get_hand_center();

func _on_card_area_3d_mouse_entered():
	if( not get_parent().get_parent() is Hand ):
		return
	if(get_parent().is_dragging):
		return
	scale = Vector3(1.5,1.5,1.5)
	position.y += 0.1
	position.z =  -get_parent().position.z - 0.4
	rotation = -get_parent().rotation


func _on_card_area_3d_mouse_exited() -> void:
	reset()


func _on_card_area_3d_card_grabbed(_card: Variant) -> void:
	reset()


func reset():
	scale = Vector3(1,1,1)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
