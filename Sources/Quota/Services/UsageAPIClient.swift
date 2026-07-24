import Foundation

enum APIError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case badResponse
}

/// Calls the (unofficial) subscription usage endpoint and maps the response
/// into a `UsageSnapshot`. The response schema is undocumented, so decoding is
/// deliberately tolerant: it probes several candidate key paths and fills what
/// it can. Confirm/tighten in Phase 0 once a real payload is captured.
struct UsageAPIClient {

    func fetch(token: OAuthToken) async throws -> UsageSnapshot {
        var req = URLRequest(url: Config.usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Config.anthropicBeta, forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.badResponse
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }

        switch http.statusCode {
        case 200:
            return try Self.parse(data)
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retry)
        default:
            throw APIError.http(http.statusCode)
        }
    }

    // MARK: - Tolerant decoding

    /// Real (undocumented) schema. The authoritative per-limit data is the
    /// `limits` array; each entry has an int `percent`, a `kind`, `resets_at`,
    /// and (for scoped rows) `scope.model.display_name`:
    /// ```
    /// "limits": [
    ///   { "kind":"session",       "percent":64, "resets_at":"…" },
    ///   { "kind":"weekly_all",     "percent":23, "resets_at":"…" },
    ///   { "kind":"weekly_scoped",  "percent":29, "resets_at":"…",
    ///     "scope":{ "model":{ "display_name":"Fable" } } } ]
    /// ```
    /// (`five_hour`/`seven_day` objects mirror session/weekly_all; the old
    /// `seven_day_<model>` keys are always null now.)
    static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }

        var fivePct = 0, weeklyPct = 0
        var fiveReset: Date?, weeklyReset: Date?
        var models: [ModelUsage] = []

        let limits = root["limits"] as? [[String: Any]] ?? []
        for limit in limits {
            let pct = percentInt(limit["percent"])
            let reset = isoDate(limit["resets_at"])
            switch limit["kind"] as? String {
            case "session":
                fivePct = pct; fiveReset = reset
            case "weekly_all":
                weeklyPct = pct; weeklyReset = reset
            case "weekly_scoped":
                let name = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                models.append(ModelUsage(name: prettyModelName(name ?? "모델"), percent: pct))
            default:
                break
            }
        }

        // Fallback to the flat objects if `limits` is absent.
        if limits.isEmpty {
            let five = root["five_hour"] as? [String: Any]
            let weekly = root["seven_day"] as? [String: Any]
            fivePct = percentInt(five?["utilization"]); fiveReset = isoDate(five?["resets_at"])
            weeklyPct = percentInt(weekly?["utilization"]); weeklyReset = isoDate(weekly?["resets_at"])
        }

        return UsageSnapshot(
            fiveHourPercent: fivePct,
            fiveHourResetText: TimeText.resetsIn(fiveReset),
            fiveHourResetAt: fiveReset,
            weeklyAllPercent: weeklyPct,
            weeklyResetText: TimeText.resetsAt(weeklyReset),
            weeklyResetAt: weeklyReset,
            models: models,
            creditsText: creditsText(from: root),
            lastUpdated: Date()
        )
    }

    /// Usage-credits balance — shown ONLY when the user has the pay-as-you-go
    /// credits feature enabled (amounts are minor units, e.g. cents). We
    /// deliberately don't surface the "disabled/out_of_credits" state, since
    /// for users who never opted in it reads as misleading.
    private static func creditsText(from root: [String: Any]) -> String? {
        guard let spend = root["spend"] as? [String: Any],
              (spend["enabled"] as? Bool) == true,
              let limit = spend["limit"] as? [String: Any],
              let used = spend["used"] as? [String: Any] else { return nil }
        let exp = (limit["exponent"] as? Int) ?? 2
        let divisor = pow(10.0, Double(exp))
        let remaining = Double((limit["amount_minor"] as? Int ?? 0)
                               - (used["amount_minor"] as? Int ?? 0)) / divisor
        return String(format: "크레딧 $%.2f 남음", max(0, remaining))
    }

    // MARK: helpers

    /// `utilization` is a 0…100 percentage already — round + clamp, no scaling.
    private static func percentInt(_ any: Any?) -> Int {
        let v: Double
        if let d = any as? Double { v = d }
        else if let i = any as? Int { v = Double(i) }
        else { return 0 }
        return max(0, min(100, Int(v.rounded())))
    }

    private static func isoDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func prettyModelName(_ raw: String) -> String {
        let r = raw.lowercased()
        if r.contains("opus") { return "Opus" }
        if r.contains("fable") { return "Fable 5" }
        if r.contains("sonnet") { return "Sonnet" }
        if r.contains("haiku") { return "Haiku" }
        return raw.capitalized
    }
}
