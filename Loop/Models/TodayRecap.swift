//
//  TodayRecap.swift
//  Loop
//

import Foundation
import HealthKit
import LoopKit

struct TodayRecapQueryContext {
    let startDate: Date
    let endDate: Date
    let timeZone: TimeZone

    init(now: Date, calendar: Calendar) {
        startDate = calendar.startOfDay(for: now)
        endDate = now
        timeZone = calendar.timeZone
    }
}

enum TodayRecapSourceState<Value> {
    case loading
    case available(Value)
    case noData
    case excluded(Int)
    case unavailable
}

struct TodayRecapDistribution {
    let belowCount: Int
    let withinCount: Int
    let aboveCount: Int
    let belowPercent: Int
    let withinPercent: Int
    let abovePercent: Int
}

struct TodayRecapGlucoseMetrics {
    let readingCount: Int
    let manualReadingCount: Int
    let excludedDisplayOnlyCount: Int
    let censoredReadingCount: Int
    let firstReadingDate: Date
    let latestReadingDate: Date
    let largestGap: TimeInterval?
    let averageMilligramsPerDeciliter: Double?
    let minimumMilligramsPerDeciliter: Double?
    let maximumMilligramsPerDeciliter: Double?
    let distribution: TodayRecapDistribution?
}

struct TodayRecapInsulinMetrics {
    let units: Double
    let includesEstimatedDelivery: Bool
}

enum TodayRecapCalculator {
    static let lowerBoundMilligramsPerDeciliter = 70.0
    static let upperBoundMilligramsPerDeciliter = 180.0
    static let minimumReadingCountForDistribution = 12

    static func glucoseMetrics(
        from samples: [StoredGlucoseSample],
        in context: TodayRecapQueryContext
    ) -> TodayRecapGlucoseMetrics? {
        let samplesInWindow = samples.filter {
            context.startDate <= $0.startDate && $0.startDate < context.endDate
        }
        let excludedDisplayOnlyCount = samplesInWindow.filter(\.isDisplayOnly).count
        let eligibleReadings = samplesInWindow.compactMap { sample -> (sample: StoredGlucoseSample, value: Double)? in
            guard !sample.isDisplayOnly else {
                return nil
            }

            let value = sample.quantity.doubleValue(for: .milligramsPerDeciliter)
            guard value.isFinite && value > 0 else {
                return nil
            }

            return (sample, value)
        }.sorted { $0.sample.startDate < $1.sample.startDate }

        guard let firstReading = eligibleReadings.first, let latestReading = eligibleReadings.last else {
            return nil
        }

        let readingCount = eligibleReadings.count
        let belowCount = eligibleReadings.filter { reading in
            reading.sample.condition == .belowRange || reading.value < lowerBoundMilligramsPerDeciliter
        }.count
        let aboveCount = eligibleReadings.filter { reading in
            reading.sample.condition == .aboveRange || reading.value > upperBoundMilligramsPerDeciliter
        }.count
        let withinCount = readingCount - belowCount - aboveCount
        let exactValues = eligibleReadings.compactMap { reading in
            reading.sample.condition == nil ? reading.value : nil
        }
        let distribution: TodayRecapDistribution?

        if readingCount >= minimumReadingCountForDistribution {
            let percentages = roundedPercentages(for: [belowCount, withinCount, aboveCount])
            distribution = TodayRecapDistribution(
                belowCount: belowCount,
                withinCount: withinCount,
                aboveCount: aboveCount,
                belowPercent: percentages[0],
                withinPercent: percentages[1],
                abovePercent: percentages[2]
            )
        } else {
            distribution = nil
        }

        let largestGap = zip(eligibleReadings, eligibleReadings.dropFirst())
            .map { $1.sample.startDate.timeIntervalSince($0.sample.startDate) }
            .max()

        return TodayRecapGlucoseMetrics(
            readingCount: readingCount,
            manualReadingCount: eligibleReadings.filter { $0.sample.wasUserEntered }.count,
            excludedDisplayOnlyCount: excludedDisplayOnlyCount,
            censoredReadingCount: readingCount - exactValues.count,
            firstReadingDate: firstReading.sample.startDate,
            latestReadingDate: latestReading.sample.startDate,
            largestGap: largestGap,
            averageMilligramsPerDeciliter: exactValues.isEmpty ? nil : exactValues.reduce(0, +) / Double(exactValues.count),
            minimumMilligramsPerDeciliter: exactValues.min(),
            maximumMilligramsPerDeciliter: exactValues.max(),
            distribution: distribution
        )
    }

    static func displayOnlyCount(
        from samples: [StoredGlucoseSample],
        in context: TodayRecapQueryContext
    ) -> Int {
        samples.filter {
            context.startDate <= $0.startDate && $0.startDate < context.endDate && $0.isDisplayOnly
        }.count
    }

    static func totalCarbs(from entries: [StoredCarbEntry]) -> Double {
        entries.reduce(0) { total, entry in
            total + entry.quantity.doubleValue(for: .gram())
        }
    }

    static func totalInsulin(
        from doses: [DoseEntry],
        in context: TodayRecapQueryContext
    ) -> TodayRecapInsulinMetrics {
        let dosesInWindow = doses.filter { dose in
            if dose.startDate == dose.endDate {
                return context.startDate <= dose.startDate && dose.startDate < context.endDate
            }

            return context.startDate < dose.endDate && dose.startDate < context.endDate
        }
        let units = dosesInWindow.reduce(0) { total, dose in
            let trimmedDose = dose.trimmed(from: context.startDate, to: context.endDate)
            return total + trimmedDose.unitsInDeliverableIncrements
        }

        return TodayRecapInsulinMetrics(
            units: units,
            includesEstimatedDelivery: dosesInWindow.contains(where: \.isMutable)
        )
    }

    private static func roundedPercentages(for counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        precondition(total > 0, "Cannot calculate percentages without readings")

        let exactPercentages = counts.map { Double($0) * 100 / Double(total) }
        var roundedPercentages = exactPercentages.map { Int(floor($0)) }
        let remainderCount = 100 - roundedPercentages.reduce(0, +)
        let indicesByRemainder = exactPercentages.indices.sorted { first, second in
            let firstRemainder = exactPercentages[first] - floor(exactPercentages[first])
            let secondRemainder = exactPercentages[second] - floor(exactPercentages[second])

            if firstRemainder == secondRemainder {
                return first < second
            }

            return firstRemainder > secondRemainder
        }

        for index in indicesByRemainder.prefix(remainderCount) {
            roundedPercentages[index] += 1
        }

        return roundedPercentages
    }
}
