#!/usr/bin/env python3
"""Guard the two derived architecture artefacts against silent drift (CLAUDE.md §7).

Two invariants, both of which have broken in practice:

1. **Version alignment** — `architecture.json`'s `meta.appVersion` must equal the released
   marketing version in `.release-please-manifest.json`. The rule used to say "mirror
   `CFBundleShortVersionString` from Info.plist", but that plist value is a frozen fallback the
   Build Phase overwrites from `git describe --tags`, so the docs sat on 2.0.0 while the app
   shipped 2.4.0 — a version number nobody could place.

2. **HTML/JSON sync** — `architecture.html` embeds a verbatim copy of `architecture.json` in its
   `<script id="architecture-data">` block. CLAUDE.md calls re-injecting it "the single
   most-forgotten item" of the Definition-of-Done checklist; nothing enforced it until now.

Run locally before pushing:  python3 scripts/check-doc-consistency.py

Exit codes: 0 = consistent, 1 = drift found (message says exactly what to change).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ARCH_JSON = REPO / "docs/architecture/architecture.json"
ARCH_HTML = REPO / "docs/architecture/architecture.html"
MANIFEST = REPO / ".release-please-manifest.json"

RELEASE_BRANCH = "release-please--branches--main"
RELEASE_SUBJECT = re.compile(r"^chore\(main\): release ")
EMBED = re.compile(
    r'<script id="architecture-data" type="application/json">\n([\s\S]*?)\n</script>'
)

# GitHub Actions annotations; plain prefixes when run locally.
IN_CI = os.environ.get("GITHUB_ACTIONS") == "true"


def fail(msg: str) -> None:
    print(f"::error::{msg}" if IN_CI else f"ERROR: {msg}")


def notice(msg: str) -> None:
    print(f"::notice::{msg}" if IN_CI else f"NOTE: {msg}")


def version_lag_allowed() -> bool:
    """True while a release is being cut.

    Merging the release-please PR bumps the manifest, so `architecture.json` is legitimately one
    release behind on that PR and on the merge commit that lands it. Failing there would just make
    a machine-generated PR red and block the release; the very next PR is where the bump gets
    enforced. Anywhere else, a mismatch is real drift.
    """
    if os.environ.get("GITHUB_HEAD_REF") == RELEASE_BRANCH:
        return True
    try:
        subject = subprocess.run(
            ["git", "log", "-1", "--pretty=%s"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
    return bool(RELEASE_SUBJECT.match(subject))


def check_version(arch: dict) -> bool:
    """`meta.appVersion` must equal the released version in the release-please manifest."""
    doc_version = arch.get("meta", {}).get("appVersion")
    released = json.loads(MANIFEST.read_text())["."]

    if doc_version == released:
        print(f"✅ appVersion {doc_version} matches .release-please-manifest.json")
        return True

    message = (
        f"architecture.json meta.appVersion is {doc_version!r} but the released version is "
        f"{released!r}. Set meta.appVersion to {released!r}, reset meta.docRevision to 1 "
        f"(it counts revisions within one release), update meta.lastUpdated, then re-inject the "
        f"JSON into architecture.html — see CLAUDE.md §7 'Versioning'."
    )
    if version_lag_allowed():
        notice(f"Release in flight, not failing on this. {message}")
        return True
    fail(message)
    return False


def check_html_embed() -> bool:
    """The JSON embedded in architecture.html must be a verbatim copy of architecture.json."""
    match = EMBED.search(ARCH_HTML.read_text())
    if not match:
        fail(
            "Could not find the <script id=\"architecture-data\" type=\"application/json\"> block "
            "in architecture.html — the viewer cannot render without it."
        )
        return False

    if match.group(1).strip() == ARCH_JSON.read_text().strip():
        print("✅ architecture.html embeds the current architecture.json")
        return True

    fail(
        "architecture.html embeds a stale copy of architecture.json. Re-inject it with the "
        "snippet under CLAUDE.md §7 'Architecture visualisation' (step 5) and commit both files."
    )
    return False


def main() -> int:
    for path in (ARCH_JSON, ARCH_HTML, MANIFEST):
        if not path.exists():
            fail(f"Missing required file: {path.relative_to(REPO)}")
            return 1

    try:
        arch = json.loads(ARCH_JSON.read_text())
    except json.JSONDecodeError as error:
        fail(f"architecture.json is not valid JSON: {error}")
        return 1
    print("✅ architecture.json parses")

    # Run both checks before returning, so one push surfaces every problem at once.
    ok = check_version(arch)
    ok = check_html_embed() and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
