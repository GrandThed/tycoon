#!/usr/bin/env python3
"""Upload the Kenney event sounds to Roblox via Open Cloud and write the ids into Sounds.json.

Reads credentials from .env (gitignored) and the file picks from tools/audio_map.json, pulling
the audio straight out of the zips in assets/ so nothing is unpacked into the repo.

Why this is careful: Open Cloud caps audio uploads per calendar month (10 for an account that
is not ID-verified, 100 for one that is). There are nine event sounds, so an unverified account
spends almost its entire monthly budget in one run and a mistake cannot be undone. Therefore:

  * a key whose id is already non-zero in Sounds.json is never re-uploaded;
  * Sounds.json is rewritten after EVERY successful upload, so a crash, a network drop or a
    Ctrl-C can never lose an id that was already paid for;
  * --audition and --dry-run let the whole flow be rehearsed without spending anything.

Usage:
    py tools/upload_audio.py --audition        # extract picks + alternates to listen to
    py tools/upload_audio.py --dry-run         # show exactly what would upload, call nothing
    py tools/upload_audio.py                   # upload every key still at id 0
    py tools/upload_audio.py --only uiClick    # upload one key (repeatable)

Stdlib only, per the project's tooling rule.
"""

from __future__ import annotations

import argparse
import io
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = REPO_ROOT / ".env"
MAP_FILE = REPO_ROOT / "tools" / "audio_map.json"
SOUNDS_FILE = REPO_ROOT / "src" / "shared" / "Config" / "Sounds.json"
ASSETS_DIR = REPO_ROOT / "assets"
AUDITION_DIR = ASSETS_DIR / "audition"

CREATE_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{operation_id}"

# Roblox returns the asset id through a long-running operation. These bound the wait; audio
# normally resolves in a few seconds, but moderation can make it slower.
POLL_ATTEMPTS = 30
POLL_INTERVAL_SECONDS = 2.0
# Open Cloud rejects bursts; audio uploads are rare and slow anyway, so pace them politely.
UPLOAD_SPACING_SECONDS = 1.5


class UploadError(RuntimeError):
    """Any failure that should stop this key without poisoning the ones already uploaded."""


def load_env() -> dict[str, str]:
    if not ENV_FILE.exists():
        raise SystemExit(
            f"No {ENV_FILE.name} found. Copy .env.example to .env and fill it in.\n"
            "It is gitignored on purpose - never commit the key."
        )
    values: dict[str, str] = {}
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def require_credentials(env: dict[str, str]) -> tuple[str, str, str]:
    api_key = env.get("ROBLOX_API_KEY", "")
    creator_type = env.get("ROBLOX_CREATOR_TYPE", "user").lower()
    creator_id = env.get("ROBLOX_CREATOR_ID", "")
    problems = []
    if not api_key or "paste" in api_key.lower():
        problems.append("ROBLOX_API_KEY is empty or still the placeholder")
    if creator_type not in ("user", "group"):
        problems.append(f"ROBLOX_CREATOR_TYPE must be 'user' or 'group', got {creator_type!r}")
    if not creator_id.isdigit():
        problems.append("ROBLOX_CREATOR_ID must be the numeric id, digits only")
    if problems:
        raise SystemExit("Cannot upload:\n  - " + "\n  - ".join(problems))
    return api_key, creator_type, creator_id


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def set_sound_id(key: str, asset_id: int) -> None:
    """Set one sound's id in place, leaving every other byte of Sounds.json untouched.

    A json.load/json.dumps round-trip would reformat the designer's compact one-line entries
    into 60 lines of churn in a file this tool does not own. So the id is patched textually.
    Written via a temp file and os.replace so an interrupted write cannot truncate the config
    and lose an id that has already been paid for out of the monthly upload quota.
    """
    text = SOUNDS_FILE.read_text(encoding="utf-8")
    pattern = re.compile(r'("' + re.escape(key) + r'"\s*:\s*\{[^}]*?"id"\s*:\s*)(\d+)')
    text, replacements = pattern.subn(lambda m: m.group(1) + str(asset_id), text, count=1)
    if replacements != 1:
        raise UploadError(f"could not locate an id field for {key!r} in {SOUNDS_FILE.name}")
    json.loads(text)  # never leave the config unparseable, whatever the regex did
    temp = SOUNDS_FILE.with_suffix(".json.tmp")
    temp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temp, SOUNDS_FILE)


def read_from_zip(zip_name: str, inner_path: str) -> bytes:
    archive = ASSETS_DIR / zip_name
    if not archive.exists():
        raise UploadError(f"missing zip {archive}")
    with zipfile.ZipFile(archive) as zf:
        try:
            return zf.read(inner_path)
        except KeyError:
            raise UploadError(f"{inner_path!r} not found inside {zip_name}") from None


def read_loose_file(relative: str) -> bytes:
    """Ambient loops are single downloaded files under assets/, not Kenney zips."""
    path = ASSETS_DIR / relative
    if not path.exists():
        raise UploadError(f"missing file {path}")
    return path.read_bytes()


def build_multipart(payload: dict, filename: str, file_bytes: bytes) -> tuple[bytes, str]:
    """Hand-rolled multipart/form-data: the API wants a `request` JSON part and `fileContent`."""
    boundary = f"----EraCityTycoon{uuid.uuid4().hex}"
    content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    buf = io.BytesIO()

    def write(text: str) -> None:
        buf.write(text.encode("utf-8"))

    write(f"--{boundary}\r\n")
    write('Content-Disposition: form-data; name="request"\r\n')
    write("Content-Type: application/json\r\n\r\n")
    write(json.dumps(payload) + "\r\n")
    write(f"--{boundary}\r\n")
    write(f'Content-Disposition: form-data; name="fileContent"; filename="{filename}"\r\n')
    write(f"Content-Type: {content_type}\r\n\r\n")
    buf.write(file_bytes)
    write(f"\r\n--{boundary}--\r\n")
    return buf.getvalue(), f"multipart/form-data; boundary={boundary}"


def api_request(url: str, api_key: str, data: bytes | None, content_type: str | None) -> dict:
    request = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    request.add_header("x-api-key", api_key)
    if content_type:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:400]
        # Never echo the key; the body is Roblox's and safe to show.
        raise UploadError(f"HTTP {error.code} from {url.split('?')[0]}: {body}") from None
    except urllib.error.URLError as error:
        raise UploadError(f"network error contacting Roblox: {error.reason}") from None


def poll_operation(operation_path: str, api_key: str) -> int:
    operation_id = operation_path.rsplit("/", 1)[-1]
    url = OPERATION_URL.format(operation_id=operation_id)
    for attempt in range(1, POLL_ATTEMPTS + 1):
        result = api_request(url, api_key, None, None)
        if result.get("done"):
            response = result.get("response") or {}
            asset_id = response.get("assetId")
            if asset_id is None:
                raise UploadError(f"operation finished with no assetId: {result}")
            return int(asset_id)
        time.sleep(POLL_INTERVAL_SECONDS)
        if attempt % 5 == 0:
            print(f"      still processing ({attempt * POLL_INTERVAL_SECONDS:.0f}s)...")
    raise UploadError(
        "operation never completed. The upload may still succeed on Roblox's side - "
        "check create.roblox.com before re-running, or this key's slot is spent twice."
    )


def upload_one(key: str, entry: dict, creds: tuple[str, str, str]) -> int:
    api_key, creator_type, creator_id = creds
    if "file" in entry:
        filename = Path(entry["file"]).name
        file_bytes = read_loose_file(entry["file"])
        source = entry.get("source", "unknown source")
        description = f"Era City Tycoon ambient loop '{key}'. Source: {source}, CC0."
    else:
        inner = entry["pick"]
        filename = Path(inner).name
        file_bytes = read_from_zip(entry["zip"], inner)
        description = f"Era City Tycoon UI sound '{key}'. Source: Kenney ({entry['zip']}), CC0."
    creator = {"userId": creator_id} if creator_type == "user" else {"groupId": creator_id}
    payload = {
        "assetType": "Audio",
        "displayName": f"EraCityTycoon_{key}",
        "description": description,
        "creationContext": {"creator": creator},
    }
    body, content_type = build_multipart(payload, filename, file_bytes)
    print(f"      uploading {filename} ({len(file_bytes) / 1024:.0f} KB)...")
    created = api_request(CREATE_URL, api_key, body, content_type)
    operation_path = created.get("path") or created.get("operationId")
    if not operation_path:
        raise UploadError(f"no operation path in create response: {created}")
    return poll_operation(str(operation_path), api_key)


def do_audition(audio_map: dict) -> None:
    AUDITION_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for key, entry in audio_map["sounds"].items():
        target = AUDITION_DIR / key
        target.mkdir(exist_ok=True)
        candidates = [("PICK", entry["pick"])]
        candidates += [(f"alt{i + 1}", p) for i, p in enumerate(entry.get("alternates", []))]
        for label, inner in candidates:
            try:
                data = read_from_zip(entry["zip"], inner)
            except UploadError as error:
                print(f"  ! {key}/{label}: {error}")
                continue
            out = target / f"{label}__{Path(inner).name}"
            out.write_bytes(data)
            written += 1
        print(f"  {key}: {len(candidates)} files -> {target.relative_to(REPO_ROOT)}")
        print(f"      wants: {entry['wants']}")
    print(
        f"\nExtracted {written} files to {AUDITION_DIR.relative_to(REPO_ROOT)}.\n"
        "Listen, then edit `pick` in tools/audio_map.json for anything you want to change.\n"
        "Nothing has been uploaded and no upload quota has been spent."
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--audition", action="store_true", help="extract picks+alternates to listen to; uploads nothing")
    parser.add_argument("--dry-run", action="store_true", help="show what would upload; calls no API")
    parser.add_argument("--only", action="append", default=[], metavar="KEY", help="upload just this key (repeatable)")
    args = parser.parse_args()

    audio_map = read_json(MAP_FILE)
    sounds = read_json(SOUNDS_FILE)

    if args.audition:
        do_audition(audio_map)
        return 0

    # One flat key space: event sounds and era ambient loops never share a name, and each
    # key remembers which Sounds.json block it belongs to so the id lands in the right place.
    entries: dict[str, dict] = {}
    blocks: dict[str, str] = {}
    for block in ("sounds", "ambient"):
        for key, entry in audio_map.get(block, {}).items():
            entries[key] = entry
            blocks[key] = block

    unknown = [k for k in args.only if k not in entries]
    if unknown:
        raise SystemExit(f"--only names unmapped key(s): {', '.join(unknown)}")

    wanted = args.only or list(entries)
    pending = [k for k in wanted if sounds[blocks[k]].get(k, {}).get("id", 0) == 0]
    already = [k for k in wanted if k not in pending]

    if already:
        print(f"Already uploaded, skipping: {', '.join(already)}")
    if not pending:
        print("Nothing to upload - every requested key already has a non-zero id.")
        return 0

    print(f"\n{len(pending)} sound(s) to upload: {', '.join(pending)}")
    print(
        "Monthly Open Cloud audio quota: 10 uploads if the account is NOT ID-verified, 100 if it is.\n"
        "Each success is written to Sounds.json immediately, so this is safe to interrupt.\n"
    )

    if args.dry_run:
        for key in pending:
            entry = entries[key]
            source = entry["file"] if "file" in entry else f"{entry['zip']} :: {entry['pick']}"
            print(f"  would upload {key:<18} <- {source}")
        print("\nDry run: nothing uploaded, no quota spent.")
        return 0

    creds = require_credentials(load_env())
    failures: list[str] = []
    for index, key in enumerate(pending, start=1):
        entry = entries[key]
        print(f"[{index}/{len(pending)}] {key}")
        try:
            asset_id = upload_one(key, entry, creds)
        except UploadError as error:
            print(f"      FAILED: {error}")
            failures.append(key)
            continue
        # Persist immediately: an id that exists on Roblox but not in the config is a slot burned.
        set_sound_id(key, asset_id)
        print(f"      OK -> rbxassetid {asset_id} (written to Sounds.json)")
        if index < len(pending):
            time.sleep(UPLOAD_SPACING_SECONDS)

    done = len(pending) - len(failures)
    print(f"\nUploaded {done}/{len(pending)}.")
    if failures:
        print(f"Failed (still at id 0, safe to re-run): {', '.join(failures)}")
        return 1
    print(
        "All ids are in src/shared/Config/Sounds.json. Uploaded audio starts private and is\n"
        "moderated; it may be silent in Studio for a few minutes. An id that never clears\n"
        "moderation should be set back to 0 rather than left pointing at a rejected asset."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
