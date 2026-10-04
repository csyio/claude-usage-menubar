import Foundation
import ServiceManagement

enum Period: String, CaseIterable, Identifiable {
    case today = "Bugün"
    case fiveHours = "5 saat"
    case week = "7 gün"
    var id: String { rawValue }

    func start(now: Date) -> Date {
        switch self {
        case .today: return Calendar.current.startOfDay(for: now)
        case .fiveHours: return now.addingTimeInterval(-5 * 3600)
        case .week: return now.addingTimeInterval(-7 * 24 * 3600)
        }
    }
}

struct Breakdown: Identifiable {
    let name: String
    let tokens: Int
    let cost: Double
    var id: String { name }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var limits: PlanLimits?
    @Published private(set) var limitsError: LimitsError?
    @Published private(set) var entries: [UsageEntry] = []
    @Published private(set) var now = Date()
    @Published var period: Period = .today
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let scanner = LogScanner()
    private var nextLimitsFetch = Date.distantPast

    init() {
        Task { await refresh(force: true) }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: false) }
        }
    }

    /// Kayıtlar her 30 sn'de taranır; limit uç noktası en fazla 2 dk'da bir sorgulanır.
    func refresh(force: Bool) async {
        now = Date()
        entries = await scanner.scan()
        guard force || now >= nextLimitsFetch else { return }
        do {
            limits = try await LimitsClient.fetch()
            limitsError = nil
            nextLimitsFetch = now.addingTimeInterval(120)
        } catch let e as LimitsError {
            limitsError = e
            nextLimitsFetch = now.addingTimeInterval(e == .http(429) ? 600 : 120)
        } catch {
            limitsError = .http(0)
            nextLimitsFetch = now.addingTimeInterval(120)
        }
    }

    // MARK: - Üst bar

    var menuBarText: String {
        guard let w = limits?.fiveHour else { return "—" }
        let pct = "\(Int(w.percent.rounded()))%"
        guard let reset = w.resetsAt, reset > now, w.percent > 0 else { return pct }
        return "\(pct) · \(Self.shortDuration(reset.timeIntervalSince(now)))"
    }

    var menuBarSymbol: String {
        guard let p = limits?.fiveHour?.percent else { return "gauge.with.dots.needle.0percent" }
        switch p {
        case ..<34: return "gauge.with.dots.needle.33percent"
        case ..<67: return "gauge.with.dots.needle.50percent"
        case ..<90: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    var limitsStale: Bool {
        guard let l = limits else { return true }
        return limitsError != nil || now.timeIntervalSince(l.fetchedAt) > 600
    }

    // MARK: - Dağılımlar

    private var periodEntries: [UsageEntry] {
        let start = period.start(now: now)
        return entries.filter { $0.timestamp >= start }
    }

    var totalCost: Double { periodEntries.reduce(0) { $0 + $1.cost } }
    var totalTokens: Int { periodEntries.reduce(0) { $0 + $1.totalTokens } }

    var byModel: [Breakdown] { group { Pricing.displayName($0.model) } }
    var byProject: [Breakdown] { group(\.project) }

    private func group(_ key: (UsageEntry) -> String) -> [Breakdown] {
        Dictionary(grouping: periodEntries, by: key)
            .map { Breakdown(name: $0.key,
                             tokens: $0.value.reduce(0) { $0 + $1.totalTokens },
                             cost: $0.value.reduce(0) { $0 + $1.cost }) }
            .sorted { $0.cost > $1.cost }
    }

    // MARK: - Ayarlar

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Girişte başlatma ayarlanamadı: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Biçimlendirme

    nonisolated static func shortDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        let (d, h, m) = (mins / 1440, (mins % 1440) / 60, mins % 60)
        if d > 0 { return "\(d)g \(h)sa" }
        if h > 0 { return "\(h)sa \(m)dk" }
        return "\(m)dk"
    }

    nonisolated static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1e3)
        default: return "\(n)"
        }
    }

    nonisolated static func dollars(_ v: Double) -> String { String(format: "$%.2f", v) }
}
