import Foundation

enum SensorType: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case gpu = "GPU"
    case battery = "Battery"

    var id: String { rawValue }
}
