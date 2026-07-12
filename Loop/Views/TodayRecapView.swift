//
//  TodayRecapView.swift
//  Loop
//

import Combine
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

struct TodayRecapView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.glucoseTintColor) private var glucoseTintColor
    @Environment(\.carbTintColor) private var carbTintColor
    @Environment(\.insulinTintColor) private var insulinTintColor

    @ObservedObject var viewModel: TodayRecapViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    glucoseCard
                    recordedTotalsCard
                    safetyNote
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitle(Text("Today Recap", comment: "Title for the daily recorded-data recap screen"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: viewModel.reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel(Text("Refresh recap", comment: "Accessibility label for refreshing the daily recap"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: dismiss) {
                        Text("Done", comment: "Button label for dismissing the daily recap").bold()
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: viewModel.reload)
        .onDisappear(perform: viewModel.cancelRefresh)
        .onReceive(NotificationCenter.default.publisher(for: .LoopDataUpdated)) { _ in viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in viewModel.reload() }
    }

    @ViewBuilder
    private var glucoseCard: some View {
        switch viewModel.glucoseState {
        case .loading:
            recapCard {
                loadingRow(title: NSLocalizedString("Recorded Glucose", comment: "Daily recap glucose section title"))
            }
        case .noData:
            recapCard {
                sectionHeader(
                    title: NSLocalizedString("Recorded Glucose", comment: "Daily recap glucose section title"),
                    symbol: "drop.fill",
                    color: glucoseTintColor
                )
                Text("No recorded glucose readings yet today.", comment: "Daily recap empty glucose message")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .excluded(let count):
            recapCard {
                sectionHeader(
                    title: NSLocalizedString("Recorded Glucose", comment: "Daily recap glucose section title"),
                    symbol: "drop.fill",
                    color: glucoseTintColor
                )
                Text(displayOnlyOnlyString(count))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unavailable:
            recapCard {
                sectionHeader(
                    title: NSLocalizedString("Recorded Glucose", comment: "Daily recap glucose section title"),
                    symbol: "drop.fill",
                    color: glucoseTintColor
                )
                unavailableText
            }
        case .available(let metrics):
            recapCard {
                sectionHeader(
                    title: NSLocalizedString("Recorded Glucose", comment: "Daily recap glucose section title"),
                    symbol: "drop.fill",
                    color: glucoseTintColor
                )

                if let distribution = metrics.distribution {
                    Text(String(format: NSLocalizedString("%1$d%%", comment: "Integer percentage displayed in the daily recap. (1: percentage)"), distribution.withinPercent))
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(
                            Text(
                                String(
                                    format: NSLocalizedString("%1$d percent of recorded readings within %2$@", comment: "Daily recap accessible within-range summary. (1: percentage)(2: range)"),
                                    distribution.withinPercent,
                                    glucoseRangeString
                                )
                            )
                        )

                    Text(String(format: NSLocalizedString("of recorded readings within %1$@", comment: "Daily recap explanation for the recorded-reading percentage. (1: range)"), glucoseRangeString))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    distributionBar(distribution)
                    distributionLabels(distribution)
                } else {
                    Text(readingsRecordedString(metrics.readingCount))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("At least 12 readings are needed to show a recorded-reading distribution.", comment: "Daily recap sparse glucose explanation")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                if let average = metrics.averageMilligramsPerDeciliter,
                   let minimum = metrics.minimumMilligramsPerDeciliter,
                   let maximum = metrics.maximumMilligramsPerDeciliter
                {
                    metricTiles(average: average, minimum: minimum, maximum: maximum)
                } else {
                    Text("Exact average, lowest, and highest values are unavailable because today's readings are sensor limit values.", comment: "Daily recap explanation when only censored LOW or HIGH glucose readings are available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if metrics.censoredReadingCount > 0 {
                    Text("Sensor LOW and HIGH readings are counted in the distribution but excluded from exact average, lowest, and highest values.", comment: "Daily recap explanation for censored sensor glucose readings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                detailRow(
                    title: NSLocalizedString("Recorded readings", comment: "Daily recap glucose reading count label"),
                    value: NumberFormatter.localizedString(from: NSNumber(value: metrics.readingCount), number: .decimal)
                )
                detailRow(
                    title: NSLocalizedString("First to latest", comment: "Daily recap first and latest glucose reading label"),
                    value: String(
                        format: NSLocalizedString("%1$@ to %2$@", comment: "Daily recap format for first and latest glucose reading times. (1: first time)(2: latest time)"),
                        timeString(metrics.firstReadingDate),
                        timeString(metrics.latestReadingDate)
                    )
                )

                if let largestGap = metrics.largestGap {
                    detailRow(
                        title: NSLocalizedString("Largest observed gap", comment: "Daily recap largest glucose data gap label"),
                        value: durationString(largestGap)
                    )
                }

                if metrics.manualReadingCount > 0 {
                    detailRow(
                        title: NSLocalizedString("Manual readings included", comment: "Daily recap manual glucose reading count label"),
                        value: NumberFormatter.localizedString(from: NSNumber(value: metrics.manualReadingCount), number: .decimal)
                    )
                }

                if metrics.excludedDisplayOnlyCount > 0 {
                    detailRow(
                        title: NSLocalizedString("Display-only readings excluded", comment: "Daily recap excluded display-only reading count label"),
                        value: NumberFormatter.localizedString(from: NSNumber(value: metrics.excludedDisplayOnlyCount), number: .decimal)
                    )
                }
            }
        }
    }

    private var recordedTotalsCard: some View {
        recapCard {
            sectionHeader(
                title: NSLocalizedString("Recorded Today", comment: "Daily recap recorded totals section title"),
                symbol: "calendar",
                color: .secondary
            )

            sourceTotals

            if let lastUpdated = viewModel.lastUpdated {
                Divider()
                Text(String(format: NSLocalizedString("Loaded at %1$@", comment: "Daily recap completed-load time. (1: time)"), timeString(lastUpdated)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("About this recap", comment: "Daily recap safety note title").font(.headline)
            } icon: {
                Image(systemName: "info.circle.fill")
            }

            Text("This recap summarizes recorded data for today. It does not recommend treatment or insulin dosing.", comment: "Daily recap safety note")
                .font(.footnote)

            Text(String(format: NSLocalizedString("The %1$@ band is used only to describe recorded readings. It does not change or represent Loop dosing targets.", comment: "Daily recap fixed glucose band explanation. (1: range)"), glucoseRangeString))
                .font(.footnote)

            Text("Insulin delivery may update as pump records are reconciled. Values based on active or unresolved records are labeled as estimates.", comment: "Daily recap insulin reconciliation note")
                .font(.footnote)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func recapCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            )
    }

    private func sectionHeader(title: String, symbol: String, color: Color) -> some View {
        Label {
            Text(title).font(.headline)
        } icon: {
            Image(systemName: symbol).foregroundColor(color)
        }
    }

    private func loadingRow(title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var unavailableText: some View {
        Text("Recorded data is unavailable right now. Pull down to try again.", comment: "Daily recap unavailable data message")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distributionBar(_ distribution: TodayRecapDistribution) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.red.opacity(0.75))
                    .frame(width: geometry.size.width * CGFloat(distribution.belowPercent) / 100)
                Rectangle()
                    .fill(glucoseTintColor)
                    .frame(width: geometry.size.width * CGFloat(distribution.withinPercent) / 100)
                Rectangle()
                    .fill(Color.orange.opacity(0.8))
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func distributionLabels(_ distribution: TodayRecapDistribution) -> some View {
        Group {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 8) {
                    distributionLabel(title: NSLocalizedString("Below", comment: "Daily recap below-range label"), percent: distribution.belowPercent, count: distribution.belowCount)
                    distributionLabel(title: NSLocalizedString("Within", comment: "Daily recap within-range label"), percent: distribution.withinPercent, count: distribution.withinCount)
                    distributionLabel(title: NSLocalizedString("Above", comment: "Daily recap above-range label"), percent: distribution.abovePercent, count: distribution.aboveCount)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    distributionLabel(title: NSLocalizedString("Below", comment: "Daily recap below-range label"), percent: distribution.belowPercent, count: distribution.belowCount)
                    distributionLabel(title: NSLocalizedString("Within", comment: "Daily recap within-range label"), percent: distribution.withinPercent, count: distribution.withinCount)
                    distributionLabel(title: NSLocalizedString("Above", comment: "Daily recap above-range label"), percent: distribution.abovePercent, count: distribution.aboveCount)
                }
            }
        }
    }

    private func distributionLabel(title: String, percent: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(String(format: NSLocalizedString("%1$d%% (%2$d)", comment: "Daily recap category percentage and reading count. (1: percentage)(2: count)"), percent, count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(distributionAccessibilityString(title: title, percent: percent, count: count)))
    }

    @ViewBuilder
    private func metricTiles(average: Double, minimum: Double, maximum: Double) -> some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(spacing: 8) {
                metricTile(title: NSLocalizedString("Average", comment: "Daily recap average glucose label"), value: glucoseString(average))
                metricTile(title: NSLocalizedString("Lowest", comment: "Daily recap minimum glucose label"), value: glucoseString(minimum))
                metricTile(title: NSLocalizedString("Highest", comment: "Daily recap maximum glucose label"), value: glucoseString(maximum))
            }
        } else {
            HStack(spacing: 8) {
                metricTile(title: NSLocalizedString("Average", comment: "Daily recap average glucose label"), value: glucoseString(average))
                metricTile(title: NSLocalizedString("Lowest", comment: "Daily recap minimum glucose label"), value: glucoseString(minimum))
                metricTile(title: NSLocalizedString("Highest", comment: "Daily recap maximum glucose label"), value: glucoseString(maximum))
            }
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func sourceTotal(
        title: String,
        symbol: String,
        color: Color,
        state: TodayRecapSourceState<Double>,
        formatter: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(title).font(.caption).foregroundColor(.secondary)

            switch state {
            case .loading:
                ProgressView().frame(height: 28)
            case .available(let value):
                Text(formatter(value)).font(.title2.bold())
            case .noData:
                Text("None", comment: "Daily recap no recorded total value").font(.title2.bold())
            case .excluded:
                Text("Unavailable", comment: "Daily recap unavailable total value")
                    .font(.subheadline.bold())
            case .unavailable:
                Text("Unavailable", comment: "Daily recap unavailable total value")
                    .font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func insulinTotal(state: TodayRecapSourceState<TodayRecapInsulinMetrics>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "syringe.fill")
                .font(.title2)
                .foregroundColor(insulinTintColor)
                .accessibilityHidden(true)

            switch state {
            case .loading:
                Text("Insulin Delivery", comment: "Daily recap insulin total label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ProgressView().frame(height: 28)
            case .available(let metrics):
                Text(
                    metrics.includesEstimatedDelivery
                        ? NSLocalizedString("Estimated Insulin", comment: "Daily recap estimated insulin total label")
                        : NSLocalizedString("Reported Insulin", comment: "Daily recap reported insulin total label")
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Text(insulinString(metrics.units)).font(.title2.bold())
            case .noData:
                Text("Reported Insulin", comment: "Daily recap reported insulin total label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("None", comment: "Daily recap no recorded total value").font(.title2.bold())
            case .excluded, .unavailable:
                Text("Reported Insulin", comment: "Daily recap reported insulin total label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Unavailable", comment: "Daily recap unavailable total value")
                    .font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func glucoseString(_ value: Double) -> String {
        let unit = viewModel.glucoseUnit
        let quantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value)
        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        return formatter.string(from: quantity.doubleValue(for: unit), unit: unit) ?? "-"
    }

    private var glucoseRangeString: String {
        let unit = viewModel.glucoseUnit
        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        let lowerQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: TodayRecapCalculator.lowerBoundMilligramsPerDeciliter)
        let upperQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: TodayRecapCalculator.upperBoundMilligramsPerDeciliter)
        let lower = formatter.string(from: lowerQuantity.doubleValue(for: unit)) ?? "-"
        let upper = formatter.string(from: upperQuantity.doubleValue(for: unit)) ?? "-"
        guard unit == .millimolesPerLiter else {
            return String(
                format: NSLocalizedString("%1$@-%2$@ %3$@", comment: "Daily recap fixed glucose band with unit. (1: lower bound)(2: upper bound)(3: unit)"),
                lower,
                upper,
                unit.localizedShortUnitString
            )
        }

        return String(
            format: NSLocalizedString("70-180 mg/dL (about %1$@-%2$@ mmol/L)", comment: "Daily recap exact glucose band with approximate mmol/L conversion. (1: lower bound)(2: upper bound)"),
            lower,
            upper
        )
    }

    @ViewBuilder
    private var sourceTotals: some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: 12) {
                sourceTotal(
                    title: NSLocalizedString("Carbohydrates", comment: "Daily recap recorded carbohydrate total label"),
                    symbol: "fork.knife",
                    color: carbTintColor,
                    state: viewModel.carbsState,
                    formatter: carbString
                )
                Divider()
                insulinTotal(state: viewModel.insulinState)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                sourceTotal(
                    title: NSLocalizedString("Carbohydrates", comment: "Daily recap recorded carbohydrate total label"),
                    symbol: "fork.knife",
                    color: carbTintColor,
                    state: viewModel.carbsState,
                    formatter: carbString
                )
                Divider()
                insulinTotal(state: viewModel.insulinState)
            }
        }
    }

    private func readingsRecordedString(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("1 reading recorded", comment: "Daily recap singular sparse glucose reading count")
        }

        return String(format: NSLocalizedString("%1$d readings recorded", comment: "Daily recap plural sparse glucose reading count. (1: count)"), count)
    }

    private func displayOnlyOnlyString(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("1 display-only reading was recorded and excluded from the recap metrics.", comment: "Daily recap singular excluded-only glucose message")
        }

        return String(format: NSLocalizedString("%1$d display-only readings were recorded and excluded from the recap metrics.", comment: "Daily recap plural excluded-only glucose message. (1: count)"), count)
    }

    private func distributionAccessibilityString(title: String, percent: Int, count: Int) -> String {
        let readingCount: String
        if count == 1 {
            readingCount = NSLocalizedString("1 reading", comment: "Daily recap singular accessible reading count")
        } else {
            readingCount = String(format: NSLocalizedString("%1$d readings", comment: "Daily recap plural accessible reading count. (1: count)"), count)
        }

        return String(
            format: NSLocalizedString("%1$@ range, %2$d percent, %3$@", comment: "Daily recap accessible distribution category. (1: category)(2: percentage)(3: reading count)"),
            title,
            percent,
            readingCount
        )
    }

    private func carbString(_ value: Double) -> String {
        let formatter = QuantityFormatter(for: .gram())
        let quantity = HKQuantity(unit: .gram(), doubleValue: value)
        return formatter.string(from: quantity) ?? "-"
    }

    private func insulinString(_ value: Double) -> String {
        let formatter = QuantityFormatter(for: .internationalUnit())
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: value)
        return formatter.string(from: quantity) ?? "-"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = viewModel.queryContext?.timeZone
        return formatter.string(from: date)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= .hours(1) ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "-"
    }
}
