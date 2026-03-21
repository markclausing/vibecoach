actor HealthKitSyncService {
    let x: Int = 1

    @MainActor
    func test() async {
        _ = x
    }
}
