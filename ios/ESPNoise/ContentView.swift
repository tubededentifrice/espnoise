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
            Stepper(
                "LED brightness: \(settings.brightnessPercent)%",
                value: $settings.brightnessPercent,
                in: 0...100
            )
            Stepper(
                "Buzzer volume: \(settings.buzzerPercent)%",
                value: $settings.buzzerPercent,
                in: 0...100
            )
            Stepper(
                "Mute duration: \(settings.muteDurationSeconds) s",
                value: $settings.muteDurationSeconds,
                in: 60...86_400,
                step: 30
            )
        }
        Section("Thresholds") {
            threshold("Green", value: $settings.greenThresholdTenths)
            threshold("Orange", value: $settings.orangeThresholdTenths)
            threshold("Red", value: $settings.redThresholdTenths)
        }
        if includesSampling {
            Section("Sampling") {
                Stepper(
                    "K sample duration: \(settings.sampleDurationMilliseconds) ms",
                    value: $settings.sampleDurationMilliseconds,
                    in: 1...60_000,
                    step: 10
                )
                Stepper(
                    "N sample period: \(settings.samplePeriodMilliseconds) ms",
                    value: $settings.samplePeriodMilliseconds,
                    in: 1...60_000,
                    step: 10
                )
                Stepper(
                    "Decision window: \(settings.decisionWindowMilliseconds) ms",
                    value: $settings.decisionWindowMilliseconds,
                    in: 1...600_000,
                    step: 100
                )
                Stepper(
                    "X trigger percent: \(settings.triggerPercent)%",
                    value: $settings.triggerPercent,
                    in: 1...99
                )
            }
        }
    }

    @ViewBuilder
    private func threshold(_ label: String, value: Binding<Int16>) -> some View {
        Stepper(
            "\(label): \(Double(value.wrappedValue) / 10, specifier: "%.1f") dBFS",
            value: value,
            in: -1_200...0,
            step: 5
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
            thresholdOverride("Green threshold", value: $overrides.greenThresholdTenths, inherited: global.greenThresholdTenths)
            thresholdOverride("Orange threshold", value: $overrides.orangeThresholdTenths, inherited: global.orangeThresholdTenths)
            thresholdOverride("Red threshold", value: $overrides.redThresholdTenths, inherited: global.redThresholdTenths)
            toggle("Mute duration", isOn: Binding(
                get: { overrides.muteDurationSeconds != nil },
                set: { overrides.muteDurationSeconds = $0 ? global.muteDurationSeconds : nil }
            ))
            if overrides.muteDurationSeconds != nil {
                Stepper(
                    "Mute: \(overrides.muteDurationSeconds ?? 0) s",
                    value: Binding(
                        get: { overrides.muteDurationSeconds ?? global.muteDurationSeconds },
                        set: { overrides.muteDurationSeconds = $0 }
                    ),
                    in: 60...86_400,
                    step: 30
                )
            } else {
                Text("Inherited value: \(global.muteDurationSeconds) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
            Stepper(
                "\(label): \(value.wrappedValue ?? inherited)%",
                value: Binding(
                    get: { value.wrappedValue ?? inherited },
                    set: { value.wrappedValue = $0 }
                ),
                in: range
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
        inherited: Int16
    ) -> some View {
        toggle("Override \(label)", isOn: Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? inherited : nil }
        ))
        if value.wrappedValue != nil {
            Stepper(
                "\(label): \(Double(value.wrappedValue ?? inherited) / 10, specifier: "%.1f") dBFS",
                value: Binding(
                    get: { value.wrappedValue ?? inherited },
                    set: { value.wrappedValue = $0 }
                ),
                in: -1_200...0,
                step: 5
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
}
