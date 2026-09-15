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

Diagnostics from inside an expanded macro are skipped. In practice these are all SwiftData's
`#Predicate` (via `@Query`) complaining that `KeyPath` is not `Sendable` — noise nobody can act on,
since the code belongs to Apple's macro. They also have no portable source attribution: Xcode 27
reports them as `macro expansion #Predicate` plus an "expanded code originates here" note, while
Xcode 26.6 reports a mangled `@__swiftmacro_…` buffer name and emits no note at all. Dropping them
is what makes the remaining entries agree across both toolchains (35 of 36 identical; see below).

**The baseline belongs to one toolchain.** There is no compiler-independent key to normalise to:
diagnostic group tags (`[#MutableGlobalVariable]`) exist only from Xcode 27, and wording changes
between releases — Xcode 26.6 says "data races between code in the current task", Xcode 27 says
"…in the current isolation context" for the same warning. So the baseline records the Xcode it was
generated with, CI pins that same Xcode, and a mismatch is reported as a toolchain difference
rather than as new debt. Bumping the pinned Xcode means re-freezing the baseline.

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

# Which Xcode produced the log, so a toolchain change is reported as such instead of as new debt.
TOOLCHAIN = re.compile(r"/Applications/(?P<xcode>Xcode[^/]*\.app)")
BASELINE_TOOLCHAIN = re.compile(r"^# toolchain:\s*(?P<xcode>\S+)\s*$", re.MULTILINE)

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

    Matched by finding the longest suffix of the path that exists in this checkout, rather than by
    stripping a fixed prefix: the checkout root differs per machine (`/Users/runner/work/vibecoach/
    vibecoach` on CI), and the baseline is deliberately refreshed *from a downloaded CI log*, so a
    prefix-based version silently discarded every entry when run anywhere but the runner itself.
    """
    parts = Path(path).parts
    # Start at 1: parts[0] is the root ("/"), and joining an absolute path onto REPO would just
    # yield that absolute path back — which of course "exists", so every entry stayed absolute.
    for index in range(1, len(parts)):
        candidate = Path(*parts[index:])
        if (REPO / candidate).exists():
            return str(candidate)
    return None


def is_concurrency(message: str) -> bool:
    lowered = message.lower()
    return any(marker in lowered for marker in CONCURRENCY_MARKERS)


def extract(log: str) -> set[str]:
    """Normalised, deduplicated `file: message` entries for every concurrency warning in the log."""
    entries: set[str] = set()

    for line in log.splitlines():
        match = WARNING.match(line)
        if not match:
            continue

        message = SUFFIXES.sub("", match.group("msg")).strip()
        if not is_concurrency(message):
            continue

        # Not an absolute path → a macro-expansion buffer. Skipped: unactionable SwiftData
        # `#Predicate` noise, and the two toolchains disagree on how to name it at all.
        location = match.group("loc")
        if not location.startswith("/"):
            continue

        path = relativise(location)
        if path is not None:
            entries.add(f"{path}: {message}")

    return entries


def detect_toolchain(text: str) -> str | None:
    """The Xcode that produced a build log, or the one a baseline was frozen with."""
    match = TOOLCHAIN.search(text) or BASELINE_TOOLCHAIN.search(text)
    return match.group("xcode") if match else None


def read_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    return {
        line.strip()
        for line in BASELINE.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    }


def write_baseline(entries: set[str], toolchain: str | None) -> None:
    header = (
        "# Strict-concurrency warning baseline — see scripts/check-concurrency-baseline.py.\n"
        "#\n"
        "# Frozen debt, not an allowlist to grow: CI fails when an entry appears that is not\n"
        "# listed here. Entries may disappear freely; re-freeze with `--update` when they do.\n"
        "# Format: <repo-relative file>: <compiler message>, line numbers deliberately dropped.\n"
        "# Macro-expansion diagnostics (SwiftData #Predicate) are excluded — unactionable, and\n"
        "# the toolchains disagree on how to name them.\n"
        "#\n"
        "# Diagnostic wording is toolchain-specific, so this file belongs to the Xcode below —\n"
        "# the one the CI job pins. Bumping that pin means re-freezing this baseline.\n"
        f"# toolchain: {toolchain or 'unknown'}\n"
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

    log = log_path.read_text(errors="replace")
    found = extract(log)
    baseline = read_baseline()

    log_toolchain = detect_toolchain(log)
    baseline_toolchain = detect_toolchain(BASELINE.read_text()) if BASELINE.exists() else None

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
        write_baseline(found, log_toolchain)
        print(
            f"✅ Baseline re-frozen at {len(found)} entries "
            f"({log_toolchain or 'unknown toolchain'}) → {BASELINE.relative_to(REPO)}"
        )
        return 0

    added = sorted(found - baseline)
    removed = sorted(baseline - found)

    # Diagnostic wording changes between Xcode releases, so a toolchain mismatch shows up as a
    # simultaneous add+remove of the *same* warning. Say that outright — otherwise it reads as
    # "you introduced a data race" when all that happened is a compiler upgrade.
    mismatched = (
        added and removed
        and log_toolchain and baseline_toolchain
        and log_toolchain != baseline_toolchain
    )
    if mismatched:
        notice(
            f"Toolchain mismatch: this log is from {log_toolchain}, the baseline was frozen with "
            f"{baseline_toolchain}. Diagnostic wording differs between Xcode releases, so some of "
            f"the entries below are the same warnings phrased differently, not new debt. CI pins "
            f"its Xcode — compare against a CI log (the job uploads one on failure) before "
            f"concluding anything from a local run."
        )

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
