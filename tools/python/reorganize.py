"""One-off project reorganisation: move the loose root files and group scripts/ into subfolders.

    python tools/python/reorganize.py           # dry run: prints the plan, checks every source exists
    python tools/python/reorganize.py --apply   # git mv each file (+ its .uid / .import) and rewrite res:// paths

Every move is explicit below. References are rewritten as whole paths: "res://old" becomes "res://new" only where the
path ends there (a quote, '::' for a sub-resource, or the end of the token), never as a prefix of a longer path.
"""
import os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

GROUPS = [
    # ---- scenes ----
    ("scenes/game", ["game.tscn", "board.tscn", "battle_field.tscn", "Hand.tscn", "deck.tscn", "graveyard.tscn",
                    "damage_zone.tscn", "clash_cinematic.tscn"]),
    ("scenes/cards", ["card.tscn", "card_button.tscn", "card_shards.tscn", "stack_ability_face.tscn", "target.tscn",
                     "silence_icon.tscn"]),
    ("scenes/ui", ["main_menu.tscn", "deck_editor.tscn", "deck_picker.tscn", "deck_search.tscn", "demo_menu.tscn",
                  "test_grounds_menu.tscn", "element_choice.tscn", "mana_choice.tscn", "number_choice.tscn",
                  "party_split.tscn", "skill_choice.tscn", "BigButton.tscn", "GemButton.tscn", "crystal_cost.tscn"]),
    ("scenes/vfx", ["ballistic_arrow.tscn", "crystal.tscn", "light_orb.tscn", "mana_crystal.tscn", "slam_pulse.tscn",
                   "CapsuleGX.tscn"]),
    ("scenes/previews", ["CardShatterPreview.tscn", "CrystalShardsPreview.tscn", "GemButtonPreview.tscn",
                        "LightOrbPreview.tscn", "ManaCrystalPreview.tscn"]),
    # ---- loose root scripts ----
    ("scripts/game", ["battle_field.gd", "stack.gd", "assistant.gd", "damage_zone.gd"]),
    ("scripts/cards", ["area_3d.gd", "focus_card.gd", "mesh_instance_3d.gd", "power_display.gd"]),
    ("scripts/ui", ["big_button.gd"]),
    ("scripts/vfx", ["ballistic_arrow.gd", "crystal.gd"]),
    # ---- loose root shaders / resources ----
    ("shaders", ["crystal.gdshader", "big_button.tres", "capsule.tres", "crystal.tres"]),
    ("shaders/materials", ["gem_button_metal.tres", "gem_button_stone.tres"]),
    ("assets/models", ["card.tres"]),
    # ---- scripts/ grouped ----
    ("scripts/core", ["scripts/CardDatabase.gd", "scripts/GlobalVariables.gd", "scripts/match_setup.gd",
                     "scripts/log.gd", "scripts/presentation.gd", "scripts/elements.gd", "scripts/Instruction.gd",
                     "scripts/card_filter.gd", "scripts/cost_check.gd", "scripts/test_grounds.gd"]),
    ("scripts/game", ["scripts/game.gd", "scripts/hand.gd", "scripts/deck.gd", "scripts/graveyard.gd",
                     "scripts/player_field.gd", "scripts/player_side.gd", "scripts/rules.gd", "scripts/camera_rig.gd",
                     "scripts/board_environment.gd"]),
    ("scripts/cards", ["scripts/card.gd", "scripts/card_absorb.gd", "scripts/card_area_3d.gd",
                      "scripts/card_cost_badge.gd", "scripts/card_damage_fx.gd", "scripts/card_edge.gd",
                      "scripts/card_overlap_shadow.gd", "scripts/card_shards.gd", "scripts/card_status_overlays.gd",
                      "scripts/card_target.gd", "scripts/card_teleport.gd", "scripts/card_view.gd",
                      "scripts/stack_ability_face.gd", "scripts/silence_icon.gd"]),
    ("scripts/ui", ["scripts/main_menu.gd", "scripts/deck_editor.gd", "scripts/deck_picker.gd",
                   "scripts/deck_search.gd", "scripts/demo_menu.gd", "scripts/demo_catalog.gd",
                   "scripts/demo_navigation.gd", "scripts/test_grounds_menu.gd", "scripts/element_choice.gd",
                   "scripts/mana_choice.gd", "scripts/number_choice.gd", "scripts/party_split.gd",
                   "scripts/skill_choice.gd", "scripts/gem_button.gd", "scripts/gem_button_model.gd",
                   "scripts/crystal_cost.gd"]),
    ("scripts/vfx", ["scripts/light_orb.gd", "scripts/light_orb_preview.gd", "scripts/mana_crystal.gd",
                    "scripts/payment_orb.gd", "scripts/slam_pulse.gd", "scripts/crystal_shards.gd",
                    "scripts/crystal_shards_preview.gd", "scripts/card_shatter_preview.gd",
                    "scripts/animation_batch.gd", "scripts/clash_cinematic.gd"]),
]
# Whole folders.
DIRS = {"Font": "assets/fonts"}

def plan():
    moves = []
    for dest, files in GROUPS:
        for f in files:
            moves.append((f, dest + "/" + os.path.basename(f)))
    for src, dest in DIRS.items():
        for dirpath, _, names in os.walk(os.path.join(ROOT, src)):
            for n in names:
                rel = os.path.relpath(os.path.join(dirpath, n), ROOT).replace(os.sep, "/")
                moves.append((rel, dest + rel[len(src):]))
    # Every sidecar travels with its file.
    out = []
    for src, dst in moves:
        out.append((src, dst))
        for side in (".uid", ".import"):
            if os.path.exists(os.path.join(ROOT, src + side)) and not src.endswith((".uid", ".import")):
                out.append((src + side, dst + side))
    # A folder's own sidecars were already listed by the walk: drop duplicates.
    seen, unique = set(), []
    for m in out:
        if m[0] not in seen:
            seen.add(m[0]); unique.append(m)
    return unique

def main():
    moves = plan()
    problems = [s for s, _ in moves if not os.path.exists(os.path.join(ROOT, s))]
    clashes = [d for _, d in moves if os.path.exists(os.path.join(ROOT, d))]
    loose = sorted(f for f in os.listdir(ROOT) if os.path.isfile(os.path.join(ROOT, f))
                   and f.endswith((".tscn", ".gd", ".tres", ".gdshader")) and f not in {s for s, _ in moves})
    flat = sorted("scripts/" + f for f in os.listdir(os.path.join(ROOT, "scripts"))
                  if f.endswith(".gd") and "scripts/" + f not in {s for s, _ in moves})
    print(f"{len(moves)} moves | missing sources {problems} | destination clashes {clashes}")
    print(f"still loose at the root after the move: {loose}")
    print(f"still flat in scripts/ after the move: {flat}")
    if "--apply" not in sys.argv or problems or clashes:
        return
    for src, dst in moves:
        os.makedirs(os.path.dirname(os.path.join(ROOT, dst)), exist_ok=True)
        subprocess.run(["git", "mv", src, dst], cwd=ROOT, check=True)
    # Rewrite references: whole paths only.
    mapping = {"res://" + s: "res://" + d for s, d in moves if not s.endswith((".uid", ".import"))}
    pattern = re.compile("|".join(re.escape(k) for k in sorted(mapping, key=len, reverse=True)) + r"(?![\w./-])")
    changed = 0
    for dirpath, dirnames, names in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".godot", "probe_logs", "__pycache__", "Blender"}]
        for n in names:
            if not n.endswith((".tscn", ".tres", ".gd", ".gdshader", ".godot", ".cfg", ".import", ".md", ".ps1", ".bat")):
                continue
            p = os.path.join(dirpath, n)
            raw = open(p, "rb").read()
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                continue
            new = pattern.sub(lambda m: mapping[m.group(0)], text)
            if new != text:
                open(p, "wb").write(new.encode("utf-8"))
                changed += 1
    print(f"rewrote references in {changed} files")

main()
