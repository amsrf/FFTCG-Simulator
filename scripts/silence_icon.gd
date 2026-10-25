extends Node3D
## The silence status icon: a static SVG balloon plus three animated dots.
##
## It lives as a child of Card. The balloon and dots are separate Sprite3D nodes so the dot loop is a runtime
## animation; the SVG itself is static and never contains a frame sequence.

const BALLOON_TEXTURE := preload("res://assets/icons/silence_balloon.svg")
const DOT_TEXTURE := preload("res://assets/icons/silence_dot.svg")

const BALLOON_PIXELS: float = 1024.0
## World units per texture pixel before the icon's own scale is applied.
const PIXEL_SIZE: float = 0.00025
const BASE_WIDTH: float = BALLOON_PIXELS * PIXEL_SIZE
## Texture-space dot centres, measured from the 512 px balloon's top-left.
const DOT_X := [-128.0, 0.0, 128.0]
const DOT_Y: float = 0.0

@export var dot_seconds: float = 0.55

var _balloon: Sprite3D = null
var _dots: Array[Sprite3D] = []
var _elapsed: float = 0.0
var _shown: int = 0
var _mirrored: bool = false
var _active: bool = false
## Whether this node's local +x appears to the RIGHT on screen. The icon is a card child and the card may be
## rotated, so dot positions must follow screen order rather than local order.
var _local_plus_is_screen_right: bool = true


func _ready() -> void:
	_refresh_screen_axis()
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
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


## Set the icon's width in the CARD's local units. The card itself may be scaled by its zone.
func set_icon_width(width_local: float) -> void:
	var width: float = maxf(width_local, 0.001) / BASE_WIDTH
	scale = Vector3.ONE * width
	if _mirrored:
		scale.x = -width


func set_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if on:
		_refresh_screen_axis()
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
	# A NEGATIVE ROOT SCALE, not Sprite3D.flip_h: flip_h did not mirror the billboarded sprites reliably, so
	# the whole icon (balloon, tail and child positions) is mirrored together by the parent transform.
	var width: float = absf(scale.x)
	scale.x = -width if mirror else width
	_refresh_screen_axis()
	for i in range(_dots.size()):
		_dots[i].position = _dot_position(i)


func dot_count() -> int:
	return _shown


func _dot_position(index: int) -> Vector3:
	var x: float = DOT_X[index] / BALLOON_PIXELS * BASE_WIDTH
	if not _local_plus_is_screen_right:
		x = -x
	var y: float = DOT_Y / BALLOON_PIXELS * BASE_WIDTH
	# A hair toward the viewer keeps the dots from competing with the balloon at the same depth.
	return Vector3(x, y, 0.001)


func _refresh_screen_axis() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var origin: Vector2 = cam.unproject_position(global_position)
	var plus: Vector2 = cam.unproject_position(global_position + global_transform.basis.x.normalized() * 0.01)
	_local_plus_is_screen_right = plus.x >= origin.x


func _process(delta: float) -> void:
	advance_animation(delta)


## Explicit step, also used by the probe so the loop can be checked without depending on frame timing.
func advance_animation(seconds: float) -> void:
	if not _active:
		return
	_elapsed += seconds
	# Four frames: one dot, two, three, then an empty beat before the loop repeats.
	var frame: int = int(_elapsed / maxf(dot_seconds, 0.05)) % 4
	var count: int = (frame + 1) if frame < 3 else 0
	if count != _shown:
		_show_count(count)


func _show_count(count: int) -> void:
	_shown = count
	for i in range(_dots.size()):
		# Reveal from the VISUAL left even when the balloon is mirrored: mirroring flips the dot order too.
		var visible_now: bool = (i >= _dots.size() - count) if _mirrored else (i < count)
		_dots[i].visible = visible_now
