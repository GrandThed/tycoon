"""Write .proving.project.json: combat.project.json with Workspace.DebugProving = true.

Ben's Studio is in Spanish and adding a Workspace attribute by hand is error-prone, so the Proving
Grounds gets its own place file (build/proving.rbxl) with the switch baked in. Generated from
combat.project.json on every build so the two projects can never drift apart.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "combat.project.json"
TARGET = ROOT / ".proving.project.json"


def main() -> None:
    project = json.loads(SOURCE.read_text(encoding="utf-8"))
    combat = json.loads((ROOT / "src/shared/Config/Combat.json").read_text(encoding="utf-8"))
    attribute = combat["debug"]["provingAttribute"]
    project["name"] = project["name"] + "Proving"
    workspace = project["tree"]["Workspace"]
    workspace["$attributes"] = {attribute: True}
    TARGET.write_text(json.dumps(project, indent="\t") + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {TARGET.name} ({attribute} = true)")


if __name__ == "__main__":
    main()
