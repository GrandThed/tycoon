"""Shared loader and validator for building blueprints (INTERFACES.md "M7 contracts").

Used by tools/testfit/testfit.py (renders) and tools/assets/merge_stages.py (merges), both of
which run inside Blender's Python, so this module is stdlib only.

Path convention: tools/testfit/blueprints/<Era>/<ModelName>.json, where the file stem equals the
era config's modelName and the blueprint's "id". City-dressing props (INTERFACES.md "M9 contracts")
use the same schema under tools/testfit/blueprints/_props/<Era>/<PropName>.json; they are not slots,
so their stage count is the blueprint's own (max stage + 1).
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLUEPRINTS_ROOT = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints")
PROPS_DIRNAME = "_props"
PROPS_ROOT = os.path.join(BLUEPRINTS_ROOT, PROPS_DIRNAME)
STAGE_COUNT = 5
DEFAULT_SCALE = 4.0
DEFAULT_FOOTPRINT = (9.0, 9.0)


class BlueprintError(ValueError):
    """A blueprint that cannot be used at all (unparseable, wrong shape)."""


@dataclass
class Piece:
    kit: str
    model: str
    pos: tuple[float, float, float]
    rot_y: float
    stage: int
    index: int

    @property
    def label(self) -> str:
        return f"{self.index}:{self.model}"


@dataclass
class Blueprint:
    id: str
    era: str
    scale: float
    footprint: tuple[float, float]
    pieces: list[Piece]
    path: str
    warnings: list[str] = field(default_factory=list)

    @property
    def max_stage(self) -> int:
        return max((p.stage for p in self.pieces), default=0)

    @property
    def stage_count(self) -> int:
        return self.max_stage + 1

    @property
    def kits(self) -> list[str]:
        return sorted({p.kit for p in self.pieces})

    def pieces_at(self, stage: int) -> list[Piece]:
        """Pieces visible at a stage; stages are additive."""
        return [p for p in self.pieces if p.stage <= stage]


def blueprint_path(era: str, model: str) -> str:
    return os.path.join(BLUEPRINTS_ROOT, era, f"{model}.json")


def is_prop_blueprint(path: str) -> bool:
    """True for <anything>/_props/<Era>/<PropName>.json."""
    era_dir = os.path.dirname(os.path.abspath(path))
    return os.path.basename(os.path.dirname(era_dir)) == PROPS_DIRNAME


def list_blueprints(era: str, root: str | None = None) -> list[str]:
    folder = os.path.join(root or BLUEPRINTS_ROOT, era)
    if not os.path.isdir(folder):
        return []
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower().endswith(".json")]


def _number(value: object, what: str, default: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        if default is not None and value is None:
            return default
        raise BlueprintError(f"{what} must be a number, got {value!r}")
    return float(value)


def _vector(value: object, what: str, length: int) -> tuple[float, ...]:
    if not isinstance(value, (list, tuple)) or len(value) != length:
        raise BlueprintError(f"{what} must be a list of {length} numbers, got {value!r}")
    return tuple(_number(v, what) for v in value)


def parse_blueprint(data: object, path: str) -> Blueprint:
    """Validate a decoded JSON document. Hard errors raise; soft ones land in .warnings."""
    if not isinstance(data, dict):
        raise BlueprintError("top level is not an object")
    stem = os.path.splitext(os.path.basename(path))[0]
    warnings: list[str] = []

    bid = data.get("id")
    if not isinstance(bid, str) or not bid:
        warnings.append(f"missing id; using the file stem {stem!r}")
        bid = stem
    elif bid != stem:
        warnings.append(f"id {bid!r} does not equal the file stem {stem!r} (the file name is what the tools key on)")

    era = data.get("era")
    parent = os.path.basename(os.path.dirname(os.path.abspath(path)))
    if not isinstance(era, str) or not era:
        warnings.append(f"missing era; using the folder name {parent!r}")
        era = parent
    elif era != parent:
        warnings.append(f"era {era!r} does not equal the folder name {parent!r}")

    scale = _number(data.get("scale"), "scale", DEFAULT_SCALE)
    if scale <= 0:
        raise BlueprintError(f"scale must be positive, got {scale}")

    if "footprint" in data:
        fx, fz = _vector(data["footprint"], "footprint", 2)
        if fx <= 0 or fz <= 0:
            raise BlueprintError(f"footprint must be positive, got {data['footprint']!r}")
        footprint = (fx, fz)
    else:
        footprint = DEFAULT_FOOTPRINT

    raw_pieces = data.get("pieces")
    if not isinstance(raw_pieces, list):
        raise BlueprintError("pieces must be a list")
    pieces: list[Piece] = []
    for index, raw in enumerate(raw_pieces):
        if not isinstance(raw, dict):
            raise BlueprintError(f"piece {index} is not an object")
        kit = raw.get("kit", "")
        model = raw.get("model", "")
        if not isinstance(kit, str) or not kit or not isinstance(model, str) or not model:
            raise BlueprintError(f"piece {index} needs a kit and a model")
        pos = _vector(raw.get("pos", [0, 0, 0]), f"piece {index} pos", 3)
        rot_y = _number(raw.get("rotY", 0.0), f"piece {index} rotY")
        stage_raw = raw.get("stage", 0)
        if isinstance(stage_raw, bool) or not isinstance(stage_raw, (int, float)):
            raise BlueprintError(f"piece {index} stage must be an integer, got {stage_raw!r}")
        stage = int(stage_raw)
        if not (0 <= stage < STAGE_COUNT):
            warnings.append(f"piece {index} ({model}) has stage {stage}, clamped to 0..{STAGE_COUNT - 1}")
            stage = max(0, min(STAGE_COUNT - 1, stage))
        pieces.append(Piece(kit, model, (pos[0], pos[1], pos[2]), rot_y, stage, index))

    return Blueprint(bid, era, scale, footprint, pieces, os.path.abspath(path), warnings)


def load_blueprint(path: str) -> Blueprint:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as exc:
        raise BlueprintError(f"cannot read {path}: {exc}") from None
    except ValueError as exc:
        raise BlueprintError(f"{path} is not valid JSON: {exc}") from None
    return parse_blueprint(data, path)
