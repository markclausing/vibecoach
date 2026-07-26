import Foundation

/// Epic #73 story 73.4 — pure-Swift formatter for the **unified** periodisation context injected
/// into the coach prompt.
///
/// Before 73.4 the prompt carried one `═══ PERIODISERING: '<goal>' ═══` block per goal, each with
/// its own phase derived from that goal's own `weeksRemaining`. With overlapping races that is
/// self-contradicting: the earlier race's block says "taper, less is more" while the later race's
/// block says "maximum load". This formatter prefixes a single macrocycle header — one A-race
/// anchor, one effective phase, one combined weekly target, interim races explicitly framed as
/// mini-taper tune-ups — and the per-goal blocks below it are evaluated against that same phase
/// (`PeriodizationEngine.evaluateAllGoals(phaseOverride:)`), so they can no longer disagree.
///
/// Pure Swift, AppStorage-free (§6) and directly unit-testable. Prompt dates use
/// `AppDateFormatters.prompt*` so they stay `nl_NL` like every other prompt-side date (§13).
enum MacrocycleContextFormatter {

    /// Formats the unified program header plus the per-goal phase blocks.
    ///
    /// - Parameters:
    ///   - program: the unified macrocycle. `nil` (no active goal) falls back to the plain
    ///     per-goal join, preserving pre-73 behaviour.
    ///   - results: periodisation results, ideally evaluated with the program's effective phase.
    ///   - now: injected clock for testability.
    /// - Returns: the formatted context, or an empty string when there is nothing to say.
    static func format(program: UnifiedProgram?, results: [PeriodizationResult], now: Date = Date()) -> String {
        let goalBlocks = results.map { $0.coachingContext }.joined(separator: "\n\n")
        guard let program else { return goalBlocks }

        let header = programHeader(program: program, now: now)
        return goalBlocks.isEmpty ? header : header + "\n\n" + goalBlocks
    }

    // MARK: - Program header

    private static func programHeader(program: UnifiedProgram, now: Date) -> String {
        let dateFormat = AppDateFormatters.prompt("d MMM yyyy")
        let week = program.programWeek(at: now)
        let weeksToAnchor = program.end.timeIntervalSince(now) / (7 * 24 * 3600)

        var lines = ["═══ UNIFIED TRAINING PROGRAM (one macrocycle) ═══"]

        if let anchor = program.anchorRace {
            lines.append("🎯 A-RACE: '\(anchor.title)' — \(dateFormat.string(from: anchor.date)) "
                         + "(\(String(format: "%.1f", max(0, weeksToAnchor))) weeks out) "
                         + "| program week \(week.current)/\(week.total)")
        }

        lines.append("Current phase (applies to EVERY goal below): \(program.currentPhase.displayName)")
        lines.append(program.currentPhase.successCriteria.coaching)
        lines.append("Combined weekly load target: \(String(format: "%.0f", program.weeklyTrimpTarget)) TRIMP/week.")

        let interim = program.races.filter { !$0.isAnchor && $0.date >= now }
        if !interim.isEmpty {
            lines.append("")
            lines.append("Interim races (tune-ups INSIDE this program — never separate taper targets):")
            for race in interim {
                var line = "  • '\(race.title)' — \(dateFormat.string(from: race.date)) (\(race.priority.rawValue)-race)"
                if let taperStart = race.miniTaperStart {
                    line += " — mini-taper from \(dateFormat.string(from: taperStart))"
                }
                lines.append(line)
            }
        }

        if program.inMiniTaper, let active = activeMiniTaper(program: program, now: now) {
            lines.append("")
            lines.append("⚡ MINI-TAPER ACTIVE for '\(active.title)' (\(dateFormat.string(from: active.date))): "
                         + "unload briefly — short, light sessions only — and resume building toward the A-race "
                         + "the day after. Do NOT start a full taper; this race is a tune-up, not the season goal.")
        }

        lines.append("")
        lines.append("HARD RULE — ONE PROGRAM: there is exactly one periodisation. Plan the week against the "
                     + "phase and weekly target above. Never advise a full taper for an interim race, and never "
                     + "give per-goal phase advice that contradicts this header.")

        return lines.joined(separator: "\n")
    }

    /// The interim race whose mini-taper window contains `now`.
    private static func activeMiniTaper(program: UnifiedProgram, now: Date) -> RaceMarker? {
        program.races.first { race in
            guard let start = race.miniTaperStart else { return false }
            return now >= start && now < race.date
        }
    }
}
