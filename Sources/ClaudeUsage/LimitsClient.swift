import Foundation

struct LimitWindow {
    let percent: Double
    let resetsAt: Date?
}

struct PlanLimits {
    let fiveHour: LimitWindow?
    let sevenDay: LimitWindow?
    let plan: String?
    let fetchedAt: Date
}

enum LimitsError: Error, Equatable {
    case noCredentials
    case tokenExpired
    case http(Int)
    case badResponse

    var message: String {
        switch self {
        case .noCredentials: return "Claude Code girişi bulunamadı — terminalde `claude` ile giriş yap."
        case .tokenExpired: return "Oturum süresi doldu — Claude Code'u bir kez açınca yenilenir."
        case .http(429): return "Çok sık sorgulandı, biraz sonra tekrar denenecek."
        case .http(let code): return "Sunucu hatası (\(code))."
        case .badResponse: return "Beklenmeyen yanıt — uç nokta değişmiş olabilir."
        }
    }
}

/// Claude Code'un `/usage` için kullandığı uç noktadan plan limitlerini okur.
/// Token'ı Claude Code'un Keychain kaydından alır; kendisi asla yenilemez
/// (yenilemek refresh token'ı döndürüp Claude Code'un oturumunu bozardı).
enum LimitsClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws -> PlanLimits {
        let creds = try readCredentials()
        if let exp = creds.expiresAt, exp < Date() { throw LimitsError.tokenExpired }

        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-usage-menubar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw LimitsError.tokenExpired }
        guard status == 200 else { throw LimitsError.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LimitsError.badResponse
        }

        func window(_ key: String) -> LimitWindow? {
            guard let w = json[key] as? [String: Any],
                  let pct = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return LimitWindow(percent: pct, resetsAt: (w["resets_at"] as? String).flatMap(DateParsing.parse))
        }
        let five = window("five_hour"), week = window("seven_day")
        if five == nil && week == nil { throw LimitsError.badResponse }
        return PlanLimits(fiveHour: five, sevenDay: week, plan: creds.plan, fetchedAt: Date())
    }

    private struct Credentials {
        let token: String
        let expiresAt: Date?
        let plan: String?
    }

    /// `security` aracıyla okunur: Claude Code kaydı bu araçla oluşturduğu için
    /// ek Keychain izni sorulmaz ve her yeniden derlemede izin tekrar istenmez.
    private static func readCredentials() throws -> Credentials {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw LimitsError.noCredentials }

        let exp = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(token: token, expiresAt: exp, plan: oauth["subscriptionType"] as? String)
    }
}
