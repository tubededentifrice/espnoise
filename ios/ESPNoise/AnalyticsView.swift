import Charts
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var syncManager: NoiseSyncManager
    @State private var range = AnalyticsRange.week
    @State private var selectedDeviceIDs: Set<UUID> = []
    @State private var showsDeviceSelector = false
    @State private var selectionWasInitialized = false

    private var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: syncManager.devices.map { ($0.id, $0.name) })
    }

    private var snapshot: FleetAnalyticsSnapshot {
        AnalyticsEngine.snapshot(
            recordsByDevice: syncManager.analyticsByDevice,
            selectedDeviceIDs: selectedDeviceIDs,
            names: names,
            range: range
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Picker("Time range", selection: $range) {
                    ForEach(AnalyticsRange.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    showsDeviceSelector = true
                } label: {
                    HStack {
                        Label(selectionText, systemImage: "sensor.tag.radiowaves.forward")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .analyticsCard()

                if syncManager.devices.isEmpty {
                    ContentUnavailableView(
                        "No devices",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Add a device to collect noise summaries.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if !snapshot.hasData {
                    ContentUnavailableView(
                        "No summaries in this range",
                        systemImage: "clock.badge.questionmark",
                        description: Text(
                            "Keep a selected device powered. The first summary starts to fill at once. Completed summaries use 15-minute periods."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    overview
                    noiseTrend
                    stateTime
                    deviceComparison
                    activityHeatmap
                    methodNote
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Noise Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDeviceSelector) {
            AnalyticsDeviceSelector(
                devices: syncManager.devices,
                selectedDeviceIDs: $selectedDeviceIDs
            )
        }
        .onAppear { initializeSelectionIfNeeded() }
        .onChange(of: syncManager.devices.map(\.id)) { oldIDs, ids in
            let selectedAllPreviousDevices =
                selectedDeviceIDs == Set(oldIDs) && !oldIDs.isEmpty
            let available = Set(ids)
            selectedDeviceIDs.formIntersection(available)
            if selectedAllPreviousDevices
                || (selectionWasInitialized
                    && selectedDeviceIDs.isEmpty && !ids.isEmpty) {
                selectedDeviceIDs = available
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview").font(.headline)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                AnalyticsMetric(
                    title: "Average level",
                    value: snapshot.meanLevel.formatted(.number.precision(.fractionLength(1))),
                    note: "Relative 0–120 scale",
                    color: levelColor(snapshot.meanLevel)
                )
                AnalyticsMetric(
                    title: "Peak level",
                    value: snapshot.peakLevel.formatted(.number.precision(.fractionLength(1))),
                    note: "Highest 15-minute peak",
                    color: levelColor(snapshot.peakLevel)
                )
                AnalyticsMetric(
                    title: "Warning time",
                    value: snapshot.warningPercent.formatted(.number.precision(.fractionLength(1))) + "%",
                    note: "Green, orange, or red",
                    color: .orange
                )
                AnalyticsMetric(
                    title: "Red time",
                    value: snapshot.redPercent.formatted(.number.precision(.fractionLength(1))) + "%",
                    note: "Sustained red state",
                    color: .red
                )
                AnalyticsMetric(
                    title: "Data volume",
                    value: snapshot.deviceHours.formatted(.number.precision(.fractionLength(1))),
                    note: "Device-hours",
                    color: .blue
                )
                AnalyticsMetric(
                    title: "Devices with data",
                    value: "\(snapshot.devices.count)",
                    note: "Of \(selectedDeviceIDs.count) selected",
                    color: .indigo
                )
            }
        }
    }

    private var noiseTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Noise Trend").font(.headline)
            Text("The line is the time-weighted average across the selected devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(snapshot.trend) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Average", point.meanLevel)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue)
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Average", point.meanLevel)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...120)
            .chartYAxisLabel("Relative level")
            .frame(height: 220)
        }
        .analyticsCard()
    }

    private var stateTime: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State Time").font(.headline)
            Text("This chart shows when the office was in each warning state.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(statePoints) { point in
                BarMark(
                    x: .value("Time", point.date),
                    y: .value("Minutes", point.seconds / 60)
                )
                .foregroundStyle(by: .value("State", point.state))
            }
            .chartForegroundStyleScale([
                "Quiet": Color.gray.opacity(0.35),
                "Green": Color.green,
                "Orange": Color.orange,
                "Red": Color.red,
            ])
            .chartYAxisLabel("Device-minutes")
            .frame(height: 220)
        }
        .analyticsCard()
    }

    private var deviceComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Device Comparison").font(.headline)
                Spacer()
                if snapshot.devices.count > 12 {
                    Text("Top 12")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Devices are ranked by the share of time in a warning state.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(Array(snapshot.devices.prefix(12))) { device in
                BarMark(
                    x: .value("Warning time", device.warningPercent),
                    y: .value("Device", device.name)
                )
                .foregroundStyle(device.redPercent > 5 ? .red : .orange)
                .annotation(position: .trailing) {
                    Text(device.warningPercent.formatted(.number.precision(.fractionLength(0))) + "%")
                        .font(.caption2)
                }
            }
            .chartXScale(domain: 0...max(10, min(100, comparisonMaximum)))
            .chartXAxisLabel("Warning time (%)")
            .frame(height: max(180, CGFloat(min(12, snapshot.devices.count)) * 30))
        }
        .analyticsCard()
    }

    private var activityHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekday and Hour").font(.headline)
            Text("Darker warm colors show the hours with higher average levels.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(snapshot.heatmap) { cell in
                RectangleMark(
                    x: .value("Hour", cell.hour),
                    y: .value("Weekday", cell.weekdayLabel)
                )
                .foregroundStyle(levelColor(cell.meanLevel))
                .cornerRadius(2)
            }
            .chartXScale(domain: -1...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23])
            }
            .frame(height: 210)
        }
        .analyticsCard()
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Private, aggregated data", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text(
                "A device keeps at most 72 hours of 15-minute summaries. The phone keeps at most 30 days. The values are relative levels, not certified dBA. No raw microphone audio is saved or sent."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .analyticsCard()
    }

    private var statePoints: [AnalyticsStatePoint] {
        snapshot.trend.flatMap { point in
            [
                AnalyticsStatePoint(date: point.date, state: "Quiet", seconds: point.quietSeconds),
                AnalyticsStatePoint(date: point.date, state: "Green", seconds: point.greenSeconds),
                AnalyticsStatePoint(date: point.date, state: "Orange", seconds: point.orangeSeconds),
                AnalyticsStatePoint(date: point.date, state: "Red", seconds: point.redSeconds),
            ].filter { $0.seconds > 0 }
        }
    }

    private var comparisonMaximum: Double {
        (snapshot.devices.prefix(12).map(\.warningPercent).max() ?? 10) * 1.15
    }

    private var selectionText: String {
        if selectedDeviceIDs.count == syncManager.devices.count,
           !syncManager.devices.isEmpty {
            return "All devices (\(selectedDeviceIDs.count))"
        }
        if selectedDeviceIDs.count == 1,
           let id = selectedDeviceIDs.first {
            return names[id] ?? "1 device"
        }
        return "\(selectedDeviceIDs.count) devices selected"
    }

    private func initializeSelectionIfNeeded() {
        guard !selectionWasInitialized else { return }
        selectedDeviceIDs = Set(syncManager.devices.map(\.id))
        selectionWasInitialized = true
    }

    private func levelColor(_ level: Double) -> Color {
        let settings = syncManager.globalSettings
        let green = NoiseLevelScale.positiveLevel(
            fromDbfsTenths: settings.greenThresholdTenths
        )
        let orange = NoiseLevelScale.positiveLevel(
            fromDbfsTenths: settings.orangeThresholdTenths
        )
        let red = NoiseLevelScale.positiveLevel(
            fromDbfsTenths: settings.redThresholdTenths
        )
        if level >= red { return .red }
        if level >= orange { return .orange }
        if level >= green { return .green }
        return .blue
    }
}

private struct AnalyticsStatePoint: Identifiable {
    let date: Date
    let state: String
    let seconds: Double
    var id: String { "\(date.timeIntervalSince1970)-\(state)" }
}

private struct AnalyticsMetric: View {
    let title: String
    let value: String
    let note: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .analyticsCard()
    }
}

private struct AnalyticsDeviceSelector: View {
    let devices: [NoiseDeviceViewState]
    @Binding var selectedDeviceIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select All") {
                        selectedDeviceIDs = Set(devices.map(\.id))
                    }
                    Button("Clear Selection") {
                        selectedDeviceIDs.removeAll()
                    }
                }
                Section("Devices") {
                    ForEach(filteredDevices) { device in
                        Button {
                            if selectedDeviceIDs.contains(device.id) {
                                selectedDeviceIDs.remove(device.id)
                            } else {
                                selectedDeviceIDs.insert(device.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .foregroundStyle(.primary)
                                    Text(device.isConnected ? "In range" : "Out of range")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedDeviceIDs.contains(device.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Find a device")
            .navigationTitle("Choose Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredDevices: [NoiseDeviceViewState] {
        guard !searchText.isEmpty else { return devices }
        return devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private extension View {
    func analyticsCard() -> some View {
        padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
