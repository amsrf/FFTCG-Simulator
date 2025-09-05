extends SubViewport

func _ready():
	# Configure the SubViewport
	$SubViewport.size = Vector2(512, 512) # Match this to your mesh proportions
	
	# Configure CanvasLayer (critical for 3D)
	$SubViewport/CanvasLayer.layer = 1
	
	# Configure Control
	var control = $SubViewport/CanvasLayer/Control
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	
	# Configure Label
	var label = $SubViewport/CanvasLayer/Control/Label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.text = "Button Text"
	
	# Set up material
	var quad = $MeshInstance3D
	var material = StandardMaterial3D.new()
	material.albedo_texture = $SubViewport.get_texture()
	material.flags_unshaded = true
	material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	quad.material_override = material
