//
//  TodayRecapTests.swift
//  LoopTests
//

import HealthKit
import LoopKit
import XCTest
@testable import Loop

final class TodayRecapCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: .hours(200))

    func testDistributionUsesInclusiveBoundsAndSumsToOneHundredPercent() {
        let context = queryContext()
        let values = [69, 70, 80, 90, 100, 110, 120, 130, 140, 150, 180, 181]
        let metrics = TodayRecapCalculator.glucoseMetrics(
            from: values.enumerated().map { sample(value: Double($0.element), date: context.startDate + .minutes(Double($0.offset * 5))) },
            in: context
        )

        XCTAssertEqual(metrics?.distribution?.belowCount, 1)
        XCTAssertEqual(metrics?.distribution?.withinCount, 10)
        XCTAssertEqual(metrics?.distribution?.aboveCount, 1)
        XCTAssertEqual(
            [metrics?.distribution?.belowPercent, metrics?.distribution?.withinPercent, metrics?.distribution?.abovePercent]
                .compactMap { $0 }
                .reduce(0, +),
            100
        )
    }

    func testDisplayOnlyAndOutOfWindowSamplesAreExcluded() {
        let context = queryContext()
        var samples = (0..<12).map { index in
            sample(value: 100, date: context.startDate + .minutes(Double(index * 5)), wasUserEntered: index == 0)
        }
        samples.append(sample(value: 300, date: context.startDate + .minutes(65), isDisplayOnly: true))
        samples.append(sample(value: 40, date: context.endDate))

        let metrics = TodayRecapCalculator.glucoseMetrics(from: samples, in: context)

        XCTAssertEqual(metrics?.readingCount, 12)
        XCTAssertEqual(metrics?.manualReadingCount, 1)
        XCTAssertEqual(metrics?.excludedDisplayOnlyCount, 1)
        XCTAssertEqual(metrics?.distribution?.withinPercent, 100)
    }

    func testSensorLimitConditionsAreClassifiedButExcludedFromExactStatistics() {
        let context = queryContext()
        var samples = (0..<10).map { index in
            sample(value: 100, date: context.startDate + .minutes(Double(index * 5)))
        }
        samples.append(sample(value: 40, date: context.startDate + .minutes(50), condition: .belowRange))
        samples.append(sample(value: 400, date: context.startDate + .minutes(55), condition: .aboveRange))

        let metrics = TodayRecapCalculator.glucoseMetrics(from: samples, in: context)

        XCTAssertEqual(metrics?.distribution?.belowCount, 1)
        XCTAssertEqual(metrics?.distribution?.withinCount, 10)
        XCTAssertEqual(metrics?.distribution?.aboveCount, 1)
        XCTAssertEqual(metrics?.censoredReadingCount, 2)
        XCTAssertEqual(metrics?.averageMilligramsPerDeciliter ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(metrics?.minimumMilligramsPerDeciliter ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(metrics?.maximumMilligramsPerDeciliter ?? 0, 100, accuracy: 0.001)
    }

    func testDisplayOnlyCountSupportsExcludedOnlyState() {
        let context = queryContext()
        let samples = [sample(value: 100, date: context.startDate + .minutes(5), isDisplayOnly: true)]

        XCTAssertNil(TodayRecapCalculator.glucoseMetrics(from: samples, in: context))
        XCTAssertEqual(TodayRecapCalculator.displayOnlyCount(from: samples, in: context), 1)
    }

    func testSparseReadingsDoNotProduceDistribution() {
        let context = queryContext()
        let metrics = TodayRecapCalculator.glucoseMetrics(
            from: [sample(value: 100, date: context.startDate + .minutes(5))],
            in: context
        )

        XCTAssertEqual(metrics?.readingCount, 1)
        XCTAssertNil(metrics?.distribution)
        XCTAssertNil(metrics?.largestGap)
    }

    func testLargestGapUsesChronologicalReadings() {
        let context = queryContext()
        let metrics = TodayRecapCalculator.glucoseMetrics(
            from: [
                sample(value: 100, date: context.startDate + .minutes(35)),
                sample(value: 100, date: context.startDate + .minutes(5)),
                sample(value: 100, date: context.startDate + .minutes(10))
            ],
            in: context
        )

        XCTAssertEqual(metrics?.largestGap, .minutes(25))
    }

    func testInsulinTotalTrimsDosesToWindow() {
        let context = queryContext()
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: context.startDate - .minutes(30),
            endDate: context.startDate + .minutes(30),
            value: 2,
            unit: .unitsPerHour
        )

        let metrics = TodayRecapCalculator.totalInsulin(from: [dose], in: context)

        XCTAssertEqual(metrics.units, 1, accuracy: 0.001)
        XCTAssertTrue(metrics.includesEstimatedDelivery)
    }

    func testInsulinTotalExcludesZeroDurationDoseOutsideWindow() {
        let context = queryContext()
        let dose = DoseEntry(
            type: .bolus,
            startDate: context.startDate - .minutes(5),
            value: 2,
            unit: .units
        )

        XCTAssertEqual(TodayRecapCalculator.totalInsulin(from: [dose], in: context).units, 0)
    }

    func testInsulinTotalUsesDeliveredUnitsForInterruptedBolus() {
        let context = queryContext()
        let dose = DoseEntry(
            type: .bolus,
            startDate: context.startDate + .minutes(30),
            value: 4,
            unit: .units,
            deliveredUnits: 1.5
        )

        let metrics = TodayRecapCalculator.totalInsulin(from: [dose], in: context)

        XCTAssertEqual(metrics.units, 1.5, accuracy: 0.001)
        XCTAssertFalse(metrics.includesEstimatedDelivery)
    }

    func testFinalizedDoseWithoutDeliveredUnitsIsReportedNotEstimated() {
        let context = queryContext()
        let dose = DoseEntry(
            type: .bolus,
            startDate: context.startDate + .minutes(30),
            value: 2,
            unit: .units,
            manuallyEntered: true
        )

        let metrics = TodayRecapCalculator.totalInsulin(from: [dose], in: context)

        XCTAssertEqual(metrics.units, 2, accuracy: 0.001)
        XCTAssertFalse(metrics.includesEstimatedDelivery)
    }

    func testCarbTotalSumsRecordedEntries() {
        let context = queryContext()
        let entries = [10.0, 15.5].enumerated().map { index, grams in
            StoredCarbEntry(
                startDate: context.startDate + .minutes(Double(index * 30)),
                quantity: HKQuantity(unit: .gram(), doubleValue: grams),
                uuid: UUID(),
                provenanceIdentifier: "TodayRecapTests",
                syncIdentifier: UUID().uuidString,
                syncVersion: 1,
                foodType: nil,
                absorptionTime: nil,
                createdByCurrentApp: true,
                userCreatedDate: context.startDate,
                userUpdatedDate: context.startDate
            )
        }

        XCTAssertEqual(TodayRecapCalculator.totalCarbs(from: entries), 25.5, accuracy: 0.001)
    }

    private func queryContext() -> TodayRecapQueryContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return TodayRecapQueryContext(now: now, calendar: calendar)
    }

    private func sample(
        value: Double,
        date: Date,
        isDisplayOnly: Bool = false,
        wasUserEntered: Bool = false,
        condition: GlucoseCondition? = nil
    ) -> StoredGlucoseSample {
        StoredGlucoseSample(
            uuid: UUID(),
            provenanceIdentifier: "TodayRecapTests",
            syncIdentifier: UUID().uuidString,
            syncVersion: 1,
            startDate: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
            condition: condition,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: isDisplayOnly,
            wasUserEntered: wasUserEntered,
            device: nil,
            healthKitEligibleDate: nil
        )
    }
}

@MainActor
final class TodayRecapViewModelTests: XCTestCase {
    func testPartialFailureKeepsSuccessfulSectionsAvailable() async {
        let dataSource = MockTodayRecapDataSource()
        dataSource.glucoseResult = .failure(MockError.unavailable)
        dataSource.carbResult = .success([])
        dataSource.doseResult = .success([])
        let viewModel = TodayRecapViewModel(dataSource: dataSource)

        await viewModel.refresh()

        if case .unavailable = viewModel.glucoseState {} else {
            XCTFail("Expected unavailable glucose state")
        }
        if case .available(let carbs) = viewModel.carbsState {
            XCTAssertEqual(carbs, 0)
        } else {
            XCTFail("Expected available zero-carb state")
        }
        if case .available(let insulin) = viewModel.insulinState {
            XCTAssertEqual(insulin.units, 0)
        } else {
            XCTFail("Expected available zero-insulin state")
        }
        XCTAssertNotNil(viewModel.lastUpdated)
    }
}

private final class MockTodayRecapDataSource: TodayRecapDataSource {
    var todayRecapGlucoseUnit: HKUnit = .milligramsPerDeciliter
    var glucoseResult: Swift.Result<[StoredGlucoseSample], Error> = .success([])
    var carbResult: CarbStoreResult<[StoredCarbEntry]> = .success([])
    var doseResult: DoseStoreResult<[DoseEntry]> = .success([])

    func fetchTodayRecapGlucose(start: Date, end: Date, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(glucoseResult)
    }

    func fetchTodayRecapCarbs(start: Date, end: Date, completion: @escaping (CarbStoreResult<[StoredCarbEntry]>) -> Void) {
        completion(carbResult)
    }

    func fetchTodayRecapDoses(start: Date, end: Date, completion: @escaping (DoseStoreResult<[DoseEntry]>) -> Void) {
        completion(doseResult)
    }
}

private enum MockError: Error {
    case unavailable
}
