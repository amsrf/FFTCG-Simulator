extends SubViewport

func _ready():

	# Save the Viewport texture
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image = get_texture().get_image()
	image.flip_y() # Viewport textures are upside-down by default
	image.save_png("res://Font/confirm_text.png")
	print("Texture saved!")
