"""Animate a Tripo character with the Quaternius Universal Animation Library (CC0).

    py tools/anim/animate.py catalogue
        Measure every library clip (length, contact moment, drift) into tools/anim/ual_clips.json and
        regenerate tools/anim/CLIPS.md. Run once per library version.

    py tools/anim/animate.py build <character.glb> --role <role> [--name N] [--out DIR] [--no-render]
        Retarget the role's clips (tools/anim/roles.json) onto the character, retime every attack so
        its contact lands on the game's windup (src/shared/Config/ProvingGrounds.json), self-check,
        export (<name>_rig.glb, <name>_all.glb, <name>_<slot>.fbx, report.json) and render a contact
        sheet and one GIF per slot. Output defaults to assets/anim/<name>/ (gitignored).

    py tools/anim/animate.py build <character.glb> --clips Sword_Attack,Roll [...]
        Ad-hoc clips with no role (no retiming).

The character must come from Tripo with the Mixamo skeleton preset, resting in a T-pose. Needs Blender
5.2; the sheet and GIFs need Pillow (run without a shebang so `py` picks the Python that has it).
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "anim")
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
CLIPS_JSON = os.path.join(HERE, "ual_clips.json")
CLIPS_MD = os.path.join(HERE, "CLIPS.md")
ROLES = os.path.join(HERE, "roles.json")
COMBAT = os.path.join(ROOT, "src", "shared", "Config", "ProvingGrounds.json")

# Self-check limits, as a share of the character's height.
SINK_LIMIT = 0.03
DRIFT_LIMIT = 0.08
# Clips that leave the spot or the floor by design.
MOVES_BY_DESIGN = re.compile(r"Death|Roll|Jump|Sitting|Swim|Driving|Crouch|Fixing|PickUp")

# What each Standard clip is good for here; anything unlisted is not combat material.
NOTES = {
    "Sword_Attack": "one-hand diagonal overhead cut, steps in; the only weapon attack in Standard",
    "Sword_Idle": "melee guard stance, weapon low in the right hand",
    "Punch_Jab": "quick lead-hand jab, guard up; unarmed only",
    "Punch_Cross": "rear-hand cross with a step; unarmed only",
    "Spell_Simple_Shoot": "one-arm forward release; stand-in for throws, lobs, casts",
    "Spell_Simple_Enter": "raise a hand to cast",
    "Spell_Simple_Idle_Loop": "hand held up, casting",
    "Spell_Simple_Exit": "lower the casting hand",
    "Pistol_Shoot": "two-hand aimed shot with recoil; marksman release",
    "Pistol_Aim_Neutral": "two-hand aim held level; marksman lock",
    "Pistol_Aim_Up": "two-hand aim held up",
    "Pistol_Aim_Down": "two-hand aim held down",
    "Pistol_Idle_Loop": "relaxed stance with a held gun",
    "Pistol_Reload": "reload with both hands",
    "Hit_Chest": "short recoil from a body hit",
    "Hit_Head": "head snaps back; headshot reaction",
    "Death01": "falls back and lies still",
    "Roll": "forward roll; a dodge",
    "Idle_Loop": "neutral breathing idle",
    "Walk_Loop": "in-place walk",
    "Jog_Fwd_Loop": "in-place jog; chase",
    "Sprint_Loop": "in-place sprint; charge travel",
    "Jump_Start": "jump take-off",
    "Jump_Loop": "airborne",
    "Jump_Land": "landing; could end a leap slam",
    "Idle_Torch_Loop": "idle holding a torch up",
    "Crouch_Idle_Loop": "crouched idle; ambush",
    "Crouch_Fwd_Loop": "crouched walk; sneaking",
    "Push_Loop": "pushing something heavy",
    "Interact": "reach out and use something",
}


def blender():
    exe = os.environ.get("BLENDER", DEFAULT_BLENDER)
    if not os.path.exists(exe):
        sys.exit(f"Blender not found at {exe}; set BLENDER")
    return exe


def library_path(given):
    if given:
        return given
    hits = glob.glob(os.path.join(ROOT, "assets", "**", "UAL1_Standard.glb"), recursive=True)
    hits = [h for h in hits if "_RM" not in os.path.basename(h)]  # root-motion copies drift by design
    if not hits:
        sys.exit("UAL1_Standard.glb not found under assets/; pass --library")
    return hits[0]


def run_blender(job):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(job, f)
        path = f.name
    try:
        proc = subprocess.run([blender(), "-b", "--python", os.path.join(HERE, "ual_blender.py"), "--", path],
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
    finally:
        os.unlink(path)
    lines = proc.stdout.splitlines()
    for ln in lines:
        if ln.startswith(("ANIM-", "Traceback")) or "Error" in ln:
            print(ln)
    if not any(ln.startswith("ANIM-DONE") for ln in lines):
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-25:])
        sys.exit(f"Blender did not finish:\n{tail}")


def catalogue(args):
    run_blender({"mode": "catalogue", "library": library_path(args.library), "out": CLIPS_JSON})
    clips = json.load(open(CLIPS_JSON, encoding="utf-8"))
    rows = ["# Universal Animation Library (Standard) clip catalogue", "",
            "Generated by `py tools/anim/animate.py catalogue`; do not edit by hand (notes live in `NOTES` in",
            "`animate.py`). Times are seconds of the source clip. **Contact** is the moment of peak hand speed",
            "relative to the pelvis: where a swing, punch, throw or shot releases, and the point a retime pins",
            "to the game's windup. **Travel** is how far the pelvis wanders (in-place clips stay near 0).",
            "Library rig height is about 1.65.", "",
            "| Clip | Seconds | Contact | Hand | Travel | Use |", "|---|---:|---:|:-:|---:|---|"]
    for c in clips:
        rows.append(f"| {c['clip']} | {c['seconds']:.2f} | {c['contact']:.2f} | {c['hand']} | "
                    f"{c['pelvisTravel']:.2f} | {NOTES.get(c['clip'], '')} |")
    open(CLIPS_MD, "w", encoding="utf-8", newline="\n").write("\n".join(rows) + "\n")
    print(f"catalogue: {len(clips)} clips -> {os.path.relpath(CLIPS_JSON, ROOT)}, {os.path.relpath(CLIPS_MD, ROOT)}")


def role_entries(role_name):
    roles = json.load(open(ROLES, encoding="utf-8"))
    if role_name not in roles["roles"]:
        sys.exit(f"unknown role {role_name}; roles: {', '.join(roles['roles'])}")
    role = roles["roles"][role_name]
    kinds = json.load(open(COMBAT, encoding="utf-8"))["crowd"]["kinds"]
    attacks = kinds[role["kind"]]["attacks"]
    measured = {c["clip"]: c for c in json.load(open(CLIPS_JSON, encoding="utf-8"))}
    slots = dict(role["slots"])
    for k, v in roles["common"].items():
        slots.setdefault(k, v)
    entries = []
    for slot, spec in slots.items():
        e = {"slot": slot, "clip": spec["clip"], "loop": bool(spec.get("loop"))}
        if "attack" in spec:
            a = attacks[spec["attack"]]
            e["windup"] = a["windup"]
            e["contact"] = spec.get("contact", measured[spec["clip"]]["contact"])
            e["shape"] = a["shape"]
        if "lead" in spec:
            e["lead"] = spec["lead"]
        if "gap" in spec:
            e["gap"] = spec["gap"]
        entries.append(e)
    return entries, role.get("placeholder", "none")


def compose(out, report):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow missing in this Python: frames are in", os.path.join(out, "frames"), "(no sheet or GIFs)")
        return
    size, per_row = (280, 180), 6
    clips = [r["slot"] for r in report["clips"]]
    sheet = Image.new("RGB", (size[0] * per_row, size[1] * len(clips)), (30, 30, 34))
    draw = ImageDraw.Draw(sheet)
    gif_ms = round(2000 / report["fps"])  # every second frame is rendered
    for r, slot in enumerate(clips):
        folder = os.path.join(out, "frames", slot)
        files = sorted(os.listdir(folder))
        pick = [files[round(i * (len(files) - 1) / (per_row - 1))] for i in range(per_row)] if len(files) > 1 else files
        for k, fn in enumerate(pick):
            im = Image.open(os.path.join(folder, fn)).convert("RGB").resize(size)
            sheet.paste(im, (k * size[0], r * size[1]))
            draw.text((k * size[0] + 5, r * size[1] + 5), f"{slot} f{fn[:3]}", fill=(255, 255, 255))
        frames = [Image.open(os.path.join(folder, fn)).convert("RGB") for fn in files]
        frames[0].save(os.path.join(out, f"{slot}.gif"), save_all=True, append_images=frames[1:],
                       duration=gif_ms, loop=0)
    sheet.save(os.path.join(out, "sheet.png"))


def build(args):
    if not os.path.exists(CLIPS_JSON):
        sys.exit("run `py tools/anim/animate.py catalogue` first")
    name = args.name or re.sub(r"[^A-Za-z0-9]+", "_", os.path.splitext(os.path.basename(args.character))[0]).strip("_")
    out = os.path.abspath(args.out or os.path.join(ROOT, "assets", "anim", name))
    if args.role:
        entries, placeholder = role_entries(args.role)
    elif args.clips:
        entries = [{"slot": c, "clip": c, "loop": c.endswith("_Loop")} for c in args.clips.split(",")]
        placeholder = "hammer"
    else:
        sys.exit("give --role or --clips")
    run_blender({"mode": "build", "library": library_path(args.library), "character": os.path.abspath(args.character),
                 "out": out, "name": name, "role": args.role, "clips": entries, "render": not args.no_render,
                 "placeholder": args.placeholder or placeholder, "fps": 30})
    report = json.load(open(os.path.join(out, "report.json"), encoding="utf-8"))
    if not args.no_render:
        compose(out, report)

    print(f"\n{name}: {report['bones']} bones, {report['triangles']} triangles, height {report['height']}")
    print(f"{'slot':<16}{'clip':<20}{'sec':>6}  timing")
    gaps = {e["slot"]: e.get("gap") for e in entries}
    flags = []
    for c in report["clips"]:
        timing = ("loop" if c["loop"] else "")
        if c.get("windup") is not None:
            timing = f"contact at {c['windup']:.2f} s = windup" + (f" (lead-in {c['lead']})" if c.get("lead") else "")
        print(f"{c['slot']:<16}{c['clip']:<20}{c['seconds']:>6.2f}  {timing}")
        if not MOVES_BY_DESIGN.search(c["clip"]):
            if c["sinkStuds"] > SINK_LIMIT:
                flags.append(f"{c['slot']}: feet sink {c['sinkStuds']:.0%} of height below the floor")
            if c["drift"] > DRIFT_LIMIT:
                flags.append(f"{c['slot']}: hips wander {c['drift']:.0%} of height from the spot")
    for slot, gap in gaps.items():
        if gap:
            flags.append(f"{slot}: stand-in clip ({gap})")
    print("\nCHECK", "clean" if not flags else "")
    for f in flags:
        print("  -", f)
    print(f"\noutput: {out}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("catalogue")
    c.add_argument("--library")
    b = sub.add_parser("build")
    b.add_argument("character")
    b.add_argument("--role")
    b.add_argument("--clips")
    b.add_argument("--name")
    b.add_argument("--out")
    b.add_argument("--library")
    b.add_argument("--placeholder", choices=["hammer", "none"])
    b.add_argument("--no-render", action="store_true")
    args = p.parse_args()
    catalogue(args) if args.cmd == "catalogue" else build(args)


if __name__ == "__main__":
    main()
