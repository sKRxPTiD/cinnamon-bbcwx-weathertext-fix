#!/usr/bin/env bash
set -euo pipefail

# Portable Cinnamon BBCWX 5.4 repair for DoloWOLF, Novo, and compatible hosts.
# The script intentionally does not inspect or modify the 3.0 desklet.

readonly DESKLET_RELATIVE='bbcwx@oak-wood.co.uk/5.4/desklet.js'

if [[ -z "${HOME:-}" ]]; then
    printf 'ERROR: HOME is not set; cannot locate the user-local desklet.\n' >&2
    exit 1
fi

# When invoked with sudo, still prefer the real user's local desklet before
# falling back to the system copy.
user_home="$HOME"
if [[ -n "${SUDO_USER:-}" ]] && command -v getent >/dev/null 2>&1; then
    sudo_user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    if [[ -n "$sudo_user_home" ]]; then
        user_home="$sudo_user_home"
    fi
fi

user_target="$user_home/.local/share/cinnamon/desklets/$DESKLET_RELATIVE"
system_target="/usr/share/cinnamon/desklets/$DESKLET_RELATIVE"

if [[ -f "$user_target" ]]; then
    target="$user_target"
    target_scope='user-local'
elif [[ -f "$system_target" ]]; then
    target="$system_target"
    target_scope='system'
else
    printf 'ERROR: Could not find the Cinnamon Weather desklet at either:\n' >&2
    printf '  %s\n' "$user_target" >&2
    printf '  %s\n' "$system_target" >&2
    exit 1
fi

# Defense-in-depth: this script is only allowed to operate on the exact 5.4 path.
if [[ "$target" != */bbcwx@oak-wood.co.uk/5.4/desklet.js ]]; then
    printf 'ERROR: Refusing an unexpected target path: %s\n' "$target" >&2
    exit 1
fi

TARGET="$target" TARGET_SCOPE="$target_scope" python3 - <<'PY'
from __future__ import annotations

import datetime as dt
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path


target = Path(os.environ["TARGET"])
scope = os.environ["TARGET_SCOPE"]

if target.is_symlink() or not target.is_file():
    print(f"ERROR: Refusing a non-regular target: {target}", file=sys.stderr)
    raise SystemExit(1)

try:
    original = target.read_text(encoding="utf-8")
except UnicodeDecodeError as exc:
    print(f"ERROR: {target} is not valid UTF-8; nothing changed: {exc}", file=sys.stderr)
    raise SystemExit(1)

newline = "\r\n" if "\r\n" in original else "\n"
had_trailing_newline = original.endswith(("\n", "\r"))
lines = original.splitlines()

weather_if = re.compile(r"^(?P<indent>\s*)if\s*\(\s*this\.weathertext\s*\)\s*\{")
legacy_weather_line = re.compile(r"^\s*if\s*\(\s*this\.weathertext\s*\)\s*this\.weathertext\.style\s*=")


def block_end(start: int) -> int | None:
    """Find a simple JS brace-balanced block; weathertext blocks contain no nested braces."""
    depth = 0
    for index in range(start, len(lines)):
        depth += lines[index].count("{") - lines[index].count("}")
        if depth == 0:
            return index
    return None


candidates: list[tuple[int, int]] = []
for index, line in enumerate(lines):
    if legacy_weather_line.match(line):
        candidates.append((index, index))
        continue
    match = weather_if.match(line)
    if not match:
        continue
    end = block_end(index)
    if end is None:
        continue
    body = "\n".join(lines[index : end + 1])
    if "this.weathertext.style" in body and "this.weathertext.clutter_text" in body:
        candidates.append((index, end))

if not candidates:
    print("ERROR: No recognizable weathertext layout block was found; nothing changed.", file=sys.stderr)
    print("       The script only repairs the known Cinnamon Weather 5.4 layout.", file=sys.stderr)
    raise SystemExit(1)

# Use the first recognized block. Remove only immediately adjacent/nested copies,
# which covers the known duplicate-if variant without disturbing unrelated code.
first_start, first_end = candidates[0]
group_end = first_end
group_count = 1
for start, end in candidates[1:]:
    if start <= group_end:
        group_end = max(group_end, end)
        group_count += 1
        continue
    gap = lines[group_end + 1 : start]
    if len(gap) <= 6 and all(not item.strip() or item.lstrip().startswith("//") for item in gap):
        group_end = end
        group_count += 1
        continue
    break

indent = re.match(r"^\s*", lines[first_start]).group(0)
canonical = [
    f"{indent}if (this.weathertext) {{",
    f"{indent}  this.weathertext.style = 'text-align: center; font-size:' + BBCWX_CC_TEXT_SIZE * this.zoom + 'px; max-width:' + (170 * this.zoom) + 'px;';",
    f"{indent}  this.weathertext.clutter_text.set_line_wrap(true);",
    f"{indent}  this.weathertext.clutter_text.set_line_wrap_mode(imports.gi.Pango.WrapMode.WORD_CHAR);",
    f"{indent}}}",
]

patched_lines = lines[:first_start] + canonical + lines[group_end + 1 :]
patched = newline.join(patched_lines)
if had_trailing_newline:
    patched += newline

if patched == original:
    print(f"Target ({scope}): {target}")
    print("Already repaired; no backup or write was needed.")
    print("No 3.0 desklet was inspected or changed.")
    print("If Cinnamon is still showing the old layout, reload all desklets.")
    raise SystemExit(0)

stamp = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
backup = target.with_name(f"{target.name}.BEFORE-REPAIR-{stamp}")
suffix = 1
while backup.exists():
    backup = target.with_name(f"{target.name}.BEFORE-REPAIR-{stamp}-{suffix}")
    suffix += 1

try:
    shutil.copy2(target, backup)
    original_mode = stat.S_IMODE(target.stat().st_mode)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="", dir=target.parent, prefix=f".{target.name}.repair-", delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        temporary.write(patched)
        temporary.flush()
        os.fsync(temporary.fileno())
    os.chmod(temporary_path, original_mode)
    os.replace(temporary_path, target)
except PermissionError as exc:
    if "temporary_path" in locals() and temporary_path.exists():
        temporary_path.unlink()
    if backup.exists():
        backup.unlink()
    print(f"ERROR: Permission denied while repairing {target}: {exc}", file=sys.stderr)
    print("       Re-run the same script with sudo if this is the system copy.", file=sys.stderr)
    raise SystemExit(1)
except Exception:
    if "temporary_path" in locals() and temporary_path.exists():
        temporary_path.unlink()
    raise

print(f"Target ({scope}): {target}")
print(f"Backup: {backup}")
print("Changed: applied zoom-scaled max-width (170 * this.zoom).")
if group_count > 1:
    print(f"Changed: removed {group_count - 1} duplicate weathertext block(s).")
else:
    print("Changed: no duplicate weathertext block was present.")
print("No 3.0 desklet was inspected or changed.")
print("Next step: reload all desklets from the Cinnamon desktop context menu.")
PY
