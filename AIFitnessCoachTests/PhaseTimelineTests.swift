import XCTest
@testable import AIFitnessCoach

/// Epic #60 story 60.1 — unit tests for `PhaseWindowCalculator` (the single source of truth
/// for phase windows) and `ProgressService.phaseTimeline` (per-phase targets + milestones).
/// All dates are absolute and `now` is injected, so the tests are deterministic.
final class PhaseTimelineTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(weeks: Int, from base: Date) -> Date {
        cal.date(byAdding: .weekOfYear, value: weeks, to: base)!
    }

    private func makeGoal(title: String,
                          weeksUntil: Int,
                          createdWeeksAgo: Int,
                          sport: SportCategory? = nil) -> FitnessGoal {
        FitnessGoal(
            title: title,
            targetDate: date(weeks: weeksUntil, from: now),
            createdAt: date(weeks: -createdWeeksAgo, from: now),
            sportCategory: sport
        )
    }

    private func makeActivity(sport: SportCategory,
                              startDate: Date,
                              distanceMeters: Double = 0,
                              trimp: Double = 0) -> ActivityRecord {
        ActivityRecord(
            id: UUID().uuidString,
            name: "Activity",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: sport,
            startDate: startDate,
            trimp: trimp
        )
    }

    // MARK: - PhaseWindowCalculator

    func testWindowsLongGoalHasFourContiguousPhases() {
        let target = now
        let created = date(weeks: -20, from: now)
        let windows = PhaseWindowCalculator.windows(targetDate: target, createdAt: created)

        XCTAssertEqual(windows.map { $0.phase },
                       [.baseBuilding, .buildPhase, .peakPhase, .tapering])
        // Contiguous: each phase ends exactly where the next begins.
        for i in 0..<(windows.count - 1) {
            XCTAssertEqual(windows[i].end, windows[i + 1].start,
                           "Phase \(windows[i].phase) must end where \(windows[i + 1].phase) starts")
        }
        // Peak + taper are always 2 weeks; build is capped at 8.
        XCTAssertEqual(windows.first { $0.phase == .peakPhase }?.weekCount, 2)
        XCTAssertEqual(windows.first { $0.phase == .tapering }?.weekCount, 2)
        XCTAssertEqual(windows.first { $0.phase == .buildPhase }?.weekCount, 8)
    }

    func testWindowsShortGoalOmitsBase() {
        // 8 trainable weeks → build 4 / peak 2 / taper 2, no base phase.
        let target = now
        let created = date(weeks: -8, from: now)
        let windows = PhaseWindowCalculator.windows(targetDate: target, createdAt: created)

        XCTAssertFalse(windows.contains { $0.phase == .baseBuilding },
                       "A short goal must not show a base phase from before it started")
        XCTAssertEqual(windows.map { $0.phase }, [.buildPhase, .peakPhase, .tapering])
        XCTAssertEqual(windows.first { $0.phase == .buildPhase }?.weekCount, 4)
    }

    func testTaperWindowEndsOnTargetDate() {
        let target = now
        let windows = PhaseWindowCalculator.windows(targetDate: target, createdAt: date(weeks: -16, from: now))
        XCTAssertEqual(windows.last?.phase, .tapering)
        XCTAssertEqual(windows.last?.end, target, "Taper must end exactly on race day")
    }

    // MARK: - ProgressService.phaseTimeline

    func testTimelineStatusPastCurrentFuture() {
        // Marathon, race in 3 weeks → today sits in the peak window.
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 3, createdWeeksAgo: 16)
        let timeline = ProgressService.phaseTimeline(for: goal, activities: [], now: now)

        func status(_ phase: TrainingPhase) -> PhaseStatus? {
            timeline.phases.first { $0.phase == phase }?.status
        }
        XCTAssertEqual(status(.peakPhase), .current)
        XCTAssertEqual(status(.buildPhase), .past)
        XCTAssertEqual(status(.tapering), .future)
    }

    func testTimelineBucketsAllMilestonesUnderPhases() {
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 3, createdWeeksAgo: 16)
        let timeline = ProgressService.phaseTimeline(for: goal, activities: [], now: now)

        let totalMilestones = timeline.phases.reduce(0) { $0 + $1.milestones.count }
        XCTAssertEqual(totalMilestones, BlueprintChecker.marathonBlueprint.essentialWorkouts.count)
        XCTAssertGreaterThan(totalMilestones, 0)
    }

    func testTaperTargetIsInverted() {
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 8, createdWeeksAgo: 16)
        let timeline = ProgressService.phaseTimeline(for: goal, activities: [], now: now)
        let taper = timeline.phases.first { $0.phase == .tapering }
        XCTAssertNotNil(taper)
        XCTAssertTrue(taper!.targets.allSatisfy { $0.isInverted },
                      "In the taper, less is better — every target must be inverted")
    }

    func testFuturePhaseHasNilCurrent() {
        // Race in 16 weeks → today is in base; taper is still in the future.
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 16, createdWeeksAgo: 2)
        let timeline = ProgressService.phaseTimeline(for: goal, activities: [], now: now)
        let taper = timeline.phases.first { $0.phase == .tapering }
        XCTAssertEqual(taper?.status, .future)
        XCTAssertTrue(taper!.targets.allSatisfy { $0.current == nil },
                      "A future phase has nothing achieved yet → current must be nil")
    }

    func testBlueprintlessGoalGetsGenericTrimpTargetOnly() {
        // No keyword + no running/cycling sport → no blueprint, so only a generic TRIMP target.
        let goal = makeGoal(title: "Algemene conditie", weeksUntil: 8, createdWeeksAgo: 16, sport: .other)
        let timeline = ProgressService.phaseTimeline(for: goal, activities: [], now: now)

        for phase in timeline.phases {
            XCTAssertEqual(phase.targets.count, 1, "Blueprint-less goals show only the TRIMP target")
            XCTAssertEqual(phase.targets.first?.unit, "TRIMP")
            XCTAssertTrue(phase.milestones.isEmpty, "No blueprint → no essential-workout milestones")
        }
    }

    func testLongestSessionTargetReflectsLoggedActivity() {
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 3, createdWeeksAgo: 16)
        // A 30 km run during the current (peak) phase: peak window is [-4w, -2w] from target.
        let runDate = date(weeks: -3, from: goal.targetDate)
        let activities = [makeActivity(sport: .running, startDate: runDate, distanceMeters: 30_000, trimp: 200)]

        let timeline = ProgressService.phaseTimeline(for: goal, activities: activities, now: now)
        let peak = timeline.phases.first { $0.phase == .peakPhase }
        let session = peak?.targets.first { $0.unit == "km" }
        XCTAssertEqual(session?.current ?? 0, 30, accuracy: 0.01,
                       "The longest-session target must reflect the 30 km run logged in this phase")
    }
}
