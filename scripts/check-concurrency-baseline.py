#!/usr/bin/env python3
"""Freeze the strict-concurrency warning debt so it can shrink but never grow (ROADMAP 63.5).

`SWIFT_STRICT_CONCURRENCY = complete` is set project-wide (story 62.6), but in Swift 5 language
mode the checker emits *warnings*, so the build stays green no matter how much new actor-isolation
debt a PR adds. Flipping to `SWIFT_VERSION = 6.0` would turn every one of them into a hard error at
once — that is the deferred Swift 6 migration epic, not something a guard can do.

So instead: extract the concurrency diagnostics from an `xcodebuild` log, normalise them, and
compare against a checked-in baseline. New entries fail the build; disappearing entries pass with a
nudge to re-freeze.

Normalisation drops the line:column, keeping `<repo-relative file>: <message>`, because an exact
`file:line` baseline is brittle — inserting a line at the top of a file would "move" every
diagnostic below it and read as a wall of new debt. The file plus the compiler's own wording is
specific enough to point at the problem and stable enough to survive unrelated edits.

Entries are deduplicated rather than counted: Swift emits the same diagnostic from both the
`SwiftEmitModule` and `SwiftCompile` phases, and *which* diagnostics get double-reported depends on
whether they sit in a declaration signature or a body. Counts would wobble between runs for reasons
that have nothing to do with the code.

Usage:
    python3 scripts/check-concurrency-baseline.py <build.log>            # compare (CI + local)
    python3 scripts/check-concurrency-baseline.py <build.log> --update   # re-freeze the baseline

To produce a log locally (a *clean* build — an incremental one re-emits nothing for untouched
files, see the empty-result guard below):

    xcodebuild build-for-testing -project AIFitnessCoach.xcodeproj -scheme AIFitnessCoach \\
      -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/cg \\
      CODE_SIGNING_ALLOWED=NO > /tmp/build.log 2>&1

Exit codes: 0 = no new debt, 1 = new diagnostics (or an unusable log).
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BASELINE = REPO / "ci/concurrency-baseline.txt"

# `<location>:<line>:<col>: warning: <message>`. The location is usually an absolute source path,
# but for diagnostics inside an expanded macro it is a pseudo-file ("macro expansion #Predicate").
WARNING = re.compile(r"^(?P<loc>.+?):(?P<line>\d+):(?P<col>\d+): warning: (?P<msg>.+)$")

# Swift points macro diagnostics back at the call site on the line right after the warning.
ORIGINATES = re.compile(r"^\s*`?-?\s*(?P<path>/.+?):\d+:\d+: note: expanded code originates here")

# Only concurrency diagnostics belong in this baseline; an unrelated deprecation warning appearing
# later must not silently inherit the guard (or pollute the debt list).
CONCURRENCY_MARKERS = (
    "concurrency-safe",
    "sendable",
    "actor-isolated",
    "actor isolated",
    "data race",
    "global actor",
    "nonisolated",
    "'sending'",
    "sending '",
    "isolated closure",
    "isolation",
)

# Trailing noise the compiler appends to most concurrency warnings. Dropping it keeps the baseline
# readable; the diagnostic group tag ("[#MutableGlobalVariable]") is dropped for the same reason.
SUFFIXES = re.compile(r"; this is an error in the Swift 6 language mode|\s*\[#[^\]]+\]$")

IN_CI = os.environ.get("GITHUB_ACTIONS") == "true"


def fail(msg: str) -> None:
    print(f"::error::{msg}" if IN_CI else f"ERROR: {msg}")


def notice(msg: str) -> None:
    print(f"::notice::{msg}" if IN_CI else f"NOTE: {msg}")


def relativise(path: str) -> str | None:
    """Repo-relative path, or None for anything outside the repo (SDK headers, DerivedData).

    Absolute paths differ between a local checkout and a CI runner, so an entry that cannot be made
    repo-relative is not ours and would never match the baseline anyway.
    """
    try:
        return str(Path(path).resolve().relative_to(REPO))
    except ValueError:
        return None


def is_concurrency(message: str) -> bool:
    lowered = message.lower()
    return any(marker in lowered for marker in CONCURRENCY_MARKERS)


def extract(log: str) -> set[str]:
    """Normalised, deduplicated `file: message` entries for every concurrency warning in the log."""
    lines = log.splitlines()
    entries: set[str] = set()

    for index, line in enumerate(lines):
        match = WARNING.match(line)
        if not match:
            continue

        message = SUFFIXES.sub("", match.group("msg")).strip()
        if not is_concurrency(message):
            continue

        location = match.group("loc")
        if location.startswith("/"):
            path = relativise(location)
        else:
            # A macro expansion: attribute it to the call site named on the following line, and
            # keep the pseudo-file as a prefix so the entry still says where the code came from.
            # Without this, every #Predicate warning in the project would collapse into a single
            # fileless entry and a new one in a new file would slip through unnoticed.
            origin = next(
                (ORIGINATES.match(lines[i]) for i in range(index + 1, min(index + 3, len(lines)))
                 if ORIGINATES.match(lines[i])),
                None,
            )
            if origin is None:
                continue
            path = relativise(origin.group("path"))
            message = f"[{location}] {message}"

        if path is not None:
            entries.add(f"{path}: {message}")

    return entries


def read_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    return {
        line.strip()
        for line in BASELINE.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    }


def write_baseline(entries: set[str]) -> None:
    header = (
        "# Strict-concurrency warning baseline — see scripts/check-concurrency-baseline.py.\n"
        "#\n"
        "# Frozen debt, not an allowlist to grow: CI fails when an entry appears that is not\n"
        "# listed here. Entries may disappear freely; re-freeze with `--update` when they do.\n"
        "# Format: <repo-relative file>: <compiler message>, line numbers deliberately dropped.\n"
        "#\n"
        f"# Entries: {len(entries)}\n"
    )
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    BASELINE.write_text(header + "\n".join(sorted(entries)) + "\n")


def summarise(title: str, entries: list[str]) -> None:
    """Append to the GitHub job summary so a failure is readable without opening the raw log."""
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    body = "\n".join(f"- `{entry}`" for entry in entries)
    with open(summary_path, "a", encoding="utf-8") as handle:
        handle.write(f"### {title}\n\n{body}\n\n")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    update = "--update" in sys.argv[1:]

    if len(args) != 1:
        fail("Usage: check-concurrency-baseline.py <build.log> [--update]")
        return 1

    log_path = Path(args[0])
    if not log_path.exists():
        fail(f"Build log not found: {log_path}")
        return 1

    found = extract(log_path.read_text(errors="replace"))
    baseline = read_baseline()

    # An incremental build re-emits nothing for untouched files, which would look like the debt
    # vanished and pass the guard for entirely the wrong reason. Treat a total wipe-out as a broken
    # log rather than a clean bill of health.
    if not found and baseline:
        fail(
            f"No concurrency diagnostics found in {log_path}, but the baseline lists "
            f"{len(baseline)}. That almost always means the log came from an incremental build "
            f"(warnings are only re-emitted for recompiled files) or the build failed early. "
            f"Rebuild with a fresh -derivedDataPath."
        )
        return 1

    if update:
        write_baseline(found)
        print(f"✅ Baseline re-frozen at {len(found)} entries → {BASELINE.relative_to(REPO)}")
        return 0

    added = sorted(found - baseline)
    removed = sorted(baseline - found)

    if removed:
        notice(
            f"{len(removed)} concurrency warning(s) are gone — nice. Re-freeze the baseline with "
            f"`python3 scripts/check-concurrency-baseline.py <build.log> --update` so the guard "
            f"tightens around the new, smaller debt."
        )
        for entry in removed:
            print(f"  - {entry}")

    if added:
        fail(
            f"{len(added)} new strict-concurrency warning(s) not in "
            f"{BASELINE.relative_to(REPO)}. Fix them, or — if the isolation is genuinely correct "
            f"and the compiler cannot see it — re-freeze the baseline deliberately and say why in "
            f"the PR."
        )
        for entry in added:
            print(f"  + {entry}")
        summarise(f"{len(added)} new concurrency warning(s)", added)
        return 1

    print(f"✅ No new concurrency warnings ({len(found)} known, baseline {len(baseline)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
