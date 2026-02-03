import SwiftUI

@main
struct MercuryApp: App {
    @StateObject private var monitor = TemperatureMonitor()
    @ObservedObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra {
            // MARK: - Current Readings
            Section("Temperatures") {
                Text("CPU: \(formatTemp(monitor.cpuTemperature))")
                if monitor.hasGPUSensors {
                    Text("GPU: \(formatTemp(monitor.gpuTemperature))")
                }
                if monitor.hasBatterySensors {
                    Text("Battery: \(formatTemp(monitor.batteryTemperature))")
                }
            }

            Divider()

            // MARK: - Menu Bar Display Options
            Section("Menu Bar") {
                Picker("Show", selection: $settings.selectedSensor) {
                    Text("CPU").tag(SensorType.cpu)
                    if monitor.hasGPUSensors {
                        Text("GPU").tag(SensorType.gpu)
                    }
                    if monitor.hasBatterySensors {
                        Text("Battery").tag(SensorType.battery)
                    }
                }

                Toggle("Show Icon", isOn: $settings.showMenuBarIcon)
            }

            Divider()

            // MARK: - Preferences
            Section("Preferences") {
                Picker("Unit", selection: $settings.temperatureUnit) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }

                Picker("Refresh", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }

            Divider()

            Button("Quit Mercury") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")

        } label: {
            if settings.showMenuBarIcon {
                HStack(spacing: 4) {
                    Image(systemName: monitor.menuBarIconName)
                    Text(monitor.menuBarDisplayText)
                        .monospacedDigit()
                }
            } else {
                Text(monitor.menuBarDisplayText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private func formatTemp(_ celsius: Double?) -> String {
        guard let temp = celsius else { return "N/A" }
        let value = settings.temperatureUnit == .fahrenheit ? temp * 9/5 + 32 : temp
        return String(format: "%.1f°%@", value, settings.temperatureUnit.symbol)
    }
}
