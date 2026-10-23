"""Runs mutate.py in several shards at once (Ben, 2026-10-22: the full run took about 13 hours on one core).

    py tools/crowd_harness/mutate_shards.py <repo root> <luau.exe> [only] [--shards N]

Each shard is one mutate.py process over a contiguous slice of the list ("from:to", its fifth argument), working in its
own copy (MUTATE_ROOT=mutant_<k>) and bundling into its own file (HARNESS_BUNDLE=bundle_<k>.luau), so they never touch
each other. `only` is mutate.py's filter, passed to every shard unchanged. The verdict is the sum of the shards'
verdicts: every shard must reach its MUTATIONS line, and a single mutation not caught fails the run, as in mutate.py.
Each shard's whole output is kept in tools/crowd_harness/mutant_logs/ for the report.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

here = Path(__file__).parent
args = [arg for arg in sys.argv[1:] if not arg.startswith("--shards")]
shards = 8
for arg in sys.argv[1:]:
    if arg.startswith("--shards="):
        shards = int(arg.split("=", 1)[1])
if len(args) < 2:
    print(__doc__)
    sys.exit(2)
repo, luau = args[0], args[1]
only = args[2] if len(args) > 2 else ""
mutate = str(here / "mutate.py")

counted = subprocess.run(
    [sys.executable, mutate, repo, luau, only], env={**os.environ, "MUTATE_COUNT": "1"}, capture_output=True, text=True
)
match = re.search(r"MUTATIONS: (\d+) entries", counted.stdout)
if match is None:
    print(f"SHARDS: mutate.py did not report its length: {counted.stdout.strip()} {counted.stderr.strip()}")
    sys.exit(2)
total = int(match.group(1))
shards = max(1, min(shards, total))
size = -(-total // shards)

logs = here / "mutant_logs"
logs.mkdir(exist_ok=True)
running = []
for k in range(shards):
    low, high = k * size, min(total, (k + 1) * size)
    if low >= high:
        break
    log = logs / f"shard_{k}.log"
    env = {**os.environ, "MUTATE_ROOT": f"mutant_{k}", "HARNESS_BUNDLE": f"bundle_{k}.luau", "PYTHONUNBUFFERED": "1"}
    handle = log.open("w", encoding="utf-8")
    process = subprocess.Popen(
        [sys.executable, mutate, repo, luau, only, f"{low}:{high}"], env=env, stdout=handle, stderr=subprocess.STDOUT
    )
    running.append((k, low, high, process, handle, log))
print(f"SHARDS: {len(running)} shards over {total} entries ({size} each), logs in {logs}")

ran = 0
not_caught: list[str] = []
broken: list[str] = []
for k, low, high, process, handle, log in running:
    process.wait()
    handle.close()
    text = log.read_text(encoding="utf-8")
    verdict = re.search(r"MUTATIONS: (\d+) run, (\d+) not caught", text)
    if verdict is None:
        last = text.strip().splitlines()[-3:] if text.strip() else ["(no output)"]
        broken.append(f"shard {k} ({low}:{high}) gave no verdict: {' | '.join(last)}")
        continue
    ran += int(verdict.group(1))
    not_caught += re.findall(r"^\s+not caught: (.+)$", text, flags=re.MULTILINE)
    print(f"  shard {k} ({low}:{high}): {verdict.group(0)}")

for line in broken:
    print("  " + line)
print(f"MUTATIONS: {ran} run, {len(not_caught)} not caught ({len(running)} shards)")
for label in not_caught:
    print("   not caught: " + label)
sys.exit(1 if not_caught or broken else 0)
