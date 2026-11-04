class_name VfxPreset
extends Resource
## Data-only look definition for one element/status. The VfxDirector resolves a
## preset and later hands it to presentation nodes; card effects never need to
## know which scene or material an element uses.

@export var element: String = ""
@export var status: String = ""
@export var tint: Color = Color.WHITE
@export var impact_scene: PackedScene
@export var board_impact_scene: PackedScene
@export var shard_scene: PackedScene
@export var flash_material: Material
@export var camera_shake: float = 0.0
@export var hit_stagger_seconds: float = 0.06
@export var board_stagger_seconds: float = 0.08
@export var sound: AudioStream


func is_status() -> bool:
	return not status.is_empty()
