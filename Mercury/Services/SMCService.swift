import Foundation
import IOKit

class SMCService {
    static let shared = SMCService()

    private var connection: io_connect_t = 0
    private var isConnected = false
    private var hasLoggedKeyErrors = false

    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCReadKey: UInt8 = 5
    private let kSMCGetKeyInfo: UInt8 = 9
    private let kSMCGetKeyCount: UInt8 = 7
    private let kSMCGetKeyFromIndex: UInt8 = 8

    // SMC struct layout (80 bytes total) based on C alignment rules:
    // Offset  Size  Field
    // 0-3     4     key (UInt32)
    // 4-9     6     vers (version struct)
    // 10-11   2     padding (for pLimitData alignment)
    // 12-27   16    pLimitData
    // 28-31   4     keyInfo.dataSize (UInt32)
    // 32-35   4     keyInfo.dataType (UInt32)
    // 36      1     keyInfo.dataAttributes (UInt8)
    // 37-39   3     padding
    // 40      1     result (UInt8)
    // 41      1     status (UInt8)
    // 42      1     data8 (UInt8) - command selector
    // 43      1     padding
    // 44-47   4     data32 (UInt32)
    // 48-79   32    bytes (data buffer)

    private typealias SMCBytes80 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    // Struct offsets (verified for Apple Silicon)
    // key: 0-3, vers: 4-11, pLimitData: 12-27, keyInfo: 28-39, result: 40, status: 41
    // data8: 42, padding: 43, data32: 44-47, bytes: 48-79

    private init() {
        print("[Mercury] SMC struct size: \(MemoryLayout<SMCBytes80>.size)")
        connect()
    }

    deinit {
        disconnect()
    }

    private func connect() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            print("[Mercury] SMC service not found")
            return
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        if result == kIOReturnSuccess {
            isConnected = true
            print("[Mercury] SMC connected successfully")
        } else {
            print("[Mercury] Failed to open SMC: \(String(format: "0x%X", result))")
        }
    }

    private func disconnect() {
        if isConnected {
            IOServiceClose(connection)
            isConnected = false
        }
    }

    private func createStruct() -> SMCBytes80 {
        return (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    func readTemperature(key: String) -> Double? {
        guard isConnected else { return nil }
        guard key.count == 4 else { return nil }

        let keyCode = fourCharCode(from: key)

        // Step 1: Get key info
        var inputStruct = createStruct()
        var outputStruct = createStruct()

        withUnsafeMutableBytes(of: &inputStruct) { ptr in
            // Key at offset 0 (big-endian FourCC)
            ptr[0] = UInt8((keyCode >> 24) & 0xFF)
            ptr[1] = UInt8((keyCode >> 16) & 0xFF)
            ptr[2] = UInt8((keyCode >> 8) & 0xFF)
            ptr[3] = UInt8(keyCode & 0xFF)
            // Command at offset 42
            ptr[42] = kSMCGetKeyInfo
        }

        let inputSize = 80
        var outputSize = 80

        var result = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSize
        )

        if result != kIOReturnSuccess {
            if !hasLoggedKeyErrors {
                print("[Mercury] '\(key)' info failed: \(String(format: "0x%X", result))")
            }
            return nil
        }

        // Check result byte at offset 40
        var resultCode: UInt8 = 0
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0

        withUnsafeBytes(of: &outputStruct) { ptr in
            resultCode = ptr[40]
            // dataSize at offset 28 (little-endian)
            dataSize = UInt32(ptr[28]) |
                       (UInt32(ptr[29]) << 8) |
                       (UInt32(ptr[30]) << 16) |
                       (UInt32(ptr[31]) << 24)
            // dataType at offset 32 (little-endian storage, gives FourCC value)
            dataType = UInt32(ptr[32]) |
                       (UInt32(ptr[33]) << 8) |
                       (UInt32(ptr[34]) << 16) |
                       (UInt32(ptr[35]) << 24)
        }


        // Result 0 = success, anything else is error
        if resultCode != 0 || dataSize == 0 {
            return nil
        }

        // Step 2: Read key value
        inputStruct = createStruct()
        withUnsafeMutableBytes(of: &inputStruct) { ptr in
            // Key at offset 0 (big-endian FourCC)
            ptr[0] = UInt8((keyCode >> 24) & 0xFF)
            ptr[1] = UInt8((keyCode >> 16) & 0xFF)
            ptr[2] = UInt8((keyCode >> 8) & 0xFF)
            ptr[3] = UInt8(keyCode & 0xFF)
            // dataSize at offset 28 (little-endian)
            ptr[28] = UInt8(dataSize & 0xFF)
            ptr[29] = UInt8((dataSize >> 8) & 0xFF)
            ptr[30] = UInt8((dataSize >> 16) & 0xFF)
            ptr[31] = UInt8((dataSize >> 24) & 0xFF)
            // dataType at offset 32 (little-endian storage)
            ptr[32] = UInt8(dataType & 0xFF)
            ptr[33] = UInt8((dataType >> 8) & 0xFF)
            ptr[34] = UInt8((dataType >> 16) & 0xFF)
            ptr[35] = UInt8((dataType >> 24) & 0xFF)
            // Command at offset 42
            ptr[42] = kSMCReadKey
        }

        result = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSize
        )

        if result != kIOReturnSuccess {
            if !hasLoggedKeyErrors {
                print("[Mercury] '\(key)' read failed: \(String(format: "0x%X", result))")
            }
            return nil
        }

        // Extract temperature data from bytes at offset 48
        var dataBytes: [UInt8] = [0, 0, 0, 0]
        withUnsafeBytes(of: &outputStruct) { ptr in
            dataBytes[0] = ptr[48]
            dataBytes[1] = ptr[49]
            dataBytes[2] = ptr[50]
            dataBytes[3] = ptr[51]
        }

        let temp = parseTemperature(dataType: dataType, bytes: dataBytes)

        if !hasLoggedKeyErrors && temp != nil {
            let typeStr = String(format: "%c%c%c%c",
                                 (dataType >> 24) & 0xFF,
                                 (dataType >> 16) & 0xFF,
                                 (dataType >> 8) & 0xFF,
                                 dataType & 0xFF)
            print("[Mercury] '\(key)' type='\(typeStr)' size=\(dataSize) = \(String(format: "%.1f", temp!))°C")
        }

        return temp
    }

    func markLoggingComplete() {
        hasLoggedKeyErrors = true
    }

    // Enumerate all SMC keys to find temperature sensors
    func discoverTemperatureKeys() -> [String] {
        guard isConnected else { return [] }

        // Get total key count
        var inputStruct = createStruct()
        var outputStruct = createStruct()

        withUnsafeMutableBytes(of: &inputStruct) { ptr in
            ptr[42] = kSMCGetKeyCount
        }

        let inputSize = 80
        var outputSize = 80

        var result = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            print("[Mercury] Failed to get key count")
            return []
        }

        // Key count is in data32 at offset 44 - try big-endian (FourCC style)
        var keyCount: UInt32 = 0
        withUnsafeBytes(of: &outputStruct) { ptr in
            // Try big-endian
            keyCount = (UInt32(ptr[44]) << 24) |
                       (UInt32(ptr[45]) << 16) |
                       (UInt32(ptr[46]) << 8) |
                       UInt32(ptr[47])
        }

        // Sanity check - if count seems wrong, try little-endian
        if keyCount > 10000 {
            withUnsafeBytes(of: &outputStruct) { ptr in
                keyCount = UInt32(ptr[44]) |
                           (UInt32(ptr[45]) << 8) |
                           (UInt32(ptr[46]) << 16) |
                           (UInt32(ptr[47]) << 24)
            }
        }

        // Still wrong? Limit it
        if keyCount > 10000 {
            print("[Mercury] Key count seems invalid (\(keyCount)), using 500")
            keyCount = 500
        } else {
            print("[Mercury] Total SMC keys: \(keyCount)")
        }

        var temperatureKeys: [String] = []

        // Iterate through all keys to find temperature ones (start with 'T')
        for i: UInt32 in 0..<min(keyCount, 500) {  // Limit to avoid long startup
            inputStruct = createStruct()

            withUnsafeMutableBytes(of: &inputStruct) { ptr in
                ptr[42] = kSMCGetKeyFromIndex
                // Index in data32 at offset 44 (little-endian)
                ptr[44] = UInt8(i & 0xFF)
                ptr[45] = UInt8((i >> 8) & 0xFF)
                ptr[46] = UInt8((i >> 16) & 0xFF)
                ptr[47] = UInt8((i >> 24) & 0xFF)
            }

            result = IOConnectCallStructMethod(
                connection,
                kSMCHandleYPCEvent,
                &inputStruct,
                inputSize,
                &outputStruct,
                &outputSize
            )

            guard result == kIOReturnSuccess else { continue }

            // Key is at offset 0 (big-endian FourCC)
            var keyCode: UInt32 = 0
            withUnsafeBytes(of: &outputStruct) { ptr in
                keyCode = (UInt32(ptr[0]) << 24) |
                          (UInt32(ptr[1]) << 16) |
                          (UInt32(ptr[2]) << 8) |
                          UInt32(ptr[3])
            }

            let keyStr = String(format: "%c%c%c%c",
                                (keyCode >> 24) & 0xFF,
                                (keyCode >> 16) & 0xFF,
                                (keyCode >> 8) & 0xFF,
                                keyCode & 0xFF)

            // Collect keys starting with 'T' (temperature)
            if keyStr.hasPrefix("T") {
                temperatureKeys.append(keyStr)
            }
        }

        print("[Mercury] Found \(temperatureKeys.count) temperature keys")

        return temperatureKeys
    }

    private func parseTemperature(dataType: UInt32, bytes: [UInt8]) -> Double? {
        // flt - Float (Apple Silicon)
        if dataType == fourCharCode(from: "flt ") {
            var floatValue: Float = 0
            withUnsafeMutableBytes(of: &floatValue) { ptr in
                ptr[0] = bytes[0]
                ptr[1] = bytes[1]
                ptr[2] = bytes[2]
                ptr[3] = bytes[3]
            }
            let temp = Double(floatValue)
            return (temp > 0 && temp < 150) ? temp : nil
        }

        // sp78 - Fixed-point 7.8 (Intel, big-endian)
        if dataType == fourCharCode(from: "sp78") {
            let intValue = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            let temp = Double(intValue) / 256.0
            return (temp > 0 && temp < 150) ? temp : nil
        }

        // ui8 - Unsigned 8-bit (direct temperature in °C)
        if dataType == fourCharCode(from: "ui8 ") {
            let temp = Double(bytes[0])
            // Filter: valid range 10-105°C, exclude 0 and 255 (N/A markers)
            if temp >= 10 && temp <= 105 {
                return temp
            }
            return nil
        }

        // ui16 - Unsigned 16-bit (little-endian, /10 scaling for temperature)
        if dataType == fourCharCode(from: "ui16") {
            let rawValue = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            if rawValue == 0 || rawValue == 0xFFFF {
                return nil
            }
            let temp = Double(rawValue) / 10.0
            // Filter: valid range 10-100°C
            if temp >= 10 && temp <= 100 {
                return temp
            }
            return nil
        }

        // ui32 - Unsigned 32-bit (little-endian)
        if dataType == fourCharCode(from: "ui32") {
            let rawValue = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) |
                          (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            if rawValue == 0 {
                return nil
            }
            let temp = Double(rawValue) / 10.0
            return (temp > 0 && temp < 150) ? temp : nil
        }

        return nil
    }

    private func fourCharCode(from string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}
