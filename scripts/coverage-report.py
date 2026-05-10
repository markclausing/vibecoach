#!/usr/bin/env python3
"""Genereert een per-directory coverage-rapport uit `xcrun xccov view --report --json`.

Achtergrond: `xccov --report` geeft één enkel target-percentage waarin Views
(die alleen door UI-tests gedekt worden) de denominator zwaar drukken. Dat
maskeert het feitelijke unit-test-bereik op Services/Models/ViewModels.

Dit script splitst de dekking op per top-level directory onder
`AIFitnessCoach/` en rapporteert daarnaast een "testable code"-aggregaat
(alles excl `Views/`) — dat is wat unit-tests realistisch kunnen dekken.

Gebruik:
    xcrun xccov view --report --json UnitTests.xcresult > coverage.json
    python3 scripts/coverage-report.py coverage.json coverage.md
"""

import json
import sys


def main(json_path: str, output_path: str) -> None:
    with open(json_path) as fh:
        data = json.load(fh)

    app_target = next(
        (t for t in data["targets"] if t["name"].endswith(".app")), None
    )
    if app_target is None:
        sys.exit("Geen .app-target gevonden in coverage-rapport.")

    groups: dict[str, dict[str, int]] = {}
    for f in app_target["files"]:
        path = f.get("path", "")
        if "/AIFitnessCoach/" not in path:
            continue
        rel = path.split("/AIFitnessCoach/", 1)[1]
        parts = rel.split("/")
        dir_name = parts[0] if len(parts) > 1 else "root"
        g = groups.setdefault(
            dir_name, {"covered": 0, "total": 0, "files": 0}
        )
        g["covered"] += f["coveredLines"]
        g["total"] += f["executableLines"]
        g["files"] += 1

    lines: list[str] = []
    lines.append("# Code Coverage Report")
    lines.append("")
    lines.append("## Per directory")
    lines.append("")
    lines.append("| Directory | Files | Covered / Total | Coverage |")
    lines.append("|---|---:|---:|---:|")
    for dir_name, g in sorted(groups.items(), key=lambda x: -x[1]["total"]):
        pct = g["covered"] / g["total"] * 100 if g["total"] else 0
        lines.append(
            f"| `{dir_name}/` | {g['files']} | "
            f"{g['covered']} / {g['total']} | {pct:.0f}% |"
        )

    testable_total = sum(g["total"] for d, g in groups.items() if d != "Views")
    testable_covered = sum(
        g["covered"] for d, g in groups.items() if d != "Views"
    )
    views = groups.get("Views", {"covered": 0, "total": 0})
    blended_total = testable_total + views["total"]
    blended_covered = testable_covered + views["covered"]

    pct_testable = (
        testable_covered / testable_total * 100 if testable_total else 0
    )
    pct_views = views["covered"] / views["total"] * 100 if views["total"] else 0
    pct_blended = (
        blended_covered / blended_total * 100 if blended_total else 0
    )

    lines.append("")
    lines.append("## Aggregate")
    lines.append("")
    lines.append("| Slice | Coverage |")
    lines.append("|---|---:|")
    lines.append(
        f"| Testable code (excl `Views/`) | "
        f"**{pct_testable:.0f}%** ({testable_covered} / {testable_total}) |"
    )
    lines.append(
        f"| `Views/` (UI-tests only) | "
        f"{pct_views:.0f}% ({views['covered']} / {views['total']}) |"
    )
    lines.append(
        f"| Totaal (incl Views) | "
        f"{pct_blended:.0f}% ({blended_covered} / {blended_total}) |"
    )
    lines.append("")
    lines.append(
        "> _Het **testable**-getal is een eerlijker indicator dan het totaal — "
        "`Views/` wordt door UI-tests gedekt, niet door deze unit-tests-bundle. "
        "Het Xcode IDE Coverage Navigator-percentage komt dichter bij het "
        "totaal-getal omdat dat ook compiler-generated code uitfiltert._"
    )
    lines.append(">")
    lines.append(
        "> _Gegenereerd uit `UnitTests.xcresult` van de `unit-tests`-job._"
    )

    output = "\n".join(lines) + "\n"
    with open(output_path, "w") as fh:
        fh.write(output)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: coverage-report.py <input.json> <output.md>")
    main(sys.argv[1], sys.argv[2])
