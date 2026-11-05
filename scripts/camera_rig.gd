extends Camera3D
class_name BoardCameraRig

## The board view, authored as one switchable rig instead of two hand-placed cameras.
##
## WHY: the old camera was ORTHOGRAPHIC, and almost every layout system in the game reads
## `cam.size` or relies on orthographic projection being affine (moving a node never changes
## how big it looks). A bare `projection = 0` therefore changes almost nothing at the old
## position — every zone is 3.8-4.0 m away, so the perspective size difference was 0-3%.
##
## The view is described by three art-facing numbers:
##   * elevation_deg  how far the camera is lifted off the board plane (90 = straight down),
##   * frame_width    how many metres are visible across the board centre,
##   * fov_deg        the lens. Distance is DERIVED, so changing the lens never reframes.
##
## ORTHOGRAPHIC is kept as a fallback, restoring the transform captured at startup, so the
## migration can be A/B tested and rolled back without a scene edit.

enum Mode { ORTHOGRAPHIC, PERSPECTIVE }

@export var mode: Mode = Mode.PERSPECTIVE
## The old board framing, used only in ORTHOGRAPHIC mode.
@export var ortho_size: float = 5.766
## Look-at point on the board. 0.35 m is roughly card-centre height above the table.
@export var target: Vector3 = Vector3(0.0, 0.35, -0.25)
## 67 deg is the "B" candidate: still clearly a table, but cards keep their readable shape.
@export_range(30.0, 90.0, 0.5) var elevation_deg: float = 67.0
@export_range(10.0, 90.0, 0.5) var fov_deg: float = 30.0
## Visible width at `target`, in metres. Derived distance keeps this fixed when fov changes.
@export_range(2.0, 20.0, 0.1) var frame_width: float = 8.0

var _ortho_transform: Transform3D

func _ready() -> void:
	_ortho_transform = global_transform
	apply()
	get_viewport().size_changed.connect(apply)

## Recompute projection and pose from the exported parameters. Safe to call at runtime.
func apply() -> void:
	if mode == Mode.ORTHOGRAPHIC:
		projection = PROJECTION_ORTHOGONAL
		size = ortho_size
		global_transform = _ortho_transform
		return

	projection = PROJECTION_PERSPECTIVE
	keep_aspect = KEEP_HEIGHT
	fov = fov_deg
	var view: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var half_fov: float = deg_to_rad(fov_deg) * 0.5
	var distance: float = frame_width / (2.0 * aspect * tan(half_fov))
	var elevation: float = deg_to_rad(elevation_deg)
	global_position = target + Vector3(0.0, distance * sin(elevation), -distance * cos(elevation))
	look_at(target, Vector3.UP)

## Switch projection without editing the scene. Used by the screenshot harness and probes.
func set_mode(next: Mode) -> void:
	mode = next
	apply()
