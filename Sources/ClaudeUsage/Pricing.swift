import Foundation

/// API liste fiyatları ($ / 1M token). Pro abonelikte gerçek ödeme bu değil —
/// "API'de olsa ne tutardı" karşılığı. Kaynak: Anthropic fiyat tablosu, 2026-09-25.
struct ModelPrice {
    let input: Double
    let output: Double
    let cacheRead: Double

    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.0 }
}

enum Pricing {
    /// Uzun önek önce gelmeli: "opus-5-5" "opus-5"ten önce eşleşsin.
    private static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5-1", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", ModelPrice(input: 10, output: 50, cacheRead: 1.00)),
        ("claude-mythos", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-opus-5-5", ModelPrice(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", ModelPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", ModelPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5", ModelPrice(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", ModelPrice(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku", ModelPrice(input: 1, output: 5, cacheRead: 0.10)),
    ]
    private static let fallback = ModelPrice(input: 5, output: 25, cacheRead: 0.50)

    static func price(for model: String) -> ModelPrice {
        table.first { model.hasPrefix($0.prefix) }?.price ?? fallback
    }

    /// "claude-opus-5-5" → "Opus 5.5", "claude-haiku-4-5-20251001" → "Haiku 4.5"
    static func displayName(_ model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
