# Game audio

- `sfx/cards/draw/`: all 22 original Artifact draw WAV variants, copied unchanged for the prototype.
- `sfx/cards/flip_distant/`: all 22 original Artifact `flip_distant` WAV variants, copied unchanged for the prototype. `card_flip` plays one at random (never the same twice in a row) once when a local hand preview expands, including reopening or switching cards; remaining hovered and closing it are silent. It uses the same SFX volume/mute controls.
- Add future categories under `sfx/` (combat, UI, spells); keep music under `music/` when introduced.
- `scripts/audio/sound_manager.gd` owns named sound events, variant selection, a separate cosmetic RNG, and bounded overlapping playback. Call `SoundManager.play(&"event_name")` from the matching presentation beat.
- Register each new event with its streams and default volume using `register_event`. Do not scatter individual file paths into gameplay scripts.
- `card_draw` plays at the start of `Hand.draw_many`, for both sides, once per valid card. Empty draws make no sound. Immediate repeats are excluded. Batch volume is reduced by the square root of the card count to soften overlapping draws.
- All effects route through the `SFX` bus, exposed by `set_sfx_volume_db` and `set_sfx_muted`. Music can use a separate bus later. No settings UI or persisted preferences yet.

Source: Valve Artifact, installed `game/dcg/pak01` archives, `sounds/cards/draw_01.vsnd_c` through `draw_22.vsnd_c` and `flip_distant_01` through `flip_distant_22`. Extracted without re-encoding. Prototype assets; no redistribution license is asserted. Replace this bank before release unless permission is obtained.
