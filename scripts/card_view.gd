extends RefCounted
class_name CardView
## The one place a card IMAGE is given the project's standard look: rounded corners, the thin black line
## along the bottom of that outline, and a hover aura that can be tinted.
##
## It exists because that look was being written out by hand in the deck editor and would otherwise be
## written out again in the deck search window — three copies of a shader material that must stay identical,
## which is three chances for them to drift apart.
##
## Everything static: these are pure functions of an id or a material, with no state to hold.

const ROUND_SHADER := preload("res://shaders/thumb_round.gdshader")
const ART_DIR := "res://assets/cards"
## In UV, so it is a fraction of the image rather than pixels — see the shader.
const CORNER_RADIUS := 0.07
## Preloaded by PATH, not through the global class cache — a class_name added since Godot last scanned is not
## in that cache, which is a parse error on every headless run.
const CARD_FILTER := preload("res://scripts/card_filter.gd")

## Blue, the project's "you may pick this" colour. The deck editor's hover and the match's targeting ring
## use the same family on purpose, so one meaning has one look across the whole game.
const HOVER_COLOUR := Color(0.15, 0.45, 1.0)
## Orange, the project's "you picked this" colour.
const SELECTED_COLOUR := Color(1.0, 0.45, 0.05)
## How an unselectable card is dimmed — the same treatment the deck editor gives a pile's back copies.
const UNAVAILABLE_TINT := Color(0.30, 0.32, 0.38)

## A material that rounds a texture's corners. Built per call rather than shared: a shared material would be
## mutated by whichever card touched it last, and every card needs its OWN hover and aura state.
static func round_material(radius: float = CORNER_RADIUS) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROUND_SHADER
	material.set_shader_parameter("radius", radius)
	return material

## The printed code for a database id, or "" when there is no such card.
static func code_of(id: int) -> String:
	var card: Dictionary = CARD_FILTER.card_by_id(id)
	return str(card.get("code", ""))

## Where the art for `id` lives, or "" when there is none on disk. Callers check for "" rather than
## probing the filesystem themselves, so "no art" has one definition.
static func art_path(id: int) -> String:
	var code: String = code_of(id)
	if code.is_empty():
		return ""
	var path: String = "%s/%s.jpg" % [ART_DIR, code]
	return path if ResourceLoader.exists(path) else ""

## Lights or unlights a card's aura in `colour`, tweened so it fades rather than snapping on. `node` must
## already carry a material from round_material().
static func set_aura(node: Control, on: bool, colour: Color = HOVER_COLOUR) -> void:
	if node == null or not (node.material is ShaderMaterial):
		return
	var material: ShaderMaterial = node.material
	material.set_shader_parameter("aura_colour", colour)
	var from: float = 0.0
	# A missing parameter reads back as null, and float(null) is a hard error rather than a 0.
	var current: Variant = material.get_shader_parameter("hover")
	if current is float:
		from = current
	var tween: Tween = node.create_tween()
	tween.tween_method(func(v: float): material.set_shader_parameter("hover", v),
		from, 1.0 if on else 0.0, 0.12)

## A dimmed card reads as "not selectable". Applied to the node rather than the material so it composites
## over the aura instead of replacing it.
static func set_unavailable(node: Control, unavailable: bool) -> void:
	if node != null:
		node.modulate = UNAVAILABLE_TINT if unavailable else Color.WHITE
