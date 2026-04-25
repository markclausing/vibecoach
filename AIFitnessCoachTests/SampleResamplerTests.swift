import XCTest
@testable import AIFitnessCoach

/// Unit tests voor de `SampleResampler` (Epic 32 Story 32.1).
/// Geen HealthKit-dependency — synthetische input dekt alle drie de strategieën én edge cases.
final class SampleResamplerTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let resampler = SampleResampler(bucketSeconds: 5)

    // MARK: - bucketStarts

    func testBucketStartsGenerateCorrectGrid() {
        let end = baseDate.addingTimeInterval(15) // 3 buckets van 5s
        let starts = resampler.bucketStarts(from: baseDate, to: end)

        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(starts[0], baseDate)
        XCTAssertEqual(starts[1], baseDate.addingTimeInterval(5))
        XCTAssertEqual(starts[2], baseDate.addingTimeInterval(10))
    }

    func testBucketStartsEmptyWhenStartNotBeforeEnd() {
        XCTAssertTrue(resampler.bucketStarts(from: baseDate, to: baseDate).isEmpty)
        XCTAssertTrue(resampler.bucketStarts(from: baseDate, to: baseDate.addingTimeInterval(-5)).isEmpty)
    }

    // MARK: - Average (HR / Power / Cadence)

    func testAverageReducesMultipleSamplesPerBucket() {
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(0), value: 140),
            TimedValue(timestamp: baseDate.addingTimeInterval(2), value: 150),
            TimedValue(timestamp: baseDate.addingTimeInterval(4), value: 160),
            TimedValue(timestamp: baseDate.addingTimeInterval(5), value: 200), // valt in bucket #2
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(10),
                                        strategy: .average)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].value!, 150, accuracy: 0.0001) // (140+150+160)/3
        XCTAssertEqual(result[1].value!, 200, accuracy: 0.0001)
    }

    func testAverageEmptyBucketReturnsNil() {
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(1), value: 130),
            // bucket #2 (5..10) heeft geen samples
            TimedValue(timestamp: baseDate.addingTimeInterval(11), value: 145), // bucket #3
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(15),
                                        strategy: .average)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].value!, 130, accuracy: 0.0001)
        XCTAssertNil(result[1].value, "Lege buckets moeten nil opleveren — niet 0")
        XCTAssertEqual(result[2].value!, 145, accuracy: 0.0001)
    }

    func testAverageIgnoresUnsortedInput() {
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(4), value: 160),
            TimedValue(timestamp: baseDate.addingTimeInterval(0), value: 140),
            TimedValue(timestamp: baseDate.addingTimeInterval(2), value: 150),
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(5),
                                        strategy: .average)
        XCTAssertEqual(result[0].value!, 150, accuracy: 0.0001)
    }

    // MARK: - LinearInterpolation (Speed)

    func testLinearInterpolationAtMidpoint() {
        // Twee samples: t=0 → 4 m/s, t=10 → 6 m/s. Bucket-start op t=5 → verwacht 5 m/s.
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(0), value: 4),
            TimedValue(timestamp: baseDate.addingTimeInterval(10), value: 6),
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(15),
                                        strategy: .linearInterpolation)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].value!, 4.0, accuracy: 0.0001)
        XCTAssertEqual(result[1].value!, 5.0, accuracy: 0.0001) // exact midden
        XCTAssertEqual(result[2].value!, 6.0, accuracy: 0.0001)
    }

    func testLinearInterpolationOutsideRangeReturnsNil() {
        // Samples beginnen pas op t=10 — buckets op t=0 en t=5 moeten nil zijn (geen extrapolatie).
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(10), value: 5),
            TimedValue(timestamp: baseDate.addingTimeInterval(15), value: 6),
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(20),
                                        strategy: .linearInterpolation)

        XCTAssertNil(result[0].value)
        XCTAssertNil(result[1].value)
        XCTAssertEqual(result[2].value!, 5.0, accuracy: 0.0001) // exacte match op t=10
        XCTAssertEqual(result[3].value!, 6.0, accuracy: 0.0001) // exacte match op t=15 (laatste sample)
    }

    // MARK: - DeltaAccumulation (Distance)

    func testDeltaAccumulationSumsWithinBucket() {
        // Distance-samples: per stuk de delta in meters tijdens een sub-interval.
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(0), value: 1.5),
            TimedValue(timestamp: baseDate.addingTimeInterval(1), value: 1.6),
            TimedValue(timestamp: baseDate.addingTimeInterval(3), value: 1.4),
            TimedValue(timestamp: baseDate.addingTimeInterval(5), value: 1.7), // bucket #2
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(10),
                                        strategy: .deltaAccumulation)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].value!, 4.5, accuracy: 0.0001) // 1.5+1.6+1.4
        XCTAssertEqual(result[1].value!, 1.7, accuracy: 0.0001)
    }

    func testDeltaAccumulationEmptyBucketReturnsNil() {
        let samples = [
            TimedValue(timestamp: baseDate.addingTimeInterval(0), value: 2.0),
        ]
        let result = resampler.resample(samples: samples,
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(15),
                                        strategy: .deltaAccumulation)

        XCTAssertEqual(result[0].value!, 2.0, accuracy: 0.0001)
        XCTAssertNil(result[1].value)
        XCTAssertNil(result[2].value)
    }

    // MARK: - Generic edge cases

    func testEmptyInputProducesAllNilBuckets() {
        let result = resampler.resample(samples: [],
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(10),
                                        strategy: .average)
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result[0].value)
        XCTAssertNil(result[1].value)
    }

    func testTimestampsAlignToBucketStart() {
        // Elke bucket-timestamp in het resultaat moet exact gelijk zijn aan de berekende bucket-start.
        let result = resampler.resample(samples: [],
                                        from: baseDate,
                                        to: baseDate.addingTimeInterval(15),
                                        strategy: .average)
        XCTAssertEqual(result[0].timestamp, baseDate)
        XCTAssertEqual(result[1].timestamp, baseDate.addingTimeInterval(5))
        XCTAssertEqual(result[2].timestamp, baseDate.addingTimeInterval(10))
    }
}
