# Five ordered art passes

Run `Blender/refine_board_five_passes.py` with Blender 4.4 in background mode from the repository root. It builds on `build_board_slabs.py` and saves cumulative 1920 x 1080 renders:

1. `01_wood.png`: warped broad grain, subtle knots and darker edges.
2. `02_riverbanks.png`: irregular stone clusters, wet stone and moss/reeds.
3. `03_vegetation.png`: varied layered foliage, visible branches and roots.
4. `04_volcanic_terrain.png`: larger fractured masses, rubble and localized red fissures.
5. `05_lighting_final.png`: neutral key with cool forest and warm volcanic fills.

`environment_final.png` hides the approximate card/hand/deck witnesses. `board_art_passes.blend` is the editable final scene with packed card textures and the original camera framing. Earlier preview directories are preserved.

Godot scenes and card placement are unchanged. This is a Cycles art study; UI, damage piles, targeting and gameplay effects are not reproduced, and materials/lighting still require conversion and runtime validation for GL Compatibility. No animation is added in these five passes.
