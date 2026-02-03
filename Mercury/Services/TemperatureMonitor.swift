import Foundation
import Combine

class TemperatureMonitor: ObservableObject {
    @Published var cpuTemperature: Double?
    @Published var gpuTemperature: Double?
    @Published var batteryTemperature: Double?

    private let smcService = SMCService.shared
    private let keySet: SMCKeySet
    private var timer: AnyCancellable?
    private var settingsObserver: AnyCancellable?

    let chipType: ChipType
    let settings = Settings.shared

    private var hasLoggedOnce = false

    // Expose sensor availability for UI
    var hasGPUSensors: Bool { !keySet.gpuKeys.isEmpty }
    var hasBatterySensors: Bool { !keySet.batteryKeys.isEmpty }

    private var discoveredKeys: [String] = []

    init() {
        chipType = ChipType.detect()

        // First, discover what temperature keys actually exist on this Mac
        discoveredKeys = smcService.discoverTemperatureKeys()

        // Use discovered keys if available, otherwise fall back to predefined
        if discoveredKeys.isEmpty {
            keySet = SMCKeySet.forChip(chipType)
        } else {
            keySet = SMCKeySet.fromDiscoveredKeys(discoveredKeys)
        }

        updateTemperatures()
        startPolling()

        settingsObserver = settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.startPolling()
            }
    }

    private func startPolling() {
        timer?.cancel()
        timer = Timer.publish(every: settings.refreshInterval.rawValue, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTemperatures()
            }
    }

    private func updateTemperatures() {
        cpuTemperature = readAverageTemperature(keys: keySet.cpuKeys)
        gpuTemperature = readAverageTemperature(keys: keySet.gpuKeys)
        batteryTemperature = readAverageTemperature(keys: keySet.batteryKeys)

        if !hasLoggedOnce {
            hasLoggedOnce = true
            smcService.markLoggingComplete()
            print("[Mercury] CPU: \(cpuTemperature.map { String(format: "%.1f°C", $0) } ?? "N/A"), GPU: \(gpuTemperature.map { String(format: "%.1f°C", $0) } ?? "N/A"), Battery: \(batteryTemperature.map { String(format: "%.1f°C", $0) } ?? "N/A")")
        }
    }

    private func readAverageTemperature(keys: [String]) -> Double? {
        var validReadings: [Double] = []

        for key in keys {
            if let temp = smcService.readTemperature(key: key) {
                validReadings.append(temp)
            }
        }

        guard !validReadings.isEmpty else { return nil }
        return validReadings.reduce(0, +) / Double(validReadings.count)
    }

    var menuBarDisplayText: String {
        guard let temp = selectedTemperature else { return "--°" }
        return formatTemperature(temp, unit: settings.temperatureUnit)
    }

    var menuBarIconName: String {
        guard let celsius = selectedTemperature else { return "thermometer.medium" }

        switch celsius {
        case ..<45:
            return "thermometer.low"
        case 45..<70:
            return "thermometer.medium"
        default:
            return "thermometer.high"
        }
    }

    private var selectedTemperature: Double? {
        switch settings.selectedSensor {
        case .cpu:
            return cpuTemperature
        case .gpu:
            return gpuTemperature
        case .battery:
            return batteryTemperature
        }
    }

    private func formatTemperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        let value = unit == .fahrenheit ? celsius * 9/5 + 32 : celsius
        return String(format: "%.0f°%@", value, unit.symbol)
    }

}
