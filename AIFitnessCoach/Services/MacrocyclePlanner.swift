import Foundation

// MARK: - Epic #73 story 73.1: MacrocyclePlanner

/// Merges every active goal into **one** macrocycle, so overlapping race goals no longer each run
/// their own contradicting periodisation (an earlier B-race tapering while the A-race still needs
/// to build). The single A-race anchors the program; interim races (earlier, non-anchor) are folded
/// in as mini-taper tune-ups after which the build toward the A-race resumes.
///
/// Pure Swift, AppStorage-free (§6). The date/phase maths reuse `PhaseWindowCalculator` so the
/// macrocycle bar can never disagree with the per-phase windows.
enum MacrocyclePlanner {

    /// Length of the short unload before an interim (non-anchor) race. Deliberately a few days,
    /// not the full 2-week taper — a B/C race is a tune-up, so the athlete freshens up briefly and
    /// then resumes building toward the A-race.
    static let miniTaperDays = 4

    /// Builds the unified program from all goals, or `nil` when there is no active goal to plan for.
    ///
    /// - Parameters:
    ///   - goals: all of the user's goals (completed/expired ones are filtered out here).
    ///   - activities: recent activities — reserved for the combined weekly-target refinement in
    ///     later stories; the current target derives from the anchor's macrocycle phase.
    ///   - now: injected clock for testability.
    ///   - calendar: injected calendar (DST-safe date maths, §3).
    static func plan(
        goals: [FitnessGoal],
        activities: [ActivityRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UnifiedProgram? {
        let active = goals.filter { !$0.isCompleted && now < $0.targetDate }
        guard let anchor = selectAnchor(active) else { return nil }

        // The macrocycle spans from the earliest goal's creation to the anchor race. Base building
        // therefore reflects when the athlete actually started, not just the anchor's own window.
        let programStart = active.map(\.createdAt).min() ?? anchor.createdAt
        let windows = PhaseWindowCalculator.windows(
            targetDate: anchor.targetDate,
            createdAt: programStart,
            calendar: calendar
        )

        // Interim races: active, non-anchor, and earlier than the anchor. Each gets a mini-taper
        // window ending on race day. (A lower-priority race dated *after* the anchor is degenerate —
        // it is kept as a plain marker with no mini-taper, since the macrocycle ends at the anchor.)
        let races = buildRaceMarkers(active: active, anchor: anchor, now: now, calendar: calendar)

        let miniTaper = races.first { marker in
            guard let taperStart = marker.miniTaperStart else { return false }
            return now >= taperStart && now < marker.date
        }
        let inMiniTaper = miniTaper != nil

        let underlyingPhase = phase(containing: now, in: windows) ?? (anchor.currentPhase ?? .baseBuilding)
        let effectivePhase: TrainingPhase = inMiniTaper ? .tapering : underlyingPhase

        let weeklyTrimpTarget = weeklyTarget(anchor: anchor, phase: effectivePhase, now: now)

        return UnifiedProgram(
            anchorGoalID: anchor.id,
            phases: windows,
            races: races,
            currentPhase: effectivePhase,
            inMiniTaper: inMiniTaper,
            weeklyTrimpTarget: weeklyTrimpTarget,
            start: programStart,
            end: anchor.targetDate
        )
    }

    // MARK: - Anchor selection

    /// Picks the A-race that anchors the macrocycle:
    /// 1. an explicitly-A goal (multiple → the latest-dated one);
    /// 2. otherwise the latest race — the date-derived default from the locked product model.
    ///
    /// **A B/C marking demotes, it never promotes.** An earlier race the athlete deliberately
    /// marked "B" must not out-rank a later unmarked one: saying "this is a B-race" is a statement
    /// that it is *not* the season goal. Ranking by best-explicit-priority (the original 73.1
    /// reading) did exactly the opposite — with Haarlem marked B and Amsterdam left unset, the half
    /// marathon anchored the macrocycle and the marathon three weeks later was clamped onto the end
    /// of the bar as a stray marker, which is the very failure this epic exists to remove.
    static func selectAnchor(_ active: [FitnessGoal]) -> FitnessGoal? {
        guard !active.isEmpty else { return nil }

        let explicitA = active.filter { $0.racePriority == .a }
        if !explicitA.isEmpty {
            return explicitA.max { $0.targetDate < $1.targetDate }
        }

        return active.max { $0.targetDate < $1.targetDate }
    }

    /// The priority shown on a race marker: the goal's explicit `racePriority` if set, otherwise
    /// derived from its role in the program (the anchor is the A-race, every other race a B tune-up).
    static func resolvedPriority(for goal: FitnessGoal, anchor: FitnessGoal) -> RacePriority {
        goal.racePriority ?? (goal.id == anchor.id ? .a : .b)
    }

    // MARK: - Race markers

    private static func buildRaceMarkers(
        active: [FitnessGoal],
        anchor: FitnessGoal,
        now: Date,
        calendar: Calendar
    ) -> [RaceMarker] {
        active
            .map { goal -> RaceMarker in
                let isAnchor = goal.id == anchor.id
                // Interim = a non-anchor race before the anchor. Only those get a mini-taper; the
                // anchor uses the macrocycle taper, and a rare later-than-anchor race gets none.
                let isInterim = !isAnchor && goal.targetDate < anchor.targetDate
                let taperStart = isInterim
                    ? calendar.date(byAdding: .day, value: -miniTaperDays, to: goal.targetDate)
                    : nil
                return RaceMarker(
                    goalID: goal.id,
                    title: goal.title,
                    date: goal.targetDate,
                    priority: resolvedPriority(for: goal, anchor: anchor),
                    isAnchor: isAnchor,
                    miniTaperStart: taperStart
                )
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Phase & target helpers

    /// The phase whose window contains `now`, or `nil` if `now` falls outside every window
    /// (before the first start / after the last end — the caller then falls back).
    private static func phase(containing now: Date, in windows: [PhaseWindow]) -> TrainingPhase? {
        windows.first { now >= $0.start && now < $0.end }?.phase
    }

    /// Combined weekly TRIMP target: the anchor's linear remaining-load rate corrected by the
    /// current macrocycle phase multiplier. During a mini-taper the taper multiplier applies, so the
    /// week automatically unloads for the interim race.
    private static func weeklyTarget(anchor: FitnessGoal, phase: TrainingPhase, now: Date) -> Double {
        let weeksRemaining = max(0.1, anchor.weeksRemaining(from: now))
        let linearRate = anchor.computedTargetTRIMP / weeksRemaining
        return linearRate * phase.multiplier
    }
}
