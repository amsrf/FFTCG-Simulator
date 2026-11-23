#!/usr/bin/env python3
"""ROUGH CUT of the trailer: shots (frame folders from trailer_shot.tscn) + plain title cards + the music, assembled
with ffmpeg. This is for judging PACING; the final edit (camera-cut timing, speed ramps, sound) is planned in
Blender's sequencer.

    python3 tools/trailer/rough_cut.py [--work ~/.cache/fftcg_trailer_work] [--out rough_cut.mp4]

Music: Prologue Movie from 20 s until the cut to Trisection, which lands where the Forwards start (the Prologue's
swell peaks at ~43.5 s). The music files stay where the user keeps them (not in the repo).
"""
import argparse, os, subprocess, tempfile

MUSIC_DIR = os.path.expanduser("~/Music/Final Fantasy Tactics (MP3).zophar")
PROLOGUE = os.path.join(MUSIC_DIR, "106 Prologue Movie.mp3")
TRISECTION = os.path.join(MUSIC_DIR, "109 Trisection.mp3")
PROLOGUE_START = 20.0
FONT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "fonts", "FOT-NewRodin Pro EB.otf")
FPS = 60
# Fedora's ffmpeg has no libx264; OpenH264 plays everywhere and is good enough for a pacing check.
VIDEO_CODEC = ["-c:v", "libopenh264", "-b:v", "16M", "-pix_fmt", "yuv420p"]

# (kind, value, seconds[, start]). A shot plays `seconds` from `start` (seconds into its take), so one continuous take
# can be cut into several beats (hit_exburst = shots 6, 7 and 8). The Prologue plays until the "switch"; Trisection
# from there.
TIMELINE = [
    ("title", "Destroy the 7 crystals of your enemy", 3.5),
    ("shot", "crystals", 8.0),
    ("title", "But first, you will need backup", 2.5),
    ("shot", "backups_mine", 5.0),
    ("shot", "backups_theirs", 5.0),
    ("switch", "trisection", 0.0),
    ("title", "But of course, we need swords too", 2.5),
    ("shot", "forwards", 9.2, 0.0),             # Red XIII, Tifa, Orlandeau's entry and Haste
    ("title", "Defend yourself by using your warriors to block incoming attacks", 3.0),
    ("shot", "block_survive", 12.0, 0.2),
    ("title", "Break through your opponent's defences", 2.5),
    ("shot", "clash_toss", 3.6, 4.1),           # quick cuts: three clash wins, three deaths
    ("shot", "clash_pop", 3.6, 4.1),
    ("shot", "clash_tumble", 3.6, 4.1),
    ("title", "Use your characters' abilities to break through", 3.0),
    ("shot", "forwards", 5.3, 10.0),             # Orlandeau's attack: lightning on the whole row
    ("shot", "ab_alma", 6.0),                   # Alma draws (the water splash)
    ("shot", "break_through", 8.5, 5.6),        # Delita's Northswain's Strike
    ("shot", "ab_kefka", 5.0),                  # Kefka: +5000
    ("shot", "ab_kain", 7.0),                   # Kain: -5000, the drain death
    ("shot", "break_through", 4.8, 0.6),        # Ultimecia's Time Compression
    ("shot", "hit_exburst", 3.4, 0.0),
    ("title", "But be careful", 2.0),
    ("shot", "hit_exburst", 3.0, 3.4),
    ("title", "The field is filled with magic and trickery!", 2.5),
    ("shot", "hit_exburst", 4.4, 6.4),
    ("title", "Use Summons to gain advantage", 2.5),
    ("shot", "sm_fire", 5.0),                   # quick cuts: one Summon per scene
    ("shot", "sm_ice", 4.5),
    ("shot", "sm_wind", 6.0),
    ("shot", "sm_earth", 5.5),
    ("shot", "sm_lightning", 4.8),
    ("title", "Help your pieces so they can help you", 2.5),
    ("shot", "titan", 8.6),
    ("title", "Fight magic with magic", 2.5),
    ("shot", "stack3", 12.0),
    ("shot", "victory", 13.0),
    ("title", "[ NAME ]", 3.0),
]




def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def title_clip(text, seconds, path):
    font = os.path.abspath(FONT).replace(":", r"\:")
    fade = 0.35
    size = 64 if len(text) < 40 else 48
    # The text goes through a FILE: quoting it inline mangles apostrophes and colons.
    text_file = path + ".txt"
    with open(text_file, "w") as f:
        f.write(text)
    draw = (f"drawtext=fontfile='{font}':textfile='{text_file}':fontcolor=white:fontsize={size}:"
            f"x=(w-text_w)/2:y=(h-text_h)/2,"
            f"fade=t=in:st=0:d={fade},fade=t=out:st={seconds - fade}:d={fade}")
    run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=c=black:s=1920x1080:r={FPS}:d={seconds}",
         "-vf", draw, *VIDEO_CODEC, path])


def shot_clip(folder, seconds, path, start=0.0):
    available = len([f for f in os.listdir(folder) if f.startswith("f_")]) / FPS
    seconds = min(seconds, available - start)
    run(["ffmpeg", "-y", "-framerate", str(FPS), "-start_number", str(int(round(start * FPS))),
         "-i", os.path.join(folder, "f_%04d.png"), "-t", str(seconds), *VIDEO_CODEC, path])
    return seconds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default=os.path.expanduser("~/.cache/fftcg_trailer_work"))
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    out = a.out or os.path.join(a.work, "rough_cut.mp4")
    tmp = tempfile.mkdtemp(dir=a.work)
    clips, t, switch_at = [], 0.0, None
    for i, entry in enumerate(TIMELINE):
        kind, value, seconds = entry[0], entry[1], entry[2]
        start = entry[3] if len(entry) > 3 else 0.0
        if kind == "switch":
            switch_at = t
            continue
        path = os.path.join(tmp, f"{i:02d}.mp4")
        if kind == "title":
            title_clip(value, seconds, path)
        else:
            # Final takes live in takes/ (a fresh folder per take, so no stale frames from a longer old take); shots/
            # holds the earlier ones.
            folder = next(os.path.join(a.work, d, value) for d in ("takes7", "takes6", "takes5", "takes4", "takes3", "takes2", "takes", "shots")
                          if os.path.isdir(os.path.join(a.work, d, value)))
            seconds = shot_clip(folder, seconds, path, start)
        clips.append(path)
        t += seconds
    total = t
    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{c}'\n" for c in clips)
    video = os.path.join(tmp, "video.mp4")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", video])
    # Music: Prologue from 20 s up to the switch, then Trisection from its start; a 0.1 s fade on the join, a fade out.
    pro = switch_at
    tri = total - switch_at
    audio = (f"[1:a]atrim=start={PROLOGUE_START}:duration={pro},asetpts=PTS-STARTPTS,afade=t=out:st={pro - 0.1}:d=0.1[a1];"
             f"[2:a]atrim=start=0:duration={tri},asetpts=PTS-STARTPTS,afade=t=out:st={tri - 1.0}:d=1.0[a2];"
             f"[a1][a2]concat=n=2:v=0:a=1[a]")
    # Trisection loops if the cut outlasts it (150 s): a long rough cut must not lose its end to a short track.
    run(["ffmpeg", "-y", "-i", video, "-i", PROLOGUE, "-stream_loop", "-1", "-i", TRISECTION, "-filter_complex", audio,
         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out])
    print(f"rough cut: {total:.1f} s (Prologue {PROLOGUE_START:.0f}-{PROLOGUE_START + pro:.1f} s, then Trisection 0-{tri:.1f} s) -> {out}")


if __name__ == "__main__":
    main()
