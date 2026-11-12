# Integrated terrain perimeter

Latest revision fills the lower rock gaps with a continuous red lava surface instead of narrow emissive lines. The screen-right tree's older overlapping branch sets are removed and replaced with an explicit connected trunk/fork/branch structure and attached foliage.

A continuous cooled dark ground bank now tucks beneath the lower wooden edge and covers the lava immediately beside the board. Its uneven lower boundary exposes the lava only farther down among the rocks.

The forest ground continues to Blender y=-7, beyond the camera view, with continued low ground cover. The former raised soil ribbon and separate ground box are replaced by one smooth continuous mesh, removing the straight exposed rear edge within the grass. Its board-facing edge and the camera remain fixed.

Build: run `Blender/build_board_terrain_join.py` in Blender 4.4 background mode. Input is the tightened shallow-tray scene in `board_deck_trays/board_deck_trays.blend`.

Adds a continuous soil bed, low irregular moss patches meeting the upper wooden edge, and broad basalt shelves overlapping the lower edge. Removed the disconnected decorative roots after visual feedback. Corner caps tie these joins into the side scenery. Deck recesses and card positions remain unchanged. Overlaps stay at the outer perimeter.

`terrain_join_with_cards.png` and `terrain_join_environment.png` show the same current camera. `board_terrain_join.blend` retains the layout witnesses and packed textures. This is a Blender preview; no Godot scene or runtime material is modified.
