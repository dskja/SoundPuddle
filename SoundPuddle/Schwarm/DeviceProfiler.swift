import Foundation
import UIKit

struct DeviceProfile: Equatable, Sendable {
    var model: String
    var speakerQuality: Float
    var latencyBiasMs: Int
    var supportsTorch: Bool
    var supportsUltrasonic: Bool
}

enum DeviceProfiler {
    static func profile() -> DeviceProfile {
        let model = machineIdentifier()
        let entry = table[model] ?? heuristic(for: model)
        return DeviceProfile(
            model: model,
            speakerQuality: entry.quality,
            latencyBiasMs: entry.latency,
            supportsTorch: UIDevice.current.userInterfaceIdiom == .phone,
            supportsUltrasonic: entry.ultrasonic
        )
    }

    private struct Entry {
        var quality: Float
        var latency: Int
        var ultrasonic: Bool
    }

    /// Hand-tuned bias table; CoreML hook can replace later.
    private static let table: [String: Entry] = [
        "iPhone15,2": .init(quality: 0.92, latency: 12, ultrasonic: true),
        "iPhone15,3": .init(quality: 0.95, latency: 12, ultrasonic: true),
        "iPhone16,1": .init(quality: 0.94, latency: 10, ultrasonic: true),
        "iPhone16,2": .init(quality: 0.96, latency: 10, ultrasonic: true),
        "iPhone17,1": .init(quality: 0.97, latency: 9, ultrasonic: true),
        "iPhone17,2": .init(quality: 0.98, latency: 9, ultrasonic: true),
        "iPhone14,2": .init(quality: 0.88, latency: 14, ultrasonic: true),
        "iPhone14,3": .init(quality: 0.90, latency: 14, ultrasonic: true),
        "iPhone13,2": .init(quality: 0.82, latency: 16, ultrasonic: true),
        "iPhone12,1": .init(quality: 0.75, latency: 18, ultrasonic: false),
    ]

    private static func heuristic(for model: String) -> Entry {
        if model.hasPrefix("iPhone1") {
            return .init(quality: 0.85, latency: 14, ultrasonic: true)
        }
        if model.hasPrefix("iPhone") {
            return .init(quality: 0.7, latency: 20, ultrasonic: false)
        }
        return .init(quality: 0.55, latency: 25, ultrasonic: false)
    }

    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
