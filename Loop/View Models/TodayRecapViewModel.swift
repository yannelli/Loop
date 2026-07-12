//
//  TodayRecapViewModel.swift
//  Loop
//

import Combine
import Foundation
import HealthKit
import LoopKit

protocol TodayRecapDataSource: AnyObject {
    var todayRecapGlucoseUnit: HKUnit { get }

    func fetchTodayRecapGlucose(
        start: Date,
        end: Date,
        completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void
    )

    func fetchTodayRecapCarbs(
        start: Date,
        end: Date,
        completion: @escaping (CarbStoreResult<[StoredCarbEntry]>) -> Void
    )

    func fetchTodayRecapDoses(
        start: Date,
        end: Date,
        completion: @escaping (DoseStoreResult<[DoseEntry]>) -> Void
    )
}

@MainActor
final class TodayRecapViewModel: ObservableObject {
    @Published private(set) var glucoseState: TodayRecapSourceState<TodayRecapGlucoseMetrics> = .loading
    @Published private(set) var carbsState: TodayRecapSourceState<Double> = .loading
    @Published private(set) var insulinState: TodayRecapSourceState<TodayRecapInsulinMetrics> = .loading
    @Published private(set) var queryContext: TodayRecapQueryContext?
    @Published private(set) var lastUpdated: Date?

    var glucoseUnit: HKUnit {
        dataSource?.todayRecapGlucoseUnit ?? .milligramsPerDeciliter
    }

    var isLoading: Bool {
        lastUpdated == nil
    }

    private weak var dataSource: TodayRecapDataSource?
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var activeRequestIdentifier: UUID?
    private var refreshCompletions: [() -> Void] = []
    private var pendingSourceCount = 0

    init(
        dataSource: TodayRecapDataSource,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.dataSource = dataSource
        self.now = now
        self.calendar = calendar
    }

    func reload() {
        startReload()
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            startReload {
                continuation.resume()
            }
        }
    }

    func cancelRefresh() {
        activeRequestIdentifier = nil
        completeRefreshes()
    }

    private func startReload(completion: (() -> Void)? = nil) {
        guard let dataSource else {
            glucoseState = .unavailable
            carbsState = .unavailable
            insulinState = .unavailable
            activeRequestIdentifier = nil
            completion?()
            completeRefreshes()
            return
        }

        if let completion {
            refreshCompletions.append(completion)
        }
        let requestIdentifier = UUID()
        let context = TodayRecapQueryContext(now: now(), calendar: calendar())
        activeRequestIdentifier = requestIdentifier
        pendingSourceCount = 3
        queryContext = context
        lastUpdated = nil
        glucoseState = .loading
        carbsState = .loading
        insulinState = .loading

        dataSource.fetchTodayRecapGlucose(start: context.startDate, end: context.endDate) { [weak self] result in
            Task { @MainActor in
                guard let self, self.activeRequestIdentifier == requestIdentifier else {
                    return
                }

                switch result {
                case .success(let samples):
                    if let metrics = TodayRecapCalculator.glucoseMetrics(from: samples, in: context) {
                        self.glucoseState = .available(metrics)
                    } else if TodayRecapCalculator.displayOnlyCount(from: samples, in: context) > 0 {
                        self.glucoseState = .excluded(TodayRecapCalculator.displayOnlyCount(from: samples, in: context))
                    } else {
                        self.glucoseState = .noData
                    }
                case .failure:
                    self.glucoseState = .unavailable
                }

                self.sourceDidFinish(for: requestIdentifier)
            }
        }

        dataSource.fetchTodayRecapCarbs(start: context.startDate, end: context.endDate) { [weak self] result in
            Task { @MainActor in
                guard let self, self.activeRequestIdentifier == requestIdentifier else {
                    return
                }

                switch result {
                case .success(let entries):
                    self.carbsState = .available(TodayRecapCalculator.totalCarbs(from: entries))
                case .failure:
                    self.carbsState = .unavailable
                }

                self.sourceDidFinish(for: requestIdentifier)
            }
        }

        dataSource.fetchTodayRecapDoses(start: context.startDate, end: context.endDate) { [weak self] result in
            Task { @MainActor in
                guard let self, self.activeRequestIdentifier == requestIdentifier else {
                    return
                }

                switch result {
                case .success(let doses):
                    self.insulinState = .available(TodayRecapCalculator.totalInsulin(from: doses, in: context))
                case .failure:
                    self.insulinState = .unavailable
                }

                self.sourceDidFinish(for: requestIdentifier)
            }
        }
    }

    private func sourceDidFinish(for requestIdentifier: UUID) {
        guard activeRequestIdentifier == requestIdentifier else {
            return
        }

        pendingSourceCount -= 1
        guard pendingSourceCount == 0 else {
            return
        }

        lastUpdated = now()
        activeRequestIdentifier = nil
        completeRefreshes()
    }

    private func completeRefreshes() {
        let completions = refreshCompletions
        refreshCompletions = []
        completions.forEach { $0() }
    }
}

extension DeviceDataManager: TodayRecapDataSource {
    var todayRecapGlucoseUnit: HKUnit {
        displayGlucosePreference.unit
    }

    func fetchTodayRecapGlucose(
        start: Date,
        end: Date,
        completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void
    ) {
        glucoseStore.getGlucoseSamples(start: start, end: end, completion: completion)
    }

    func fetchTodayRecapCarbs(
        start: Date,
        end: Date,
        completion: @escaping (CarbStoreResult<[StoredCarbEntry]>) -> Void
    ) {
        carbStore.getCarbEntries(start: start, end: end, completion: completion)
    }

    func fetchTodayRecapDoses(
        start: Date,
        end: Date,
        completion: @escaping (DoseStoreResult<[DoseEntry]>) -> Void
    ) {
        doseStore.getNormalizedDoseEntries(start: start, end: end, completion: completion)
    }
}
