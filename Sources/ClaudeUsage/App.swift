import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var store = UsageStore()

    init() {
        if CommandLine.arguments.contains("--dump") { Dump.run() }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            Image(systemName: store.menuBarSymbol)
            Text(store.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

/// `ClaudeUsage --dump`: arayüz açmadan hesaplananları terminale yazar (hata ayıklama için).
enum Dump {
    static func run() {
        Task {
            let entries = await LogScanner().scan()
            let today = Calendar.current.startOfDay(for: Date())
            let todays = entries.filter { $0.timestamp >= today }
            print("Bugün: \(todays.count) yanıt, \(UsageStore.dollars(todays.reduce(0) { $0 + $1.cost }))")
            for (model, list) in Dictionary(grouping: todays, by: { Pricing.displayName($0.model) }) {
                print("  \(model): \(UsageStore.tokens(list.reduce(0) { $0 + $1.totalTokens })) token, \(UsageStore.dollars(list.reduce(0) { $0 + $1.cost }))")
            }
            for (project, list) in Dictionary(grouping: todays, by: \.project) {
                print("  [\(project)] \(UsageStore.dollars(list.reduce(0) { $0 + $1.cost }))")
            }
            do {
                let l = try await LimitsClient.fetch()
                print("Plan: \(l.plan ?? "?") · 5 saat: \(l.fiveHour?.percent ?? -1)% (sıfırlanma \(String(describing: l.fiveHour?.resetsAt))) · hafta: \(l.sevenDay?.percent ?? -1)%")
            } catch let e as LimitsError {
                print("Limit hatası: \(e.message)")
            } catch {
                print("Limit hatası: \(error)")
            }
            exit(0)
        }
        RunLoop.main.run()
    }
}
