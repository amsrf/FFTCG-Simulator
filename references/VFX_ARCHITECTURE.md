# VFX architecture

Rules code describes **what happened**. Presentation code decides **how it
looks**. Nothing in a card effect should preload or instantiate particles,
models, flashes, or camera shakes directly.

## Flow

```text
Card / EffectContext / Game
        -> semantic VfxEvent
        -> VfxDirector (autoload `Vfx`)
        -> VfxPreset for element/status
        -> presentation scene(s)
```

`VfxDirector._present()` instantiates the preset's scene and awaits its
`play(event)` method when it has one. A one-shot scene can extend `VfxCue`
(`scripts/vfx/vfx_cue.gd`) for the base contract. Until a preset supplies a
scene, the event still emits, is logged synchronously, and advances the queue
in deterministic order, so the event contract stays stable while scenes are
authored one at a time.

## Event contract

`scripts/vfx/vfx_event.gd` — `VfxEvent`:

```gdscript
kind: VfxEvent.Kind
targets: Array[Card]
source: Card
element: String
amount: int
mode: String        # single / multi / sequence / radial / board
status: String
duration: int
cause: String
seed: int           # deterministic variation
```

Kinds:

- `STATUS_APPLIED`
- `STATUS_REMOVED`
- `DAMAGE`
- `BOARD_DAMAGE`
- `CARD_BROKEN`

`BOARD_DAMAGE` is deliberately separate from `DAMAGE`, even though both carry
target lists. That lets a board wave preset exist without changing every card.

## Damage magnitude

`VfxEvent.damage_tier()` is shared by every element cue, not just lightning:

```text
<= 3000        tier 0  weak
3001 .. 6000   tier 1  medium
6001 .. 8999   tier 2  high
9000+          tier 3  maximum
```

`damage_scale()` returns a neutral `[0.55, 1.0, 1.35, 1.75]` multiplier for
cues that do not have their own tuning. Lightning uses its own `TIER_*` arrays
for bolt width, glow, branching, span, shockwave extent and impact intensity.

## Director API

```gdscript
Vfx.status_applied(card, status, duration)
Vfx.status_removed(card, status)
Vfx.damage(targets, amount, element, source, mode)
Vfx.board_damage(targets, amount, element, source, mode)
Vfx.card_broken(card, cause)
```

Events are appended synchronously to `Vfx.get_events()`. The presentation queue
is serial: only one one-shot owns the stage at a time. `clear_events()` is for
probes.

## Presets

`scripts/vfx/vfx_preset.gd` — `VfxPreset` resource fields:

```gdscript
element, status, tint
impact_scene, board_impact_scene, shard_scene
flash_material, camera_shake
hit_stagger_seconds, board_stagger_seconds
sound
```

Preset locations:

```text
assets/vfx/elements/fire.tres
assets/vfx/elements/ice.tres
assets/vfx/elements/wind.tres
assets/vfx/elements/earth.tres
assets/vfx/elements/lightning.tres
assets/vfx/elements/water.tres
assets/vfx/elements/light.tres
assets/vfx/elements/dark.tres
assets/vfx/status/frozen.tres
assets/vfx/status/haste.tres
```

The director falls back to `ELEMENT_TINTS` when no `.tres` exists, so an event
always has a usable colour.

## Hook points

- `Card.add_status_effect()` -> `Card.refresh_status_visuals()` -> `_sync_status_vfx()`
  - also catches direct `status_effects.erase(...)` calls when the caller refreshes
- `EffectContext.damage()` -> `Vfx.damage(...)`
- `EffectContext.board_damage()` -> `Vfx.board_damage(...)`
- `Game.break_card()` -> `Vfx.card_broken(...)`

Persistent status visuals are owned by the card. The existing frozen overlay is
the first example: `Card.refresh_frozen_overlay()` owns the quad and its
spread/recede tweens, while the director receives the semantic status events.

## Card damage reaction

`Card.play_damage_reaction()` is card-owned presentation, not a `VfxCue`. It is
called from `Card.suffer_damage()` only for a non-empty `source_kind` (effect /
Summon damage), so combat keeps the clash presentation. It animates `HandMesh`
rather than the Card root, because the root belongs to the Field layout. The
0.62 s motion is two curves: a fast lift/scale bounce and a signed yaw/roll/side
wiggle that damps to rest.

`EffectContext._apply_damage_to_cards()` passes `i * 0.20 s` as `reaction_delay`
through `Field.cause_damage()` so a multi-target effect reacts as a sequence.
`Card.enter_zone()` and `reset_for_field_arrival()` normalise the mesh so a hit
pose cannot leak into the next zone. The viewing harness is
`tools/damage_reaction_demo.tscn`.

## Authored effects

### Lightning damage (雷)

- Preset: `assets/vfx/elements/lightning.tres`
- Cue: `assets/effects/lightning/lightning_strike_cue.tscn`
  (`scripts/vfx/lightning_strike_cue.gd`)
- Per-target visual: `assets/effects/lightning/lightning_strike.tscn`
  (`scripts/vfx/lightning_strike.gd`)
- Shaders:
  - `shaders/lightning_bolt.gdshader` — camera-facing descending channel
  - `shaders/lightning_impact.gdshader` — card-plane flare, ring and forks
- Viewing harness: `tools/lightning_demo.tscn` — empty `clean` ground,
  three numbered targets, auto-plays once; keys `1/2/3`, `SPACE`/`R`, `M`,
  `B`, `A`, and `T` to cycle the 3000/5000/8000/12000 damage tiers (`--tier 0..3`
  for a screenshot)

The cue chooses targets from the event, so a normal directed hit strikes one
card. `multi`, `sequence`, `radial` and `board` events use one strike per valid
target; the stagger is 0.36 s (0.45 s for `sequence`) so separate impacts stay
readable. `single` never fans out. The preset points both `impact_scene` and
`board_impact_scene` at the cue, so a board-damage event uses the same
staggered presentation until a dedicated board wave is authored.

The bolt is a camera-facing quad anchored to `Card.get_global_face_centre()` and
extended up the camera's screen-up axis. Because the board camera is almost
top-down, a world-vertical bolt would be seen end-on, so the effect is built in
screen space. Do not push the quad back along camera Z to fake depth: that
changes the projected landing point for an off-centre card. `depth_test_disabled`
is intentional here, so the bolt and flare read over the card they hit.
`QuadMesh` maps UV.y 0 to its top edge, so the bolt shader uses `y = 1 - UV.y`
to keep the path's convergence and impact pool on the card.

The palette follows `references/violet_thunder.jpg`: white-hot core, purple
inner glow, deep royal-violet outer halo. It is not a flat violet bolt.
The two shaders are listed in `Game.EFFECT_SHADERS`, because Compatibility
compiles a shader on first render and a first strike must not hitch.

### Haste clock (status "haste")

`Card.sync_haste_vfx()` raises `STATUS_APPLIED("haste")` when `has_haste()` turns true on the field, so every source
of Haste (printed, timed status, aura grant, code keyword) is one trigger; the generic `_sync_status_vfx()` skips the
"haste" status so it never fires twice. `Field.play_card()` holds the edge until the arrival presentation is queued
(`Card.begin_field_arrival()` / `end_field_arrival()`: a `Vfx.present` job after the arrival clears the hold, so the
clock plays on the landed card). The cue spawns one `haste_clock.gd` per card under the
tree root and releases the queue after `APPEAR_SECONDS`; the clock follows its card and frees itself at `LIFETIME`.
Viewing harness: `tools/haste_demo.tscn`; probe: `tests/haste_vfx_probe.tscn`.

### Summoning-sickness waves (persistent, card-owned)

Not a `VfxCue`: like the frozen overlay it lives as long as its condition. `card_status_overlays.refresh_sickness()`
builds `scripts/cards/sickness_overlay.gd` (a card-aligned plane on `HandMesh`, `shaders/sickness_waves.gdshader`: soft dark circular pulses rippling outward
from the centre)
lazily and drives it from `Card.shows_summoning_sickness()`; the overlay picks its exit (wake / burst / dismiss / hide).
Viewer: `tools/sickness_demo.tscn`; probe: `tests/sickness_waves_probe.tscn`.

## Adding a new effect

1. Create or update the element/status preset `.tres`.
2. Author the presentation scene with its own `play(event)`/awaitable lifecycle.
3. Wire the scene into the preset fields.
4. Have the rules effect call the director API, or rely on the core hooks above.
5. Add a probe that asserts the event contract, not the pixels.

Do not add per-card branches like `if card.element == "火": preload(...)`.
Element and target-count differences belong in presets and spread modes.
