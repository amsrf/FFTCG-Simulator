extends BigButton
class_name GemButton
## The gem button: BigButton's structure and interaction (Area3D, text viewport, hover scale,
## press pulse) with the generated capsule model in place of the flat plate.
##
## Two things differ from BigButton, both consequences of the frame being METAL:
##
## 1. HOVER/DISABLED FEEDBACK cannot be `_dim_to()`. BigButton tweens a material's `albedo_color`
##    on hover and on disable, which is invisible on a full metal — metal has almost no diffuse
##    response, so lightening its albedo changes nothing on screen. The cue that does show is the
##    STONE: its shader's `emission_strength` drives the glow, and "lit teal stone -> grey unlit
##    stone" is exactly how the reference depicts enabled vs disabled. So this class drives that
##    instead, and leaves BigButton's albedo tween alone (it is harmless).
##
## 2. The model is an INSTANCED glb, so `$Background/MeshInstance3D` is an empty placeholder kept
##    only so BigButton's lookup path resolves. It is deliberately left WITHOUT a material: an
##    override would reference the shared `gem_button_metal.tres`, and BigButton's tween would then
##    dim every button at once — and persist that change if the resource were ever saved.
##    The real materials are applied per-mesh by GemButtonModel, which runs before this `_ready`.

const LIT_EMISSION := 1.1       # matches the shipped gem_button_stone.tres
const HOVER_EMISSION := 1.8     # pointer over: the stone brightens
const DISABLED_EMISSION := 0.12 # disabled: barely alive, the reference's grey stone

@onready var _model: GemButtonModel = $Background/Model

func _ready() -> void:
	super()
	_apply_stone(_target_emission())

## The frame's material, so a caller can still reach it if it wants to.
func frame_material() -> StandardMaterial3D:
	return _model.frame_material if _model != null else null

func _target_emission() -> float:
	if _disabled:
		return DISABLED_EMISSION
	return HOVER_EMISSION if _hovered else LIT_EMISSION

func _apply_stone(value: float) -> void:
	var mat: ShaderMaterial = _model.stone_material if _model != null else null
	if mat == null:
		return
	mat.set_shader_parameter("emission_strength", value)

## Animate the glow rather than snapping it. A shader parameter is not an object property, so this
## uses tween_method with _apply_stone as the setter.
func _animate_stone(to: float) -> void:
	var mat: ShaderMaterial = _model.stone_material if _model != null else null
	if mat == null:
		return
	var from: float = float(mat.get_shader_parameter("emission_strength"))
	var tween := create_tween()
	tween.tween_method(_apply_stone, from, to, 0.12)

func _on_area_hovered() -> void:
	super()
	if not _disabled:
		_animate_stone(HOVER_EMISSION)

func _on_area_unhovered() -> void:
	super()
	if not _disabled:
		_animate_stone(LIT_EMISSION)

func set_disabled(value: bool) -> void:
	super(value)
	_animate_stone(DISABLED_EMISSION if value else LIT_EMISSION)
