extends Node3D
## The two board button stations (housings baked into the board; Blender/build_button_housing.py). The local
## station's discs are driven by the match buttons (disc_button.gd). The opponent's are a read-out only: their
## forward disc lights while the opponent holds priority, and their Cancel never lights.
##
## Both forward coins use amber to indicate priority. The small gem discs use the seat's accent colours.
## The station's stone follows the biome, exactly as BoardEnvironment.configure_seat() swaps the baked board.

# Linear colours, the same numbers as the Blender mock-up.
const VOLCANIC_STONE := Color(0.035, 0.034, 0.036)
const VOLCANIC_GROOVE := Color(0.16, 0.15, 0.14)          # iron
const FOREST_STONE := Color(0.12, 0.12, 0.115)
const FOREST_GROOVE := Color(0.42, 0.27, 0.12)            # bronze
const LOCAL_FORWARD := [Color(0.0, 0.26, 0.25), Color(0.02, 0.55, 0.50), Color(0.25, 1.0, 0.85)]
const LOCAL_CANCEL := [Color(0.36, 0.03, 0.02), Color(0.7, 0.08, 0.03), Color(1.0, 0.35, 0.12)]
const OPPONENT_FORWARD := [Color(0.17, 0.04, 0.30), Color(0.45, 0.14, 0.80), Color(0.7, 0.4, 1.0)]

@onready var local_forward: Node3D = $LocalForward
@onready var local_cancel: Node3D = $LocalCancel
@onready var opponent_forward: Node3D = $OpponentForward
@onready var opponent_cancel: Node3D = $OpponentCancel
const PHASE_DIAL := preload("res://scripts/ui/phase_dial.gd")
## The phase marks + pointer around each big button (scripts/ui/phase_dial.gd); both show the current phase.
var local_dial: Node3D
var opponent_dial: Node3D


func _ready() -> void:
	configure_seat(1)
	local_dial = _add_dial(local_forward)
	opponent_dial = _add_dial(opponent_forward)


func _add_dial(socket: Node3D) -> Node3D:
	var dial: Node3D = PHASE_DIAL.new()
	dial.name = "PhaseDial"
	socket.add_child(dial)
	return dial


## Game.phase_entered: both dials point at the phase (it is the same phase for both players).
func show_phase(phase: int) -> void:
	for dial in [local_dial, opponent_dial]:
		if dial != null:
			dial.show_phase(phase)

func configure_seat(seat: int) -> void:
	var local_volcanic := seat != 2
	var local_stone := VOLCANIC_STONE if local_volcanic else FOREST_STONE
	var local_groove := VOLCANIC_GROOVE if local_volcanic else FOREST_GROOVE
	var far_stone := FOREST_STONE if local_volcanic else VOLCANIC_STONE
	var far_groove := FOREST_GROOVE if local_volcanic else VOLCANIC_GROOVE
	local_forward.set_colors(LOCAL_FORWARD[0], LOCAL_FORWARD[1], local_stone, local_groove, LOCAL_FORWARD[2])
	local_cancel.set_colors(LOCAL_CANCEL[0], LOCAL_CANCEL[1], local_stone, local_groove, LOCAL_CANCEL[2])
	opponent_forward.set_colors(OPPONENT_FORWARD[0], OPPONENT_FORWARD[1], far_stone, far_groove, OPPONENT_FORWARD[2])
	opponent_cancel.set_colors(OPPONENT_FORWARD[0], OPPONENT_FORWARD[1], far_stone, far_groove, OPPONENT_FORWARD[2])
	# The priority coins belong to the SEAT, like the biome: seat 1 (volcanic) is Chaos, seat 2 (forest) is Cosmos.
	local_forward.set_coin_style("chaos" if local_volcanic else "cosmos")
	opponent_forward.set_coin_style("cosmos" if local_volcanic else "chaos")
	local_cancel.set_coin_style("chaos" if local_volcanic else "cosmos")
	opponent_cancel.set_coin_style("cosmos" if local_volcanic else "chaos")

## The opponent holds priority: their forward disc is up. Their Cancel never is.
func set_opponent_priority(on: bool) -> void:
	opponent_forward.set_claim(self, on)
