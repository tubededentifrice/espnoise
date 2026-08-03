import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var syncManager: NoiseSyncManager

    var body: some View {
        NavigationStack {
            List {
                Section("Global Settings") {
                    NavigationLink {
                        GlobalSettingsView(syncManager: syncManager)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Edit all global settings")
                            Text("Sampling values are global for all devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Add Device", systemImage: "plus.circle") {
                        syncManager.addDevice()
                    }
                    LabeledContent("Setup", value: syncManager.setupText)
                        .font(.caption)
                }

                Section("Devices") {
                    if syncManager.devices.isEmpty {
                        Text("No devices are added.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(syncManager.devices) { device in
                        NavigationLink {
                            DeviceSettingsView(
                                syncManager: syncManager,
                                deviceID: device.id
                            )
                        } label: {
                            DeviceRow(device: device)
                        }
                    }
                }

                if let error = syncManager.lastError {
                    Section("Needs Attention") {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Privacy") {
                    Text("ESPNoise uses Bluetooth only. It does not use the Internet, location, accounts, analytics, or raw microphone audio.")
                        .font(.footnote)
                    Text("iOS controls background work. Keep the app installed and do not force it to close.")
                        .font(.footnote)
                }
            }
            .navigationTitle("ESPNoise")
        }
    }
}

private struct DeviceRow: View {
    let device: NoiseDeviceViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.name).font(.headline)
                Spacer()
                Text(device.syncText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(syncColor)
            }
            Text(device.isConnected ? "In range" : "Out of range")
                .font(.caption)
                .foregroundStyle(device.isConnected ? .green : .secondary)
            if device.connectionText != "Connected" {
                Text(device.connectionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let alarm = device.alarmText {
                Text("Current state: \(alarm)").font(.caption)
            }
            Text("Last sync: \(lastSyncText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let error = device.lastError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var lastSyncText: String {
        guard let date = device.lastSyncDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var syncColor: Color {
        switch device.syncText {
        case "Synchronized": .green
        case "Error": .red
        default: .orange
        }
    }
}

struct GlobalSettingsView: View {
    @ObservedObject var syncManager: NoiseSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoiseSettings
    @State private var errorText: String?
    @State private var resetText: String?

    init(syncManager: NoiseSyncManager) {
        self.syncManager = syncManager
        _draft = State(initialValue: syncManager.globalSettings)
    }

    var body: some View {
        Form {
            SettingsControls(settings: $draft, includesSampling: true)
            if let errorText {
                Section("Needs Attention") { Text(errorText).foregroundStyle(.red) }
            }
            if let resetText {
                Section { Text(resetText).foregroundStyle(.secondary) }
            }
            Section {
                Button("Save Global Settings") {
                    do {
                        try syncManager.saveGlobalSettings(draft)
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                Button("Reset Global Values to Defaults") {
                    draft = NoiseSettings()
                    errorText = nil
                    resetText =
                        "Default values are ready. Select Save Global Settings to apply them. Device overrides stay unchanged."
                }
            } footer: {
                Text("A change marks only devices that use the changed value as pending.")
            }
        }
        .navigationTitle("Global Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, newValue in
            if resetText != nil, newValue != NoiseSettings() {
                resetText = nil
            }
        }
    }
}

struct DeviceSettingsView: View {
    @ObservedObject var syncManager: NoiseSyncManager
    let deviceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var overrides = DeviceOverrides()
    @State private var errorText: String?
    @State private var savedText: String?
    @State private var showRemove = false
    @State private var loadedName = ""

    var body: some View {
        Form {
            if let device = syncManager.devices.first(where: { $0.id == deviceID }) {
                let previewSettings = overrides.applying(
                    to: syncManager.globalSettings
                )
                let savedSettings = syncManager.effectiveSettings(id: deviceID)
                LiveNoisePanel(
                    device: device,
                    settings: previewSettings,
                    rulesAreCurrent: device.settingsAreApplied
                        && previewSettings == savedSettings
                )

                Section("Device") {
                    TextField("Custom name", text: $name)
                    LabeledContent("Connection", value: device.connectionText)
                    LabeledContent("Sync", value: device.syncText)
                    if let alarm = device.alarmText {
                        LabeledContent("Current state", value: alarm)
                    }
                    Button("Send Settings Now") { syncManager.syncNow(id: deviceID) }
                }
            }

            OverrideControls(
                overrides: $overrides,
                global: syncManager.globalSettings
            )

            Section {
                globalValue("K sample duration", "\(syncManager.globalSettings.sampleDurationMilliseconds) ms")
                globalValue("N sample period", "\(syncManager.globalSettings.samplePeriodMilliseconds) ms")
                globalValue("Decision window", "\(syncManager.globalSettings.decisionWindowMilliseconds) ms")
                globalValue("X trigger percent", "\(syncManager.globalSettings.triggerPercent)%")
            } header: {
                Text("Global Sampling Values")
            } footer: {
                Text("These values are global. Change them on the Global Settings page.")
            }

            if let errorText {
                Section("Needs Attention") { Text(errorText).foregroundStyle(.red) }
            }
            if let savedText {
                Section { Text(savedText).foregroundStyle(.green) }
            }

            Section {
                Button("Save Name and Settings") { save() }
                Button("Reset All Overrides") {
                    do {
                        try syncManager.resetOverrides(id: deviceID)
                        overrides = DeviceOverrides()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                Button("Remove Device", role: .destructive) { showRemove = true }
            }
        }
        .navigationTitle(name.isEmpty ? "Device" : name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onChange(of: syncedDeviceName) { oldValue, newValue in
            guard let newValue, name == loadedName || name == oldValue else {
                return
            }
            name = newValue
            loadedName = newValue
        }
        .confirmationDialog(
            "Remove this device?",
            isPresented: $showRemove,
            titleVisibility: .visible
        ) {
            Button("Remove Device", role: .destructive) {
                syncManager.removeDevice(id: deviceID)
                dismiss()
            }
        } message: {
            Text("You must pair the device again if you want to add it later.")
        }
    }

    @ViewBuilder
    private func globalValue(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private func load() {
        guard let record = syncManager.deviceRecord(id: deviceID) else { return }
        name = record.customName
        loadedName = record.customName
        overrides = record.overrides
    }

    private var syncedDeviceName: String? {
        syncManager.devices.first(where: { $0.id == deviceID })?.name
    }

    private func save() {
        guard let cleanName = DeviceNameValidation.normalizedUserName(name)
        else {
            errorText =
                "Enter a name of 18 UTF-8 bytes or less. The form Device XXXX is reserved for the hardware name."
            savedText = nil
            return
        }
        do {
            try syncManager.saveDevice(
                id: deviceID,
                name: cleanName,
                overrides: overrides
            )
            name = cleanName
            loadedName = cleanName
            errorText = nil
            savedText =
                "Saved on this iPhone. The device name and settings will synchronize when the device is available."
        } catch {
            errorText = error.localizedDescription
            savedText = nil
        }
    }
}

private struct SettingsControls: View {
    @Binding var settings: NoiseSettings
    let includesSampling: Bool

    var body: some View {
        Section("Output") {
            SettingSlider(
                title: "LED brightness",
                valueText: "\(settings.brightnessPercent)%",
                value: uint8(\.brightnessPercent),
                range: 0...100,
                step: 1
            )
            SettingSlider(
                title: "Buzzer volume",
                valueText: "\(settings.buzzerPercent)%",
                value: uint8(\.buzzerPercent),
                range: 0...100,
                step: 1
            )
            SettingSlider(
                title: "Mute duration",
                valueText: durationText(settings.muteDurationSeconds),
                value: minutes(\.muteDurationSeconds),
                range: 1...1_440,
                step: 0.5
            )
        }
        Section("Thresholds") {
            ThresholdOverview(
                greenTenths: settings.greenThresholdTenths,
                orangeTenths: settings.orangeThresholdTenths,
                redTenths: settings.redThresholdTenths
            )
            threshold(
                "Green begins",
                kind: .green,
                color: .green
            )
            threshold(
                "Orange begins",
                kind: .orange,
                color: .orange
            )
            threshold(
                "Red begins",
                kind: .red,
                color: .red
            )
            Text("All three controls use the same scale. Move a threshold right for a louder trigger. They stay in Green, Orange, Red order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if includesSampling {
            Section("Sampling") {
                SettingSlider(
                    title: "K sample duration",
                    valueText: secondsText(settings.sampleDurationMilliseconds),
                    value: sampleDuration,
                    range: 0.001...max(0.001, Double(settings.samplePeriodMilliseconds) / 1_000),
                    step: 0.001
                )
                SettingSlider(
                    title: "N sample period",
                    valueText: secondsText(settings.samplePeriodMilliseconds),
                    value: samplePeriod,
                    range: max(0.001, Double(settings.sampleDurationMilliseconds) / 1_000)...60,
                    step: 0.001
                )
                SettingSlider(
                    title: "Decision history",
                    valueText: "\(historyCount) observations (\(secondsText(settings.decisionWindowMilliseconds)))",
                    value: history,
                    range: 2...Double(maximumHistoryCount),
                    step: 1
                )
                SettingSlider(
                    title: "X trigger level",
                    valueText: "More than \(settings.triggerPercent)%",
                    value: uint8(\.triggerPercent),
                    range: Double(minimumTriggerPercent)...99,
                    step: 1
                )
            }
        }
    }

    @ViewBuilder
    private func threshold(
        _ label: String,
        kind: ThresholdKind,
        color: Color
    ) -> some View {
        let value = thresholdValue(kind)
        SettingSlider(
            title: label,
            valueText: String(
                format: "%.1f",
                value.wrappedValue
            ),
            value: value,
            range: NoiseLevelScale.minimum...NoiseLevelScale.maximum,
            step: 0.5,
            tint: color
        )
    }

    private func uint8(
        _ keyPath: WritableKeyPath<NoiseSettings, UInt8>
    ) -> Binding<Double> {
        Binding(
            get: { Double(settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = UInt8($0.rounded()) }
        )
    }

    private func thresholdValue(_ kind: ThresholdKind) -> Binding<Double> {
        Binding(
            get: {
                NoiseLevelScale.positiveLevel(
                    fromDbfsTenths: settings[keyPath: kind.keyPath]
                )
            },
            set: { newValue in
                let candidate = NoiseLevelScale.dbfsTenths(
                    fromPositiveLevel: newValue
                )
                switch kind {
                case .green:
                    settings.greenThresholdTenths = min(
                        candidate,
                        settings.orangeThresholdTenths - 5
                    )
                case .orange:
                    settings.orangeThresholdTenths = min(
                        max(candidate, settings.greenThresholdTenths + 5),
                        settings.redThresholdTenths - 5
                    )
                case .red:
                    settings.redThresholdTenths = max(
                        candidate,
                        settings.orangeThresholdTenths + 5
                    )
                }
            }
        )
    }

    private func minutes(
        _ keyPath: WritableKeyPath<NoiseSettings, UInt32>
    ) -> Binding<Double> {
        Binding(
            get: { Double(settings[keyPath: keyPath]) / 60 },
            set: { settings[keyPath: keyPath] = UInt32(($0 * 60).rounded()) }
        )
    }

    private var sampleDuration: Binding<Double> {
        Binding(
            get: { Double(settings.sampleDurationMilliseconds) / 1_000 },
            set: {
                settings.sampleDurationMilliseconds = UInt32(($0 * 1_000).rounded())
            }
        )
    }

    private var samplePeriod: Binding<Double> {
        Binding(
            get: { Double(settings.samplePeriodMilliseconds) / 1_000 },
            set: { newSeconds in
                let oldCount = historyCount
                let newPeriod = UInt32((newSeconds * 1_000).rounded())
                settings.samplePeriodMilliseconds = newPeriod
                settings.sampleDurationMilliseconds = min(
                    settings.sampleDurationMilliseconds,
                    newPeriod
                )
                let count = min(oldCount, maximumHistoryCount)
                settings.decisionWindowMilliseconds = newPeriod * UInt32(count)
                clampTriggerPercent()
            }
        )
    }

    private var history: Binding<Double> {
        Binding(
            get: { Double(historyCount) },
            set: {
                let count = Int($0.rounded())
                settings.decisionWindowMilliseconds =
                    settings.samplePeriodMilliseconds * UInt32(count)
                clampTriggerPercent()
            }
        )
    }

    private var historyCount: Int {
        guard settings.samplePeriodMilliseconds > 0 else { return 2 }
        return max(
            2,
            Int(settings.decisionWindowMilliseconds /
                settings.samplePeriodMilliseconds)
        )
    }

    private var maximumHistoryCount: Int {
        guard settings.samplePeriodMilliseconds > 0 else { return 120 }
        return max(
            2,
            min(120, Int(600_000 / settings.samplePeriodMilliseconds))
        )
    }

    private var minimumTriggerPercent: UInt8 {
        UInt8((100 + historyCount - 1) / historyCount)
    }

    private func clampTriggerPercent() {
        settings.triggerPercent = max(
            settings.triggerPercent,
            minimumTriggerPercent
        )
    }
}

private struct OverrideControls: View {
    @Binding var overrides: DeviceOverrides
    let global: NoiseSettings

    var body: some View {
        Section("Device Overrides") {
            percentOverride(
                "LED brightness",
                value: $overrides.brightnessPercent,
                inherited: global.brightnessPercent,
                range: 0...100
            )
            percentOverride(
                "Buzzer volume",
                value: $overrides.buzzerPercent,
                inherited: global.buzzerPercent,
                range: 0...100
            )
            ThresholdOverview(
                greenTenths: effectiveGreenThreshold,
                orangeTenths: effectiveOrangeThreshold,
                redTenths: effectiveRedThreshold
            )
            thresholdOverride(
                "Green",
                kind: .green,
                value: $overrides.greenThresholdTenths,
                inherited: global.greenThresholdTenths,
                color: .green
            )
            thresholdOverride(
                "Orange",
                kind: .orange,
                value: $overrides.orangeThresholdTenths,
                inherited: global.orangeThresholdTenths,
                color: .orange
            )
            thresholdOverride(
                "Red",
                kind: .red,
                value: $overrides.redThresholdTenths,
                inherited: global.redThresholdTenths,
                color: .red
            )
            Text("These controls use the same quieter-to-louder scale. Values without an override come from Global Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            toggle("Mute duration", isOn: Binding(
                get: { overrides.muteDurationSeconds != nil },
                set: { overrides.muteDurationSeconds = $0 ? global.muteDurationSeconds : nil }
            ))
            if overrides.muteDurationSeconds != nil {
                let value = overrides.muteDurationSeconds ?? global.muteDurationSeconds
                SettingSlider(
                    title: "Mute duration",
                    valueText: durationText(value),
                    value: Binding(
                        get: { Double(overrides.muteDurationSeconds ?? global.muteDurationSeconds) / 60 },
                        set: { overrides.muteDurationSeconds = UInt32(($0 * 60).rounded()) }
                    ),
                    range: 1...1_440,
                    step: 0.5
                )
            } else {
                Text("Inherited value: \(durationText(global.muteDurationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var effectiveGreenThreshold: Int16 {
        overrides.greenThresholdTenths ?? global.greenThresholdTenths
    }

    private var effectiveOrangeThreshold: Int16 {
        overrides.orangeThresholdTenths ?? global.orangeThresholdTenths
    }

    private var effectiveRedThreshold: Int16 {
        overrides.redThresholdTenths ?? global.redThresholdTenths
    }

    @ViewBuilder
    private func percentOverride(
        _ label: String,
        value: Binding<UInt8?>,
        inherited: UInt8,
        range: ClosedRange<UInt8>
    ) -> some View {
        toggle("Override \(label)", isOn: Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? inherited : nil }
        ))
        if value.wrappedValue != nil {
            SettingSlider(
                title: label,
                valueText: "\(value.wrappedValue ?? inherited)%",
                value: Binding(
                    get: { Double(value.wrappedValue ?? inherited) },
                    set: { value.wrappedValue = UInt8($0.rounded()) }
                ),
                range: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        } else {
            Text("Inherited value: \(inherited)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thresholdOverride(
        _ label: String,
        kind: ThresholdKind,
        value: Binding<Int16?>,
        inherited: Int16,
        color: Color
    ) -> some View {
        toggle("Override \(label) threshold", isOn: Binding(
            get: { value.wrappedValue != nil },
            set: {
                value.wrappedValue = $0 ? inherited : nil
                normalizeThresholdOverrides()
            }
        ))
        if value.wrappedValue != nil {
            SettingSlider(
                title: "\(label) begins",
                valueText: String(
                    format: "%.1f",
                    NoiseLevelScale.positiveLevel(
                        fromDbfsTenths: value.wrappedValue ?? inherited
                    )
                ),
                value: Binding(
                    get: {
                        NoiseLevelScale.positiveLevel(
                            fromDbfsTenths: value.wrappedValue ?? inherited
                        )
                    },
                    set: { newValue in
                        let candidate = NoiseLevelScale.dbfsTenths(
                            fromPositiveLevel: newValue
                        )
                        switch kind {
                        case .green:
                            value.wrappedValue = min(
                                candidate,
                                effectiveOrangeThreshold - 5
                            )
                        case .orange:
                            value.wrappedValue = min(
                                max(candidate, effectiveGreenThreshold + 5),
                                effectiveRedThreshold - 5
                            )
                        case .red:
                            value.wrappedValue = max(
                                candidate,
                                effectiveOrangeThreshold + 5
                            )
                        }
                    }
                ),
                range: NoiseLevelScale.minimum...NoiseLevelScale.maximum,
                step: 0.5,
                tint: color
            )
        } else {
            Text("Inherited \(label.lowercased()): \(NoiseLevelScale.positiveLevel(fromDbfsTenths: inherited), specifier: "%.1f")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
    }

    private func normalizeThresholdOverrides() {
        for _ in 0..<4 {
            if effectiveGreenThreshold >= effectiveOrangeThreshold {
                if overrides.greenThresholdTenths != nil {
                    overrides.greenThresholdTenths = effectiveOrangeThreshold - 5
                } else if overrides.orangeThresholdTenths != nil {
                    overrides.orangeThresholdTenths = effectiveGreenThreshold + 5
                }
            }
            if effectiveOrangeThreshold >= effectiveRedThreshold {
                if overrides.redThresholdTenths != nil {
                    overrides.redThresholdTenths = effectiveOrangeThreshold + 5
                } else if overrides.orangeThresholdTenths != nil {
                    overrides.orangeThresholdTenths = effectiveRedThreshold - 5
                }
            }
            if let green = overrides.greenThresholdTenths {
                overrides.greenThresholdTenths = min(0, max(-1_200, green))
            }
            if let orange = overrides.orangeThresholdTenths {
                overrides.orangeThresholdTenths = min(0, max(-1_200, orange))
            }
            if let red = overrides.redThresholdTenths {
                overrides.redThresholdTenths = min(0, max(-1_200, red))
            }
        }

        guard effectiveGreenThreshold < effectiveOrangeThreshold,
              effectiveOrangeThreshold < effectiveRedThreshold else {
            overrides.greenThresholdTenths = nil
            overrides.orangeThresholdTenths = nil
            overrides.redThresholdTenths = nil
            return
        }
    }
}

private struct SettingSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .padding(.vertical, 2)
    }
}

private struct LiveNoisePanel: View {
    let device: NoiseDeviceViewState
    let settings: NoiseSettings
    let rulesAreCurrent: Bool

    var body: some View {
        Section("Live Noise") {
            if let latest = device.measurements.last {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest measurement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(latest.level, format: .number.precision(.fractionLength(1)))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(levelReached(latest.level))
                            .font(.headline)
                            .foregroundStyle(levelColor(latest.level))
                        if device.latestStatus?.isSampling == true {
                            Label("Measuring now", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else {
                            Text(latest.date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Chart {
                    ForEach(device.measurements) { measurement in
                        LineMark(
                            x: .value("Time", measurement.date),
                            y: .value("Noise level", measurement.level)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.linear)
                        PointMark(
                            x: .value("Time", measurement.date),
                            y: .value("Noise level", measurement.level)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(18)
                    }
                    thresholdRule("Green", value: greenLevel, color: .green)
                    thresholdRule("Orange", value: orangeLevel, color: .orange)
                    thresholdRule("Red", value: redLevel, color: .red)
                }
                .chartYScale(domain: NoiseLevelScale.minimum...NoiseLevelScale.maximum)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100, 120])
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .frame(height: 220)
                .accessibilityLabel("Recent positive noise measurements and alarm thresholds")

                thresholdLegend
                if !rulesAreCurrent {
                    Text("The threshold lines are a preview. Save and synchronize these settings before you use the device counts.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                historySummary
            } else {
                ContentUnavailableView {
                    Label("Waiting for a measurement", systemImage: "waveform")
                } description: {
                    Text(device.isConnected
                         ? "The graph will update during the next observation."
                         : "Bring the device in range to receive measurements.")
                }
            }
        }
    }

    @ChartContentBuilder
    private func thresholdRule(
        _ label: String,
        value: Double,
        color: Color
    ) -> some ChartContent {
        RuleMark(y: .value("\(label) threshold", value))
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
    }

    private var thresholdLegend: some View {
        HStack {
            legendItem("Green", value: greenLevel, color: .green)
            Spacer()
            legendItem("Orange", value: orangeLevel, color: .orange)
            Spacer()
            legendItem("Red", value: redLevel, color: .red)
        }
    }

    private var historySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = device.latestStatus, rulesAreCurrent {
                HStack {
                    countItem("Green", status.greenSampleCount, color: .green)
                    Spacer()
                    countItem("Orange", status.orangeSampleCount, color: .orange)
                    Spacer()
                    countItem("Red", status.redSampleCount, color: .red)
                }
                Text("History: \(status.historyCount) of \(historyCapacity) observations. After the history is full, an alarm starts when \(requiredCount) observations reach the same threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if device.latestStatus != nil {
                Text("Device counts are hidden until the saved settings synchronize.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("The positive level is relative to the digital microphone. It is not calibrated dB SPL. No audio is sent to the phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func legendItem(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(value, specifier: "%.1f")")
        }
        .font(.caption)
    }

    private func countItem(_ label: String, _ count: UInt8, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)/\(historyCapacity)")
                .font(.headline)
                .monospacedDigit()
            Text(label).font(.caption2)
        }
        .foregroundStyle(color)
    }

    private var greenLevel: Double {
        NoiseLevelScale.positiveLevel(fromDbfsTenths: settings.greenThresholdTenths)
    }

    private var orangeLevel: Double {
        NoiseLevelScale.positiveLevel(fromDbfsTenths: settings.orangeThresholdTenths)
    }

    private var redLevel: Double {
        NoiseLevelScale.positiveLevel(fromDbfsTenths: settings.redThresholdTenths)
    }

    private var historyCapacity: Int {
        guard settings.samplePeriodMilliseconds > 0 else { return 0 }
        return Int(settings.decisionWindowMilliseconds /
                   settings.samplePeriodMilliseconds)
    }

    private var requiredCount: Int {
        historyCapacity * Int(settings.triggerPercent) / 100 + 1
    }

    private func levelReached(_ level: Double) -> String {
        let result: String
        if level >= redLevel { result = "Red reached" }
        else if level >= orangeLevel { result = "Orange reached" }
        else if level >= greenLevel { result = "Green reached" }
        else { result = "Below Green" }
        return rulesAreCurrent ? result : "Preview: \(result)"
    }

    private func levelColor(_ level: Double) -> Color {
        if level >= redLevel { return .red }
        if level >= orangeLevel { return .orange }
        if level >= greenLevel { return .green }
        return .secondary
    }
}

private enum ThresholdKind {
    case green
    case orange
    case red

    var keyPath: WritableKeyPath<NoiseSettings, Int16> {
        switch self {
        case .green: \.greenThresholdTenths
        case .orange: \.orangeThresholdTenths
        case .red: \.redThresholdTenths
        }
    }
}

private struct ThresholdOverview: View {
    let greenTenths: Int16
    let orangeTenths: Int16
    let redTenths: Int16

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("0 · Quieter")
                Spacer()
                Text("Louder · 120")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let greenX = position(greenTenths, width: geometry.size.width)
                let orangeX = position(orangeTenths, width: geometry.size.width)
                let redX = position(redTenths, width: geometry.size.width)

                HStack(spacing: 0) {
                    Color.secondary.opacity(0.2).frame(width: greenX)
                    Color.green.frame(width: orangeX - greenX)
                    Color.orange.frame(width: redX - orangeX)
                    Color.red.frame(width: geometry.size.width - redX)
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Noise threshold order")
            .accessibilityValue("Green, then orange, then red as noise becomes louder")
        }
        .padding(.vertical, 2)
    }

    private func position(_ tenths: Int16, width: Double) -> Double {
        let value = min(
            NoiseLevelScale.maximum,
            max(
                NoiseLevelScale.minimum,
                NoiseLevelScale.positiveLevel(fromDbfsTenths: tenths)
            )
        )
        return width * value / NoiseLevelScale.maximum
    }
}

private func secondsText(_ milliseconds: UInt32) -> String {
    if milliseconds % 1_000 == 0 {
        return "\(milliseconds / 1_000) s"
    }
    if milliseconds % 100 == 0 {
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
    }
    return String(format: "%.3f s", Double(milliseconds) / 1_000)
}

private func durationText(_ seconds: UInt32) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    if minutes < 60 {
        return remainingSeconds == 0
            ? "\(minutes) min"
            : "\(minutes) min \(remainingSeconds) s"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0
        ? "\(hours) h"
        : "\(hours) h \(remainingMinutes) min"
}
