import Foundation

enum ChipType {
    case intel
    case m1
    case m2
    case m3
    case m4
    case m5
    case unknown

    static func detect() -> ChipType {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brandString = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brandString, &size, nil, 0)
        let cpuBrand = String(cString: brandString)

        print("[Mercury] Detected CPU: \(cpuBrand)")

        let lowerBrand = cpuBrand.lowercased()

        if lowerBrand.contains("m5") {
            print("[Mercury] Chip type: M5")
            return .m5
        } else if lowerBrand.contains("m4") {
            print("[Mercury] Chip type: M4")
            return .m4
        } else if lowerBrand.contains("m3") {
            print("[Mercury] Chip type: M3")
            return .m3
        } else if lowerBrand.contains("m2") {
            print("[Mercury] Chip type: M2")
            return .m2
        } else if lowerBrand.contains("m1") {
            print("[Mercury] Chip type: M1")
            return .m1
        } else if lowerBrand.contains("intel") {
            print("[Mercury] Chip type: Intel")
            return .intel
        }

        // Fallback: check for Apple Silicon via hw.optional.arm64
        var arm64: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0, arm64 == 1 {
            print("[Mercury] Chip type: Unknown Apple Silicon (using M1 keys)")
            return .m1
        }

        print("[Mercury] Chip type: Unknown")
        return .unknown
    }
}

struct SMCKeySet {
    let cpuKeys: [String]
    let gpuKeys: [String]
    let batteryKeys: [String]

    // Create key set from discovered keys by categorizing them
    static func fromDiscoveredKeys(_ keys: [String]) -> SMCKeySet {
        var cpuKeys: [String] = []
        var gpuKeys: [String] = []
        var batteryKeys: [String] = []

        for key in keys {
            let k = key.uppercased()

            // Battery/Ambient temperature keys (TA = Thermal Ambient, TB = Thermal Battery)
            if k.hasPrefix("TB") || k.hasPrefix("TA") {
                batteryKeys.append(key)
            }
            // GPU temperature keys
            else if k.hasPrefix("TG") {
                gpuKeys.append(key)
            }
            // CPU/SoC temperature keys
            else if k.hasPrefix("TC") || k.hasPrefix("TP") || k.hasPrefix("TE") ||
                    k.hasPrefix("TM") || k.hasPrefix("TF") || k.hasPrefix("TS") ||
                    k.hasPrefix("TH") || k.hasPrefix("TD") || k.hasPrefix("TR") ||
                    k.hasPrefix("TK") || k.hasPrefix("TL") || k.hasPrefix("T0") ||
                    k.hasPrefix("T-") {
                cpuKeys.append(key)
            }
        }

        return SMCKeySet(cpuKeys: cpuKeys, gpuKeys: gpuKeys, batteryKeys: batteryKeys)
    }

    static func forChip(_ chip: ChipType) -> SMCKeySet {
        switch chip {
        case .intel:
            return SMCKeySet(
                cpuKeys: ["TC0P", "TC0D", "TC1C", "TC2C", "TC3C", "TC4C"],
                gpuKeys: ["TG0D", "TG0P"],
                batteryKeys: ["TB0T", "TB1T", "TB2T"]
            )
        case .m1:
            // M1, M1 Pro, M1 Max, M1 Ultra keys
            return SMCKeySet(
                cpuKeys: [
                    // M1 base
                    "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
                    // M1 Pro/Max additional
                    "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j", "Tp0n", "Tp0r",
                    // Fallback keys
                    "TC0C", "TC0c", "TC0P", "TC0p", "Tc0c", "Tc0C"
                ],
                gpuKeys: [
                    "Tg05", "Tg0D", "Tg0L", "Tg0T",
                    // M1 Pro/Max additional
                    "Tg0f", "Tg0j", "Tg1f", "Tg1j"
                ],
                batteryKeys: ["TB0T", "TB1T", "TB2T", "TBXT"]
            )
        case .m2:
            return SMCKeySet(
                cpuKeys: ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
                gpuKeys: ["Tg0f", "Tg0j"],
                batteryKeys: ["TB0T", "TB1T", "TB2T"]
            )
        case .m3, .m4, .m5:
            // M3/M4/M5 use similar SMC key patterns
            // M5 keys are assumed to follow M4 patterns until specific keys are documented
            return SMCKeySet(
                cpuKeys: ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0D", "Tf0E", "Tf0F", "Tf0O", "Tf0P", "Tf0T"],
                gpuKeys: ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"],
                batteryKeys: ["TB0T", "TB1T", "TB2T"]
            )
        case .unknown:
            // Use M1 keys as fallback for Apple Silicon
            return SMCKeySet.forChip(.m1)
        }
    }
}
