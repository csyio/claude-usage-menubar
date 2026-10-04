import SwiftUI

struct PanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            limitsSection
            Divider()
            Picker("", selection: $store.period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .firstTextBaseline) {
                Text(UsageStore.dollars(store.totalCost)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("API karşılığı · \(UsageStore.tokens(store.totalTokens)) token")
                    .font(.caption).foregroundStyle(.secondary)
            }

            breakdown(title: "Modele göre", rows: store.byModel, limit: 6)
            breakdown(title: "Projeye göre", rows: store.byProject, limit: 8)

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Claude Kullanım").font(.headline)
            if let plan = store.limits?.plan {
                Text(plan.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Button {
                Task { await store.refresh(force: true) }
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.borderless)
            .help("Yenile")
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let l = store.limits {
                if let w = l.fiveHour { LimitBar(title: "5 saatlik pencere", window: w, now: store.now) }
                if let w = l.sevenDay { LimitBar(title: "Haftalık", window: w, now: store.now) }
            }
            if let err = store.limitsError {
                Label(err.message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.limits == nil {
                Text("Limitler yükleniyor…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func breakdown(title: String, rows: [Breakdown], limit: Int) -> some View {
        let total = max(rows.reduce(0) { $0 + $1.cost }, 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("Bu dönemde kullanım yok").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(rows.prefix(limit)) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(UsageStore.tokens(row.tokens)).foregroundStyle(.secondary)
                        Text(UsageStore.dollars(row.cost)).frame(width: 64, alignment: .trailing)
                    }
                    .font(.callout).monospacedDigit()
                    ProgressView(value: row.cost / total).progressViewStyle(.linear).tint(.secondary)
                }
            }
            if rows.count > limit {
                Text("+\(rows.count - limit) diğer").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Girişte başlat", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Spacer()
            Button("Çıkış") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}

private struct LimitBar: View {
    let title: String
    let window: LimitWindow
    let now: Date

    private var color: Color {
        switch window.percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int(window.percent.rounded()))%").font(.callout.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: min(window.percent, 100), total: 100).tint(color)
            if let reset = window.resetsAt, reset > now {
                Text("Sıfırlanma: \(reset.formatted(date: Calendar.current.isDateInToday(reset) ? .omitted : .abbreviated, time: .shortened)) · \(UsageStore.shortDuration(reset.timeIntervalSince(now))) sonra")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
