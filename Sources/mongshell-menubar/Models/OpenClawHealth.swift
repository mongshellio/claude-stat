import SwiftUI

/// Health verdict for the local openclaw gateway.
///
/// A gateway can answer HTTP 200 while its channel workers (Telegram, …) are
/// dead, so `.degraded` exists as a distinct state between fully OK and fully
/// DOWN — the whole point of this feature. `.notInstalled` means the app must
/// behave exactly as before (no icon, no settings), so it is treated as
/// "invisible" everywhere.
enum OpenClawHealth: Equatable, Sendable {
    /// openclaw binary not found — hide everything, act like the plain app.
    case notInstalled
    /// Before the first probe returns.
    case unknown
    /// Gateway itself unreachable (🔴).
    case down
    /// Gateway OK but one or more channels are stopped/errored (🟡).
    case degraded(detail: String)
    /// Gateway + channels healthy (🟢).
    case ok(detail: String)
}

extension OpenClawHealth {
    /// Whether a menu-bar item should exist at all for this state.
    var isVisible: Bool { self != .notInstalled }

    /// Menu-bar dot color. `.notInstalled` never renders, so its color is moot.
    var dotColor: Color {
        switch self {
        case .ok:            return Palette.green
        case .degraded:      return Palette.amber
        case .down:          return Palette.red
        case .unknown:       return Palette.textTertiary
        case .notInstalled:  return .clear
        }
    }

    /// SF Symbol for the dot. Solid circle for known states; a hollow one while
    /// we haven't probed yet.
    var symbolName: String {
        self == .unknown ? "circle.dotted" : "circle.fill"
    }

    /// Short status word for the popover header / settings preview.
    var shortLabel: String {
        switch self {
        case .ok:           return "정상"
        case .degraded:     return "채널 이상"
        case .down:         return "게이트웨이 다운"
        case .unknown:      return "확인 중…"
        case .notInstalled: return "미설치"
        }
    }

    /// The parsed channel summary, when there is one to show.
    var detailText: String? {
        switch self {
        case .ok(let d), .degraded(let d):
            return d.isEmpty ? nil : d
        default:
            return nil
        }
    }

    /// One-line label for the Settings preview row (status + detail).
    var settingsLabel: String {
        if let detail = detailText { return "\(shortLabel) — \(detail)" }
        return shortLabel
    }
}
