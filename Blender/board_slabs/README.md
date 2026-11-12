# Continuous wood slabs

Revision of `board_refined`: each playing half is one solid wooden slab, with a subtly irregular perimeter, fine grain and two edge splits on each end. Repeated plank seams and iron pins are removed. Terrain, card witnesses and camera remain identical to the prior refinement for comparison.

Rebuild using Blender 4.4 with `--background --python Blender/build_board_slabs.py` from the project root.

- `board_with_layout.png`: current camera with approximate card/deck/hand witnesses.
- `board_environment.png`: current camera without witnesses.
- `board_wider_comparison.png`: optional wider view; not applied in Godot.
- `board_slabs.blend`: editable scene, current camera, packed textures.

This remains a Cycles art preview, not an integrated or runtime-validated Godot asset. The previous renders and scenes are preserved. UI and gameplay effects are not reproduced.
