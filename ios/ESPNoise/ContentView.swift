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
            Section {
                Button("Save Global Settings") {
                    do {
                        try syncManager.saveGlobalSettings(draft)
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
            } footer: {
                Text("A change marks only devices that use the changed value as pending.")
            }
        }
        .navigationTitle("Global Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DeviceSettingsView: View {
    @ObservedObject var syncManager: NoiseSyncManager
    let deviceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var overrides = DeviceOverrides()
    @State private var errorText: String?
    @State private var showRemove = false

    var body: some View {
        Form {
            if let device = syncManager.devices.first(where: { $0.id == deviceID }) {
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

            Section {
                Button("Save Device Settings") { save() }
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
        overrides = record.overrides
    }

    private func save() {
        guard DeviceNameValidation.normalized(name) != nil else {
            errorText = "Enter a name with 1 through 40 characters."
            return
        }
        do {
            try syncManager.saveDevice(id: deviceID, name: name, overrides: overrides)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
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
            threshold(
                "Green",
                keyPath: \.greenThresholdTenths,
                range: -120...(Double(settings.orangeThresholdTenths) / 10 - 0.5)
            )
            threshold(
                "Orange",
                keyPath: \.orangeThresholdTenths,
                range: (Double(settings.greenThresholdTenths) / 10 + 0.5)...(Double(settings.redThresholdTenths) / 10 - 0.5)
            )
            threshold(
                "Red",
                keyPath: \.redThresholdTenths,
                range: (Double(settings.orangeThresholdTenths) / 10 + 0.5)...0
            )
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
        keyPath: WritableKeyPath<NoiseSettings, Int16>,
        range: ClosedRange<Double>
    ) -> some View {
        SettingSlider(
            title: "\(label) threshold",
            valueText: String(
                format: "%.1f dBFS",
                Double(settings[keyPath: keyPath]) / 10
            ),
            value: tenths(keyPath),
            range: range,
            step: 0.5
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

    private func tenths(
        _ keyPath: WritableKeyPath<NoiseSettings, Int16>
    ) -> Binding<Double> {
        Binding(
            get: { Double(settings[keyPath: keyPath]) / 10 },
            set: { settings[keyPath: keyPath] = Int16(($0 * 10).rounded()) }
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
            thresholdOverride(
                "Green threshold",
                value: $overrides.greenThresholdTenths,
                inherited: global.greenThresholdTenths,
                range: safeRange(
                    -120,
                    Double(effectiveOrangeThreshold) / 10 - 0.5
                )
            )
            thresholdOverride(
                "Orange threshold",
                value: $overrides.orangeThresholdTenths,
                inherited: global.orangeThresholdTenths,
                range: safeRange(
                    Double(effectiveGreenThreshold) / 10 + 0.5,
                    Double(effectiveRedThreshold) / 10 - 0.5
                )
            )
            thresholdOverride(
                "Red threshold",
                value: $overrides.redThresholdTenths,
                inherited: global.redThresholdTenths,
                range: safeRange(
                    Double(effectiveOrangeThreshold) / 10 + 0.5,
                    0
                )
            )
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

    private func safeRange(_ lower: Double, _ upper: Double) -> ClosedRange<Double> {
        min(lower, upper)...max(lower, upper)
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
        value: Binding<Int16?>,
        inherited: Int16,
        range: ClosedRange<Double>
    ) -> some View {
        toggle("Override \(label)", isOn: Binding(
            get: { value.wrappedValue != nil },
            set: {
                value.wrappedValue = $0 ? inherited : nil
                normalizeThresholdOverrides()
            }
        ))
        if value.wrappedValue != nil {
            SettingSlider(
                title: label,
                valueText: String(
                    format: "%.1f dBFS",
                    Double(value.wrappedValue ?? inherited) / 10
                ),
                value: Binding(
                    get: { Double(value.wrappedValue ?? inherited) / 10 },
                    set: { value.wrappedValue = Int16(($0 * 10).rounded()) }
                ),
                range: range,
                step: 0.5
            )
        } else {
            Text("Inherited value: \(Double(inherited) / 10, specifier: "%.1f") dBFS")
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
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .padding(.vertical, 2)
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
