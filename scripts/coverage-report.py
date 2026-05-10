#!/usr/bin/env python3
"""Genereert een per-directory coverage-rapport uit `xcrun xccov view --report --json`.

Achtergrond: `xccov --report` geeft één enkel target-percentage waarin Views
(die alleen door UI-tests gedekt worden) de denominator zwaar drukken. Dat
maskeert het feitelijke unit-test-bereik op Services/Models/ViewModels.

Dit script splitst de dekking op per top-level directory onder
`AIFitnessCoach/` en rapporteert per bundle apart + een combined-aggregaat
zodat de bijdrage van unit-tests vs UI-tests zichtbaar is.

Gebruik:
    xcrun xccov view --report --json UnitTests.xcresult > unit.json
    xcrun xccov view --report --json UITests.xcresult > ui.json
    python3 scripts/coverage-report.py coverage.md \\
        unit-tests=unit.json ui-tests=ui.json

Eén bundle is ook prima:
    python3 scripts/coverage-report.py coverage.md unit-tests=unit.json
"""

import json
import sys
from collections import defaultdict


def parse_bundle(json_path: str) -> dict[str, dict[str, int]]:
    """Lees xccov-JSON en retourneer per-file dict (path → {covered, total})."""
    with open(json_path) as fh:
        data = json.load(fh)
    app = next(
        (t for t in data["targets"] if t["name"].endswith(".app")), None
    )
    if app is None:
        return {}
    file_cov: dict[str, dict[str, int]] = {}
    for f in app["files"]:
        path = f.get("path", "")
        if "/AIFitnessCoach/" not in path:
            continue
        file_cov[path] = {
            "covered": f["coveredLines"],
            "total": f["executableLines"],
        }
    return file_cov


def aggregate_by_dir(
    file_cov: dict[str, dict[str, int]],
) -> dict[str, dict[str, int]]:
    """Groepeer per top-level directory onder `AIFitnessCoach/`."""
    groups: dict[str, dict[str, int]] = defaultdict(
        lambda: {"covered": 0, "total": 0, "files": 0}
    )
    for path, cov in file_cov.items():
        rel = path.split("/AIFitnessCoach/", 1)[1]
        parts = rel.split("/")
        dir_name = parts[0] if len(parts) > 1 else "root"
        g = groups[dir_name]
        g["covered"] += cov["covered"]
        g["total"] += cov["total"]
        g["files"] += 1
    return dict(groups)


def merge_files_max(
    bundles: list[dict[str, dict[str, int]]],
) -> dict[str, dict[str, int]]:
    """Per file: neem de max-covered over alle bundles.

    Approximatie: als zowel unit-tests als UI-tests een file deels dekken,
    nemen we de hoogste dekking. Dat is een **bovengrens** als beide suites
    verschillende regels dekken (typisch: Services via unit, Views via UI),
    en exact wanneer één suite de file niet raakt. Voor onze gebruiksdoel-
    einden goed genoeg — voor exacte union zou per-line bitmap-merging nodig
    zijn (`xccov view --files-for-target` per file).
    """
    merged: dict[str, dict[str, int]] = {}
    for bundle in bundles:
        for path, cov in bundle.items():
            if path not in merged:
                merged[path] = dict(cov)
            else:
                merged[path]["covered"] = max(
                    merged[path]["covered"], cov["covered"]
                )
                # `total` blijft identiek (zelfde file in beide bundles).
    return merged


def render_dir_table(
    title: str, dir_groups: dict[str, dict[str, int]]
) -> list[str]:
    out = [f"## {title}", ""]
    out.append("| Directory | Files | Covered / Total | Coverage |")
    out.append("|---|---:|---:|---:|")
    for d, g in sorted(dir_groups.items(), key=lambda x: -x[1]["total"]):
        pct = g["covered"] / g["total"] * 100 if g["total"] else 0
        out.append(
            f"| `{d}/` | {g['files']} | "
            f"{g['covered']} / {g['total']} | {pct:.0f}% |"
        )
    return out


def render_aggregate(dir_groups: dict[str, dict[str, int]]) -> list[str]:
    """Drie slices: testable (excl Views), Views, Totaal."""
    testable_total = sum(
        g["total"] for d, g in dir_groups.items() if d != "Views"
    )
    testable_covered = sum(
        g["covered"] for d, g in dir_groups.items() if d != "Views"
    )
    views = dir_groups.get("Views", {"covered": 0, "total": 0})
    blended_total = testable_total + views["total"]
    blended_covered = testable_covered + views["covered"]

    pct_testable = (
        testable_covered / testable_total * 100 if testable_total else 0
    )
    pct_views = views["covered"] / views["total"] * 100 if views["total"] else 0
    pct_blended = (
        blended_covered / blended_total * 100 if blended_total else 0
    )

    return [
        "| Slice | Coverage |",
        "|---|---:|",
        f"| Testable code (excl `Views/`) | "
        f"**{pct_testable:.0f}%** ({testable_covered} / {testable_total}) |",
        f"| `Views/` | "
        f"{pct_views:.0f}% ({views['covered']} / {views['total']}) |",
        f"| Totaal | "
        f"{pct_blended:.0f}% ({blended_covered} / {blended_total}) |",
    ]


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(
            "Usage: coverage-report.py output.md label=input.json "
            "[label=input.json ...]"
        )

    output_path = sys.argv[1]
    bundles: dict[str, dict[str, dict[str, int]]] = {}
    for arg in sys.argv[2:]:
        if "=" not in arg:
            sys.exit(f"Bad argument '{arg}' — use label=input.json format.")
        label, path = arg.split("=", 1)
        bundles[label] = parse_bundle(path)

    out: list[str] = ["# Code Coverage Report", ""]

    # Per bundle: per-dir tabel + aggregate
    for label, file_cov in bundles.items():
        dir_groups = aggregate_by_dir(file_cov)
        out.extend(render_dir_table(f"{label} — per directory", dir_groups))
        out.append("")
        out.append(f"### {label} — aggregate")
        out.append("")
        out.extend(render_aggregate(dir_groups))
        out.append("")

    # Combined (merged) als er meer dan één bundle is
    if len(bundles) > 1:
        merged = merge_files_max(list(bundles.values()))
        merged_groups = aggregate_by_dir(merged)
        out.extend(
            render_dir_table(
                "Combined (unit + UI tests) — per directory", merged_groups
            )
        )
        out.append("")
        out.append("### Combined — aggregate")
        out.append("")
        out.extend(render_aggregate(merged_groups))
        out.append("")
        out.append(
            "> _Combined-rapportage gebruikt **per-file max-merge**: bij "
            "overlap tussen unit-tests en UI-tests wordt de hoogste dekking "
            "genomen. Approximatie — overlap is in deze codebase laag "
            "(unit dekt Services, UI dekt Views), dus afwijking is klein._"
        )
        out.append(">")

    out.append(
        "> _Het Xcode IDE Coverage Navigator-percentage filtert compiler-"
        "generated code uit en zit daardoor lager dan deze raw `xccov`-"
        "waarden. De **testable**-slice is de meest betekenisvolle metric "
        "voor unit-test-discipline._"
    )

    output = "\n".join(out) + "\n"
    with open(output_path, "w") as fh:
        fh.write(output)


if __name__ == "__main__":
    main()
