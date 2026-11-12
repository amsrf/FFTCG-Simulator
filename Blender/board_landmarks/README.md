# Composed landmarks and river entrances

Build with Blender 4.4: `Blender/build_board_landmarks.py`. Input is the approved material-refinement scene. This adds a broken basalt outcrop, a moss-covered broken gateway in the opposite biome, larger volcanic rock masses with debris, and substantial river entrance banks with two low water stones.

The current camera and deck recesses are retained. `board_with_cards.png` includes approximate layout witnesses; `board_environment.png` omits them. The live river shader is not represented in these Blender renders. `board_landmarks.blend` is now the input for `Blender/export_board_to_godot.py`, including both seat views and separate water geometry.

Landmarks are kept in perimeter corners, but full seven-damage-card and UI clearance still needs checking in the actual running game. Scenery appearance remains baked for the gameplay camera.
