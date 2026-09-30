import Foundation
import UIKit

struct LureliaReportDiagnostics {
    let appName: String
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let deviceModel: String
    let iOSVersion: String
    let locale: String
    let timeZone: String
    let submittedAt: Date
    let screenName: String

    static func current(screenName: String) -> LureliaReportDiagnostics {
        LureliaReportDiagnostics(
            appName: "Lurelia",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceModel: deviceModel,
            iOSVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            submittedAt: Date(),
            screenName: screenName
        )
    }

    private static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }

        switch identifier {
        case "iPhone17,4": return "iPhone 16 Plus"
        default: return identifier
        }
    }
}
