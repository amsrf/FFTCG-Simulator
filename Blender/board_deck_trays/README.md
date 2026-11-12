# Recessed deck trays

Revision: tightened footprint to .66 x .95 units (previously .86 x 1.10), reduced nominal cut depth to .025 units (previously .125), and lightened the floor to 85% of the wood color. Narrow softened lip replaces the broad rounded margin.

Two actual Boolean pockets cut into the continuous wooden slabs, with rounded corners, softened lips and darker wooden floors. Built from the saved `board_art_passes/board_art_passes.blend` by `../build_deck_trays.py`.

The recesses align to the projected deck centres at table height using the existing camera. Existing deck placeholders float above the tabletop; their transforms are preserved. Final game integration must reconcile physical deck height and recess placement.

`deck_trays_with_cards.png` shows the layout; `deck_trays_environment.png` exposes both pockets. `board_deck_trays.blend` is the editable preview with card textures packed. No Godot scenes or gameplay positions are changed.
