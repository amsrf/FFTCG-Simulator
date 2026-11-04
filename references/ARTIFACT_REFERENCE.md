# Artifact (Source 2) graphics reference

Notes from inspecting the installed Artifact client for card-effect ideas. Nothing
in this file is shipped content: it records where the reference assets live and
what they do.

## Install and archives

Artifact install:

`C:\Program Files (x86)\Steam\steamapps\common\Artifact`

The relevant archives are:

- `game\core\pak01_dir.vpk` — engine/core assets
- `game\dcg\pak01_dir.vpk` — Artifact card game assets
- `game\core\shaders_pc_dir.vpk` / `game\dcg\shaders_pc_dir.vpk` — compiled shaders

The client uses Source 2 compiled resource types:

- `.vpcf_c` — particle systems
- `.vmat_c` — materials
- `.vtex_c` — textures
- `.vmdl_c` / `.vmesh_c` — models/meshes
- `.vcs` — shader bytecode

## Re-extraction tools

Two lightweight helpers are kept in `tools/`:

```bash
python tools/artifact_vpk_list.py "<path-to>\\pak01_dir.vpk" "regex"
python tools/artifact_vpk_extract.py "<path-to>\\pak01_dir.vpk" "internal/path.vpcf_c" "out.vpcf_c"
```

For decompiling extracted resources, ValveResourceFormat's CLI was used. The
portable release can be downloaded from:

`https://github.com/ValveResourceFormat/ValveResourceFormat/releases`

The release used here was **20.1**, `cli-windows-x64.zip`, containing
`Source2Viewer-CLI.exe`.

Examples:

```bash
Source2Viewer-CLI.exe -i frostbite_overlay.vpcf_c -d
Source2Viewer-CLI.exe -i card_overlay_decayed01_outer.vtex_c -d --game "<Artifact>/game/dcg/gameinfo.gi" -o overlay.png
```

Particle `.vpcf_c` files decompile to editable `.vpcf` KV3 text. Textures decode
to PNG, models can be exported to glTF with `--gltf_export_format glb`.

## Frostbite

Persistent target effect:

- `particles/card_effects/performances/spells/frostbite/frostbite_overlay.vpcf_c`
- Textures:
  - `materials/particle/dcg/card_overlays_and_borders/card_border_outline_w16_blur4.vtex_c`
  - `materials/particle/dcg/card_overlays_and_borders/card_overlay_decayed01_outer.vtex_c`

Decompiled `frostbite_overlay.vpcf`:

- Lifespan `6.0 s`
- Constant colour `RGB(119, 157, 196, 255)`
- Two additive sprite renderers:
  - blurred card-outline texture, overbright `0.5`
  - decayed/frosted outer overlay, self-illum `1.0`, overbright `2.0`, depth bias `0.2`
- Fade-out `0.5 s`; position-locked to the card
- Preview model `models/card/card.vmdl`
- The alpha pattern is a dense, asymmetric frozen frame: thick left/bottom and
  corner buildup, thinner top/right, clear central window.

Cast/impact composite:

- `particles/card_effects/performances/spells/frostbite/frostbite_impact.vpcf_c`
- Children: `frostbite_overlay`, impact sprites, `maiden_frostbite_trail`,
  `frostbite_impact_sparkles`, `frostbite_impact_models`, `shake_light`
- `frostbite_impact_models.vpcf_c` spawns `models/effects/crystal002.vmdl` with
  `materials/models/effects/crystals/crystal002.vmat`; there is a refract variant
- Ice-shard material:
  `materials/models/particle/frostbite_ice_shards.vmat_c`
  (shader `dcg/global_lit_simple.vfx`; colour + dire/spec masks)

## Winter's Curse ice

A separate, heavier ice-encasement effect:

- `particles/card_effects/performances/spells/winters_curse/winters_curse_target_ice_base.vpcf_c`
  — cyan `RGB(187, 228, 255)`, 4 s lifespan
- Children include `winters_curse_target_ice_model_base_ref/spc`
- Models: `models/effects/winters_curse_ice_trap.vmdl`,
  `winters_curse_ice_attacker_a.vmdl`, `..._attacker_b.vmdl`
- Materials: `materials/models/effects/ice_a.vmat`, `ice_c.vmat`
- Falling bits: `winters_curse_target_ice_model_bits.vpcf_c` uses
  `models/particle/tiny_simrocks.vmdl` with `ice_c.vmat`

This is actual geometry around the card, unlike Frostbite's card-space overlay.

## Thundergod's Wrath lightning

This is the reference used for our per-target 雷 damage strike. It is a useful
example of a composite effect built from a few small pieces rather than one
large system.

Top-level and support particles:

- `particles/card_effects/performances/spells/thunder_gods_wrath/thunder_gods_wrath_damage.vpcf_c`
  — the per-card damage composite. Children:
  - `tgw_static_weld_flash_a` — flickering contact glow, `RGB(133,176,251)`,
    thin glow sprites over a 0.1 s lifetime, 0.5 s emitter
  - `tgw_new_electrocution_a` — card-border electrocution flipbook,
    `RGB(75,132,255)`, 0.1 s fade, additive + lighten passes
  - `tgw_bolt_a` — the visible falling bolt, an 8-frame `bolt_b` sprite sheet,
    0.4 s lifetime, 0.1 s fade-in, 0.2 s fade-out, radius 10
  - `tgw_static_arcs_a` — short-lived box-shaped static sprites, 0.75 s emitter
  - `tgw_impact_flare_a` — `RGB(138,167,255)` additive flare, 12–18 radius,
    0.25 s continuous emission
  - `tgw_impact_dark_edges` — a soft-centre dark screen overlay, 0.3 s
- `thunder_gods_wrath_death.vpcf_c` — the same composite with the `_b`
  variants, used when the target breaks
- `thunder_gods_wrath.vpcf_c` — the wider area composite: `tgw_scorch`,
  `tgw_bounce_sparks`, `tgw_leaves`, `tgw_smoke`, `tgw_impact_light`
- `thunder_gods_wrath_bolt.vpcf_c` / `..._bolt_glow.vpcf_c` — rope bolts built
  from 32 sequential-path particles, control point 1 at `(0,0,50)`, 0.3 s,
  `beam_generic_2` / `beam_generic_7`; the glow adds a 0.5 self-illum pass
- `thunder_gods_wrath_shake.vpcf_c` — 0.2 s screen-shake renderer,
  frequency 8, amplitude 2, radius 1500
- `thunder_gods_wrath_lane.vpcf_c` — a lane marker that parents `tgw_bg`

The per-card beat is roughly:

1. Contact glow and border arcs start as the bolt lands.
2. The `bolt_b` flipbook plays for 0.4 s with two additive passes, one of
   which is overbright ×2.
3. A blue-white flare, radial static and a dark edge vignette sell the impact.
4. The card itself plays `card_thundergods_wrath_damage.vanim_c`: 22 frames
   at 30 fps (≈0.73 s), activity
   `ACT_kDCG_CARD_EFFECT_DAMAGE_THUNDERGODSWRATH`.

Palette sampled from the particles: white-hot core, `#4B84FF` border arcs,
`#8AA7FF` flare, `#85B0FB` contact glow, with a dark `#000000` edge vignette.

Our implementation (`assets/effects/lightning/`, `shaders/lightning_*.gdshader`)
keeps the same multi-part idea — bolt, contact flare, circular shock wave —
but draws each part procedurally. The per-card structural reference is this
Artifact composite; the colour reference is `references/violet_thunder.jpg`,
used as a white-hot core with purple inner glow and a deep royal-violet
outer halo. No Artifact texture or model is used at runtime.

## Other useful effects found

- `chain_frost` — projectile, impact border, flakes, mist, many explosion pieces
- `arctic_blast` — ice impact and ice normals
- `arctic_burn` — ice models
- `frostbite` — described above
- `winters_curse` — described above
- `thunder_gods_wrath` — per-card lightning composite described above; also
  `lightning_strike`, `ball_lightning`, `bolt_of_damocles`, `thunderstorm`
- `zeus/neighbor_damage*` — smaller chain-lightning arc/impact/source particles

## Local extraction scratch (temporary)

These were extracted under:

`C:\Users\KABUM\AppData\Local\Temp`

Useful temporary files from the investigation:

- `frostbite_overlay.vpcf` / `.vpcf_c`
- `frostbite_impact.vpcf` / `.vpcf_c`
- `frostbite_impact_models.vpcf` / `.vpcf_c`
- `winters_curse_target_ice_base.vpcf`
- `winters_curse_target_ice_model_bits.vpcf`
- `alpha_card_overlay_decayed01_outer.png`
- `alpha_card_border_outline_w16_blur4.png`
- `winters_curse_ice_trap.glb`

Temp files may be cleared. The VPK paths above are the durable record.

## Copyright / usage

Artifact's extracted textures, models, particle definitions, and materials are
Valve's copyrighted game content. Use them only as local visual reference while
authoring original effects. Do not commit extracted assets to this repository or
ship them with the simulator. Our committed frost assets live in
`assets/effects/frost/` and are generated by `tools/make_frost_overlay.py`.
