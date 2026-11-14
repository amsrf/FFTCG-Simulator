# Button stations mock-up

Built by `../build_button_housing.py` from `board_landmarks/board_landmarks.blend` (which is not modified).

Each player has a station set into their slab corner. It has a large disc for "go forward" (Pass / Next Phase /
Confirm / Declare) and a small one for Cancel / No Block. A disc is a coin on an axle along the station's local X:
the +Z face is the lit gem and the −Z face is carved stone, so a half turn switches a button off. The two drums are
joined by a stone web, so no wood shows between them. A glow disc fills each well, so nothing shows through the gap
around a disc.

| | player (volcanic, bottom-right) | opponent (forest, top-left) |
|---|---|---|
| housing | basalt, iron rings | mossy stone, bronze rings |
| glow under the discs | lava orange | emerald |
| forward gem | teal ▶ | violet ▶ (points the opponent's way) |
| Cancel | red ✕ | always on its stone face |

The opponent's station is the player's station turned π about Z through (0, −0.30), the same turn that
`export_board_to_godot.py --seat2` applies to the biomes. Scenery under a station, or overlapping a well, is hidden;
scenery that only touches a station is kept.

Renders:
- `full_player_prompt.png`: whole board; both of the player's discs lit, the opponent's dark.
- `full_opponent_priority.png`: whole board; the player's discs dark, the opponent's forward disc lit.
- `player_a_both_active.png`, `player_b_forward_only.png`, `player_c_both_off.png`, `player_d_mid_flip.png`
- `opponent_priority.png`, `opponent_off.png`

This is a look and placement study only; nothing is exported to Godot yet.
