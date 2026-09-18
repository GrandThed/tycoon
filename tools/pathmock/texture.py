"""Path mock shim: the generator lives in tools/paths/texture.py (the pipeline asset), so the mock
renders exactly the texture that gets uploaded.

  "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/pathmock/texture.py <out_dir>
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "paths"))
import texture as paths_texture  # noqa: E402

if __name__ == "__main__":
    out_dir = Path(sys.argv[1])
    sys.exit(paths_texture.main(["--era", "Village", "--out-dir", str(out_dir), "--preview-dir", str(out_dir)]))
