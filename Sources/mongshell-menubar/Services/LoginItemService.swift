import Foundation
import ServiceManagement

/// Launch-at-login registration via `SMAppService.mainApp` — the system's
/// Login Items list (시스템 설정 > 일반 > 로그인 항목) is the single source of
/// truth, so this type owns no state: it only queries and mutates that list.
/// Nothing else in the app touches ServiceManagement.
enum LoginItemService {
    /// Whether the app will actually launch at login.
    ///
    /// `.requiresApproval` deliberately reads as **off**: it means the item is
    /// registered but the user switched it off in System Settings, so the app
    /// will NOT launch at login. Reporting it as "on" would make the settings
    /// toggle claim something the system won't do.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has disabled the registered item in System Settings.
    /// Split from `isEnabled` so the caller can tell "off because unregistered"
    /// from "off until the user re-allows it" and explain the latter.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    enum LoginItemError: LocalizedError {
        case registerFailed(String)
        case unregisterFailed(String)

        var errorDescription: String? {
            switch self {
            case .registerFailed(let detail):
                return "로그인 항목 등록에 실패했습니다: \(detail)"
            case .unregisterFailed(let detail):
                return "로그인 항목 해제에 실패했습니다: \(detail)"
            }
        }
    }

    /// Registers or unregisters the app as a login item. Command only — read
    /// the resulting state back via `isEnabled` (CQS).
    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw enabled
                ? LoginItemError.registerFailed(error.localizedDescription)
                : LoginItemError.unregisterFailed(error.localizedDescription)
        }
    }
}
