extends "res://scripts/vfx/vfx_cue.gd"
## Presentation for one `DAMAGE` / `BOARD_DAMAGE` / `EFFECT_BREAK` event whose element is 火.
##
## Each target gets one fire_burst.gd: sparks gather, then explode. This cue decides who is hit and when, and owns the
## rules-facing beats at each DETONATION: the card's recoil (the preset sets `owns_damage_reaction`, so the generic
## recoil does not fire at damage time, before anything has exploded) and the release of a held break (`effect_break`:
## a card the fire breaks shatters in the blast, not when the effect resolves).
##
## Several targets charge together with a short stagger, so a board hit is one eruption rather than a slow roll call.
## The bursts live under the tree root and finish their smoke and embers on their own; the cue only holds the
## presentation queue until shortly after the last detonation.

const BURST := preload("res://scripts/vfx/fire_burst.gd")
const MULTI_STAGGER_SECONDS := 0.14
const SEQUENCE_STAGGER_SECONDS := 0.35
## How long the queue waits past the last detonation (the fireball's brightest part).
const HOLD_AFTER_DETONATION := 0.40
const SCREEN_FLASH_LAYER := 80
const FLASH_ALPHA_BY_TIER: Array[float] = [0.08, 0.13, 0.18, 0.24]

var _burst_count: int = 0


func play(event: VfxEvent) -> void:
	var ordered: Array = []
	for entry in event.targets:
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error.
		if not is_instance_valid(entry) or not (entry is Card):
			continue
		var card: Card = entry
		if card.is_drawn_on_field() or event.target_visuals.has(card.get_instance_id()):
			ordered.append(card)
	if ordered.is_empty():
		await get_tree().process_frame
		return
	if event.mode == "single":
		ordered = [ordered[0]]
	var spacing: float = 0.0
	if ordered.size() > 1:
		spacing = SEQUENCE_STAGGER_SECONDS if event.mode == "sequence" else MULTI_STAGGER_SECONDS

	var tier: int = event.damage_tier()
	var amount: int = event.amount if event.kind != VfxEvent.Kind.EFFECT_BREAK else Vfx.EFFECT_BREAK_AMOUNT
	_burst_count = ordered.size()
	for i in ordered.size():
		var card: Card = ordered[i]
		var visual: Dictionary = event.target_visuals.get(card.get_instance_id(), {})
		var burst: Node3D = BURST.new()
		burst.name = "FireBurst"
		get_tree().root.add_child(burst)
		var delay := float(i) * spacing
		burst.call("setup", card, visual.get("transform", null), event.seed + i * 173, delay, tier)
		_detonate(card, visual, delay + BURST.CHARGE_SECONDS, amount)

	_flash_screen(BURST.CHARGE_SECONDS, tier)
	var total: float = float(ordered.size() - 1) * spacing + BURST.CHARGE_SECONDS + HOLD_AFTER_DETONATION
	await get_tree().create_timer(total).timeout


## The rules-facing beat of one burst: a held break shatters, a surviving card recoils.
func _detonate(card: Card, visual: Dictionary, delay: float, amount: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(card):
		return
	if visual.has("stand_in"):
		Vfx.release_hold(card, visual, true)
	elif card.is_drawn_on_field():
		card.damage_fx.play_reaction(amount)


## Probe hook: how many cards this cue set on fire.
func burst_count() -> int:
	return _burst_count


func _flash_screen(delay: float, tier: int) -> void:
	var layer := CanvasLayer.new()
	layer.name = "FireScreenFlash"
	layer.layer = SCREEN_FLASH_LAYER
	add_child(layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = get_viewport().get_visible_rect().size
	rect.color = Color(1.0, 0.55, 0.18, 1.0)
	rect.modulate.a = 0.0
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = additive
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_interval(maxf(delay, 0.0))
	tween.tween_property(rect, "modulate:a", FLASH_ALPHA_BY_TIER[clampi(tier, 0, 3)], 0.04) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, "modulate:a", 0.0, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(layer.queue_free)
