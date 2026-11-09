extends Node3D
## Visual sandbox for the card break.
##
## Open CardShatterPreview.tscn and press F6. Select the CardShards child in the
## Inspector to tune speed, drag, gravity, spin, lifetime and glass values; the
## preview loops so every change can be judged against the next break.

const CARD_SCENE := preload("res://scenes/cards/card.tscn")

@export var card_id: int = 1
@export var card_scale: float = 1.8
## Lift the card above the floor in the preview. In a real match the card sits
## on the board, so the fall is shorter; the preview needs enough airtime to
## judge the landing.
@export var card_height: float = 0.9
@export var front_hold_seconds: float = 0.8
@export var repeat_seconds: float = 2.2

@onready var shards = $CardShards
@onready var camera: Camera3D = $Camera3D

var _card: Card = null


func _ready() -> void:
	camera.position = Vector3(0.0, card_height + 1.0, 2.8)
	camera.look_at(Vector3(0.0, card_height * 0.45, 0.0), Vector3.UP)
	shards.free_when_done = false
	_cycle()


func _spawn_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = CARD_SCENE.instantiate() as Card
	add_child(_card)
	_card.initialize(card_id, "player")
	_card.enter_zone(Card.Zone.FIELD)
	_card.position = Vector3(0.0, card_height, 0.0)
	_card.scale = Vector3.ONE * card_scale
	_card.visible = true


func _cycle() -> void:
	while is_inside_tree():
		_spawn_card()
		await get_tree().create_timer(front_hold_seconds).timeout
		if _card == null or not is_instance_valid(_card):
			continue
		_card.visible = false
		shards.burst_from_card(_card)
		await get_tree().create_timer(repeat_seconds).timeout
		if _card != null and is_instance_valid(_card):
			_card.queue_free()
		_card = null
