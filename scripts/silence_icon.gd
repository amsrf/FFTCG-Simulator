extends Node3D
## The silence status icon: a static SVG balloon plus three animated dots.
##
## It lives as a child of Card. The balloon and dots are separate Sprite3D nodes so the dot loop is a runtime
## animation; the SVG itself is static and never contains a frame sequence.

const BALLOON_TEXTURE := preload("res://assets/icons/silence_balloon.svg")
const DOT_TEXTURE := preload("res://assets/icons/silence_dot.svg")

const BALLOON_PIXELS: float = 512.0
## World units per texture pixel before the icon's own scale is applied.
const PIXEL_SIZE: float = 0.0005
const BASE_WIDTH: float = BALLOON_PIXELS * PIXEL_SIZE
## Texture-space dot centres, measured from the 512 px balloon's top-left.
const DOT_X := [-64.0, 0.0, 64.0]
const DOT_Y: float = 38.0

@export var dot_seconds: float = 0.42

var _balloon: Sprite3D = null
var _dots: Array[Sprite3D] = []
var _elapsed: float = 0.0
var _shown: int = 0
var _mirrored: bool = false
var _active: bool = false


func _ready() -> void:
	_balloon = _make_sprite(BALLOON_TEXTURE, PIXEL_SIZE, 0)
	_balloon.name = "Balloon"
	add_child(_balloon)
	for i in range(3):
		var dot: Sprite3D = _make_sprite(DOT_TEXTURE, PIXEL_SIZE * 0.75, 2)
		dot.name = "Dot%d" % (i + 1)
		dot.position = _dot_position(i)
		add_child(dot)
		_dots.append(dot)
	set_active(false)


func _make_sprite(texture: Texture2D, pixel_size: float, priority: int = 0) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = pixel_size
	# The dots must draw after the white balloon; transparent 3D sprites at the same depth can sort either way.
	sprite.render_priority = priority
	# A status bubble is a screen-facing cue, not a card laid on the board.
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


## Set the icon's width in the CARD's local units. The card itself may be scaled by its zone.
func set_icon_width(width_local: float) -> void:
	scale = Vector3.ONE * (maxf(width_local, 0.001) / BASE_WIDTH)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if on:
		_elapsed = 0.0
		_show_count(1)
	else:
		_show_count(0)


func is_active() -> bool:
	return _active


## Tail direction: the SVG tail points down-left, which is correct for an icon on the card's right. Mirroring
## flips the balloon and moves the dots to the mirrored side.
func set_mirrored(mirror: bool) -> void:
	if mirror == _mirrored:
		return
	_mirrored = mirror
	if _balloon != null:
		_balloon.flip_h = mirror
	for i in range(_dots.size()):
		_dots[i].flip_h = mirror
		_dots[i].position = _dot_position(i)


func dot_count() -> int:
	return _shown


func _dot_position(index: int) -> Vector3:
	var x: float = DOT_X[index] / BALLOON_PIXELS * BASE_WIDTH
	if _mirrored:
		x = -x
	var y: float = DOT_Y / BALLOON_PIXELS * BASE_WIDTH
	# A hair toward the viewer keeps the dots from competing with the balloon at the same depth.
	return Vector3(x, y, 0.001)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var count: int = int(_elapsed / maxf(dot_seconds, 0.05)) % 3 + 1
	if count != _shown:
		_show_count(count)


func _show_count(count: int) -> void:
	_shown = count
	for i in range(_dots.size()):
		# Reveal from the VISUAL left even when the balloon is mirrored: mirroring flips the dot order too.
		var visible_now: bool = (i >= _dots.size() - count) if _mirrored else (i < count)
		_dots[i].visible = visible_now
