extends Node3D

# In your main script or in _ready() of your Node3D
func _ready():
	# Create quad for text display
	var text_quad = $TextDisplay
 
	# Create material using SubViewport's texture
	var text_material = StandardMaterial3D.new()
	text_material.albedo_texture = $ButtonTextViewport.get_texture()
	text_material.flags_unshaded = true
	text_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	$ButtonTextViewport.transparent_bg = true # 2K resolution
	text_quad.material_override = text_material

func set_on_press_callback(callback: Callable):
	$Area3D.set_on_press_callback(callback)
	
