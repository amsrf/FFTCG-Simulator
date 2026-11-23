# Trailer

The beats, in the user's order (lines in quotes are the title cards; "quick cuts" = several short scenes with fast
transitions between them):

1. "Destroy the 7 crystals of your enemy": the opponent's crystal row.            -> `crystals`
2. "But first, you will need backup": both sides play Backups.                    -> `backups_mine`, `backups_theirs`
3. "But of course, we need swords too": Red XIII, Tifa, Orlandeau's entry + Haste. -> `forwards` (first part)
4. "Defend yourself by using your warriors to block incoming attacks": Gordon blocks, both survive. -> `block_survive`
5. "Break through your opponent's defences": quick cuts of clash WINS, one per death style.
                                                    -> `clash_toss`, `clash_pop`, `clash_tumble`
6. "Use your characters' abilities to break through": quick cuts of Orlandeau's attack lightning (`forwards`, second
   part), Alma's draw (`ab_alma`), Delita's Northswain's Strike (`break_through`, second part), Kefka's +5000
   (`ab_kefka`), Kain's -5000 drain death (`ab_kain`), Ultimecia's Time Compression (`break_through`, first part).
7. An unblocked hit breaks a crystal; "But be careful": the damage check reveals Ramuh (EX BURST); "The field is
   filled with magic and trickery!": Ramuh breaks our other Forward.             -> `hit_exburst` (split in three)
8. "Use Summons to gain advantage": quick cuts, one Summon per scene: Brynhildr, Shiva, Valefor 1-198S (tornado),
   Hecatoncheir, Odin.                    -> `sm_fire`, `sm_ice`, `sm_wind`, `sm_earth`, `sm_lightning`
9. "Help your pieces so they can help you": Titan shields our Forward from their Brynhildr. -> `titan`
10. "Fight magic with magic": the stack zig-zags player, opponent, player: our Ramuh, their Ifrit, our Summoner
    cancels Ifrit.                                                                -> `stack3`
11. The last crystals break: victory. (Name undecided: placeholder end card.)    -> `victory`

Scenes with targeting arrows use `ARROW_VIEW` (near the board view): with the camera much closer, arrows from the
stack cards started off screen.

Music: Prologue Movie from 20 s until the Forwards (its swell peaks at ~43.5 s), then Trisection. The files stay in
`~/Music/Final Fantasy Tactics (MP3).zophar/` and are never committed (Square Enix music: a public upload risks claims).

## Filming a shot

    godot --resolution 1920x1080 --fixed-fps 60 res://tools/trailer/trailer_shot.tscn -- --shot forwards --out-dir ~/.cache/fftcg_trailer_work/shots/forwards

Windowed (a real renderer), `--fixed-fps 60` so every frame is 1/60 s of game time. `--still <s>` saves one frame
(check a camera pose fast), `--every 2` a 30 fps preview, `--list` the shots. A shot = a board config, a camera path
(keys in the board camera's own terms: target, elevation, frame width, fov) and a scripted sequence (`_act_*`).
The 2D overlays and both hands are hidden while filming (the hands float in front of a camera that moves in).

Gotchas: a card whose arrival ability asks for a target stalls the script (nobody answers the prompt), so pick
Forwards without one (Cloud 1-009 / Sephiroth 1-186 were swapped out). Hold the camera still through a strong
card's entry: its camera shake restores the camera to where it was when the shake began.

## Rough cut

    python3 tools/trailer/rough_cut.py

Shots + plain title cards + music via ffmpeg (OpenH264: Fedora's ffmpeg has no x264) into
`~/.cache/fftcg_trailer_work/rough_cut.mp4`. For pacing only; the final edit is planned in Blender's sequencer.
