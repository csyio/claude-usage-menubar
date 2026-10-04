import Foundation

struct UsageEntry {
    let timestamp: Date
    let model: String
    let project: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite5m: Int
    let cacheWrite1h: Int

    var totalTokens: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    var cost: Double {
        let p = Pricing.price(for: model)
        let sum = Double(input) * p.input
            + Double(output) * p.output
            + Double(cacheRead) * p.cacheRead
            + Double(cacheWrite5m) * p.cacheWrite5m
            + Double(cacheWrite1h) * p.cacheWrite1h
        return sum / 1_000_000
    }
}

/// ~/.claude/projects altındaki Claude Code oturum kayıtlarını (JSONL) artımlı okur.
/// Aynı API yanıtı her içerik bloğu için ayrı satıra yazıldığından message.id + requestId ile tekilleştirir.
actor LogScanner {
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private let keepWindow: TimeInterval = 8 * 24 * 3600

    private var offsets: [String: UInt64] = [:]
    private var entries: [String: UsageEntry] = [:]

    func scan() -> [UsageEntry] {
        let cutoff = Date().addingTimeInterval(-keepWindow)
        for file in jsonlFiles(modifiedAfter: cutoff) {
            read(file)
        }
        entries = entries.filter { $0.value.timestamp >= cutoff }
        return Array(entries.values)
    }

    private func jsonlFiles(modifiedAfter cutoff: Date) -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mod, mod >= cutoff { result.append(url) }
        }
        return result
    }

    private func read(_ url: URL) {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var offset = offsets[path] ?? 0
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }  // dosya kısaldıysa baştan oku
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // Son satır yarım yazılmış olabilir: yalnız son '\n'e kadar işle.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        offsets[path] = offset + UInt64(complete.count)

        let project = projectName(for: url)
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            parse(Data(line), project: project)
        }
    }

    private static let usageMarker = Data("\"usage\"".utf8)

    private func parse(_ line: Data, project: String) {
        guard line.range(of: Self.usageMarker) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model.hasPrefix("claude"),
              let ts = (obj["timestamp"] as? String).flatMap(DateParsing.parse)
        else { return }

        let key = "\(message["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
        if key != "|", entries[key] != nil { return }

        func int(_ dict: [String: Any]?, _ k: String) -> Int { (dict?[k] as? NSNumber)?.intValue ?? 0 }
        let cacheCreation = usage["cache_creation"] as? [String: Any]
        var write5m = int(cacheCreation, "ephemeral_5m_input_tokens")
        let write1h = int(cacheCreation, "ephemeral_1h_input_tokens")
        if cacheCreation == nil { write5m = int(usage, "cache_creation_input_tokens") }

        let entry = UsageEntry(
            timestamp: ts, model: model, project: project,
            input: int(usage, "input_tokens"), output: int(usage, "output_tokens"),
            cacheRead: int(usage, "cache_read_input_tokens"),
            cacheWrite5m: write5m, cacheWrite1h: write1h
        )
        entries[key == "|" ? UUID().uuidString : key] = entry
    }

    /// Kayıt klasörü adı yolun kodlanmış hali: "-Users-can-Desktop-asistan" → "asistan".
    private func projectName(for url: URL) -> String {
        let rel = url.path.dropFirst(root.path.count + 1)
        let dir = String(rel.split(separator: "/").first ?? "")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encode = { (s: String) in String(s.map { $0.isLetter || $0.isNumber ? $0 : "-" }) }
        let desktop = encode(home + "/Desktop/")
        let homeEnc = encode(home)
        if dir.hasPrefix(desktop) { return String(dir.dropFirst(desktop.count)) }
        if dir == homeEnc { return "~ (ana dizin)" }
        if dir.hasPrefix(homeEnc + "-") { return "~/" + dir.dropFirst(homeEnc.count + 1) }
        return dir
    }
}

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date? {
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
        // "…:59.532262+00:00" gibi 6 haneli kesirleri at
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            return plain.date(from: s.replacingCharacters(in: r, with: ""))
        }
        return nil
    }
}
