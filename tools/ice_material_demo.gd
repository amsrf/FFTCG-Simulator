extends Node3D
## Uses the production mesh/shader with local materials; no game settings are changed.
const PROJECTILE := preload("res://assets/effects/ice/ice_projectile.tscn")
var _ice: Node3D
var _material: ShaderMaterial
var _light: DirectionalLight3D
var _environment: Environment
var _sliders: Dictionary = {}
var _rotate := false

func _ready() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.025, 0.045, 0.08)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.7, 0.82, 1)
	_environment.ambient_light_energy = 0.35
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	var sky_shader := Shader.new()
	sky_shader.code = """shader_type sky;
void sky() {
 vec3 d = normalize(EYEDIR);
 vec3 base = mix(vec3(0.035,0.055,0.09),vec3(0.3,0.43,0.65),smoothstep(-0.3,0.8,d.y));
 float key = smoothstep(0.92,0.95,dot(normalize(d.xz),normalize(vec2(-0.6,0.8)))) * smoothstep(-0.25,-0.15,d.y) * (1.0-smoothstep(0.65,0.75,d.y));
 float rim = smoothstep(0.96,0.98,dot(normalize(d.xz),normalize(vec2(0.8,-0.3)))) * smoothstep(-0.1,0.1,d.y);
 COLOR = base + vec3(3.0)*key + vec3(0.9,1.5,2.0)*rim;
}"""
	sky_material.shader = sky_shader
	sky.sky_material = sky_material
	_environment.sky = sky
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)
	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-35,-40,0)
	_light.light_energy = 1.2
	add_child(_light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(1.8,1.3,3.0)
	camera.look_at(Vector3(-0.22,0.64,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.65
	camera.current = true
	_ice = PROJECTILE.instantiate()
	add_child(_ice)
	_ice.drop_height = 0.25
	_ice.show_conjured()
	_material = _ice._spike.material_override.duplicate() as ShaderMaterial
	_ice._spike.material_override = _material
	_build_controls()
	_reference_settings()

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20,20)
	panel.custom_minimum_size.x = 280
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ICE MATERIAL LAB"
	title.add_theme_font_size_override("font_size",24)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Production Godot shader\nSpace: rotate / stop\nLocal preview settings only"
	box.add_child(hint)
	_slider(box,"Blue tint","blue_tint_strength",0,1,0.01)
	_slider(box,"Frost contrast","frost_contrast",0,1,0.01)
	_slider(box,"Frost roughness","frost_roughness",0,1,0.01)
	_slider(box,"Clear roughness","clear_roughness",0,1,0.01)
	_slider(box,"Ambient fill","ambient_fill",0,0.5,0.01)
	_slider(box,"Key light","light",0,3,0.05)
	var reflections := CheckButton.new()
	reflections.text = "Studio reflections"
	reflections.button_pressed = true
	reflections.toggled.connect(func(enabled: bool):
		_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if enabled else Environment.REFLECTION_SOURCE_DISABLED)
	box.add_child(reflections)
	var reference := Button.new()
	reference.text = "Try clearer blue ice"
	reference.pressed.connect(_reference_settings)
	box.add_child(reference)
	var original := Button.new()
	original.text = "Current game material"
	original.pressed.connect(func():
		var base: ShaderMaterial = load("res://assets/effects/ice/ice_material.tres")
		for key in _sliders:
			if key != "light":
				_sliders[key].value = base.get_shader_parameter(key))
	box.add_child(original)

func _slider(box: VBoxContainer, label: String, parameter: String, low: float, high: float, step: float) -> void:
	var caption := Label.new()
	box.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(270,24)
	slider.value_changed.connect(func(value: float):
		caption.text = "%s: %.2f" % [label,value]
		if parameter == "light":
			_light.light_energy = value
		else:
			_material.set_shader_parameter(parameter,value))
	box.add_child(slider)
	_sliders[parameter] = slider
	slider.value = 0.01

func _reference_settings() -> void:
	var settings := {"blue_tint_strength":0.85,"frost_contrast":0.6,"frost_roughness":0.55,"clear_roughness":0.08,"ambient_fill":0.06,"light":1.2}
	for key in settings:
		_sliders[key].value = settings[key]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_rotate = not _rotate

func _process(delta: float) -> void:
	if _rotate:
		_ice.rotation.y += delta * 0.35


