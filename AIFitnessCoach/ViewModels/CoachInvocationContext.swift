import Foundation

/// Story 65.3: bundles the three per-call context parameters that used to be
/// threaded individually (`contextProfile`, `activeGoals`, `activePreferences`)
/// through every public `ChatViewModel` entry point and its private fetch helpers.
///
/// Collapsing them into one value removes the repetitive 3-argument plumbing and
/// keeps the orchestration methods readable. Pure value type — no SwiftData / view
/// dependencies — so it is trivially constructible from any call site.
struct CoachInvocationContext {
    /// The athletic profile (peak performance, weekly volume, recovery flag) injected
    /// into the `[ATHLETE CONTEXT]` prompt block. `nil` when the caller has no profile.
    var profile: AthleticProfile?
    /// The user's active fitness goals — drive the `[DOELEN]` prefix and the
    /// `[PERIODIZATION — ACTIVE TRAINING PHASES]` block.
    var activeGoals: [FitnessGoal]
    /// The user's active preferences (pinned + temporary) for the preferences block.
    var activePreferences: [UserPreference]

    init(profile: AthleticProfile? = nil,
         activeGoals: [FitnessGoal] = [],
         activePreferences: [UserPreference] = []) {
        self.profile = profile
        self.activeGoals = activeGoals
        self.activePreferences = activePreferences
    }

    /// A context with no profile, goals or preferences — the default for calls that
    /// do not (yet) have that data in scope.
    static let empty = CoachInvocationContext()
}
