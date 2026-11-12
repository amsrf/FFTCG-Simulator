class_name LightningStrikeCue
extends VfxCue
## Presentation for one `DAMAGE` / `BOARD_DAMAGE` event whose element is 雷.
##
## A directed hit gets one bolt. A multi-target or board event gets one bolt per
## target, spaced just far enough apart to read as separate impacts. The actual
## bolt, flare and shockwave live in `lightning_strike.gd`, so this file only decides
## who is hit, in what order, and when the screen flash fires.

const STRIKE_SCENE := preload("res://assets/effects/lightning/lightning_strike.tscn")
## When the bolt reaches the card (LightningStrike.REVEAL_SECONDS).
const IMPACT_SECONDS := 0.09
const STRIKE_LIFETIME := 0.58
const SCREEN_FLASH_LAYER := 80
## A single strike owns the stage for about 0.58 s. Multi-target hits start the
## next bolt well into the previous tail so each impact reads separately.
const MULTI_STAGGER_SECONDS := 0.36
const SEQUENCE_STAGGER_SECONDS := 0.45
## Screen-flash peak by damage tier: weak, medium, high, maximum.
const FLASH_ALPHA_BY_TIER: Array[float] = [0.12, 0.22, 0.28, 0.34]

var _strike_count: int = 0


func play(event: VfxEvent) -> void:
	var targets: Array = []
	for target in event.targets:
		if target != null and is_instance_valid(target) and target is Node3D:
			targets.append(target)
	if targets.is_empty():
		await get_tree().process_frame
		return

	# A single-target event always strikes exactly one card. Multi/sequence/
	# radial/board events strike every valid target; the delays keep the
	# impacts legible instead of stacking every flare on one frame.
	var ordered: Array = targets
	if event.mode == "single" or event.kind == VfxEvent.Kind.DAMAGE and targets.size() == 1:
		ordered = [targets[0]]
	var spacing: float = 0.0
	if ordered.size() > 1:
		spacing = SEQUENCE_STAGGER_SECONDS if event.mode == "sequence" else MULTI_STAGGER_SECONDS

	var tint: Color = Vfx.tint_for(event)
	_strike_count = ordered.size()
	for i in ordered.size():
		var strike: Node3D = STRIKE_SCENE.instantiate()
		add_child(strike)
		var visual: Dictionary = event.target_visuals.get(ordered[i].get_instance_id(), {})
		strike.call("setup", ordered[i], tint, event.seed + i * 173, float(i) * spacing,
			event.damage_tier(), visual.get("transform", null))
		# A break by effect: the card is HELD on its slot (Vfx.hold_card) and breaks when the bolt lands. A card that
		# protection saved just takes the hit.
		if visual.has("stand_in") or event.kind == VfxEvent.Kind.EFFECT_BREAK:
			_on_impact(ordered[i], visual, float(i) * spacing + IMPACT_SECONDS)

	# The screen flash belongs to the impact, not to the wind-up. It is one
	# shared flash even when several bolts land, so a board hit does not strobe.
	_flash_screen(0.095, tint, event.damage_tier())

	var total: float = STRIKE_LIFETIME + float(maxi(ordered.size() - 1, 0)) * spacing
	await get_tree().create_timer(total).timeout


func _on_impact(card: Card, visual: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(card):
		return
	if visual.has("stand_in"):
		Vfx.release_hold(card, visual, true)
	elif card.is_drawn_on_field():
		card.damage_fx.play_reaction(Vfx.EFFECT_BREAK_AMOUNT)


## Probe hook: how many cards this cue actually struck.
func strike_count() -> int:
	return _strike_count


func _flash_screen(delay: float, tint: Color, tier: int) -> void:
	var layer := CanvasLayer.new()
	layer.name = "LightningScreenFlash"
	layer.layer = SCREEN_FLASH_LAYER
	add_child(layer)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	rect.position = Vector2.ZERO
	rect.size = viewport_size
	var flash := tint.lerp(Color(0.72, 0.50, 1.0, 1.0), 0.58)
	flash.a = 1.0
	rect.color = flash
	rect.modulate.a = 0.0
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = additive
	layer.add_child(rect)

	var tween := create_tween()
	tween.tween_interval(maxf(delay, 0.0))
	tween.tween_property(rect, "modulate:a", FLASH_ALPHA_BY_TIER[clampi(tier, 0, 3)], 0.035) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, "modulate:a", 0.0, 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(layer.queue_free)
