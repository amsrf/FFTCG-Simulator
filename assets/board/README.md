# Board scenery

The water is now independent geometry in `river_mesh.bin` / `river_mesh_seat2.bin`, with a live Compatibility shader (`shaders/board_river.gdshader`). It retains the baked base color and bank depth; moving procedural ripples/foam use TIME. `flow_speed` and `ripple_strength` control intensity. Both directions represent the same world current. The rest of the scenery retains baked lighting. Runtime verification remains pending: the headless harness again produced only its engine header, without a result line.

Seat one uses `board_mesh.bin` / `board_appearance.png`; seat two uses the `_seat2` variants. `Game.start_match()` selects the view from `local_seat`. Regenerate seat two with `Blender/export_board_to_godot.py -- --seat2` in Blender. The biomes rotate around the board centre while wood and recesses keep local gameplay coordinates.

Source: `Blender/board_filled_pockets/board_filled_pockets.blend` and its environment-only render, written by `Blender/fill_deck_pockets.py` from `Blender/board_button_stations/board_button_stations.blend` (itself written by `Blender/build_button_housing.py` from `Blender/board_landmarks/board_landmarks.blend`). The button stage adds the two button stations and leaves out their discs, which Godot builds and animates (`scripts/ui/disc_socket.gd`); the pocket stage fills the old shallow deck pockets so the piles lie on plain wood. Rebuild in this order: `build_button_housing.py`, `fill_deck_pockets.py`, then `export_board_to_godot.py`, then the same with `-- --seat2`. The current export was made with Blender 5.2.

`board_mesh.bin` contains BRD1, little-endian uint32 vertex/index counts, float32 x/y/z/u/v per vertex, then uint32 triangle indices. Coordinates are already Godot y-up, at gameplay world scale. `board_appearance.png` supplies the camera-projected baked color and lighting. The loader creates one unshaded ArrayMesh without an editor import dependency. No collision or input handlers are added.

This preserves the approved fixed-camera appearance on actual scenery geometry, but lighting and projection are baked. Alternate viewpoints and dynamic scenery lighting require a conventional UV/material pass. Existing gameplay cards remain live 3D nodes. No bridges or damage-zone layout changes are included.

For packaged game exports, include `assets/board/*.bin` and `assets/board/*.png` in the export preset non-resource filters: these files are intentionally read directly. Runtime flow verification remains pending because two harness attempts exited without their expected result lines.
