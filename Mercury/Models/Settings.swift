import Foundation
import SwiftUI
import Combine

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: return "C"
        case .fahrenheit: return "F"
        }
    }
}

enum RefreshInterval: Double, CaseIterable, Identifiable {
    case oneSecond = 1.0
    case twoSeconds = 2.0
    case threeSeconds = 3.0
    case fiveSeconds = 5.0
    case tenSeconds = 10.0

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .oneSecond: return "1 second"
        case .twoSeconds: return "2 seconds"
        case .threeSeconds: return "3 seconds"
        case .fiveSeconds: return "5 seconds"
        case .tenSeconds: return "10 seconds"
        }
    }
}

class Settings: ObservableObject {
    static let shared = Settings()

    @Published var temperatureUnit: TemperatureUnit {
        didSet {
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperatureUnit")
        }
    }

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
        }
    }

    @Published var selectedSensor: SensorType {
        didSet {
            UserDefaults.standard.set(selectedSensor.rawValue, forKey: "selectedSensor")
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        }
    }

    private init() {
        let defaults = UserDefaults.standard

        if let unitString = defaults.string(forKey: "temperatureUnit"),
           let unit = TemperatureUnit(rawValue: unitString) {
            self.temperatureUnit = unit
        } else {
            self.temperatureUnit = .celsius
        }

        if let intervalValue = defaults.object(forKey: "refreshInterval") as? Double,
           let interval = RefreshInterval(rawValue: intervalValue) {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = .threeSeconds
        }

        if let sensorString = defaults.string(forKey: "selectedSensor"),
           let sensor = SensorType(rawValue: sensorString) {
            self.selectedSensor = sensor
        } else {
            self.selectedSensor = .cpu
        }

        self.showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
    }
}
