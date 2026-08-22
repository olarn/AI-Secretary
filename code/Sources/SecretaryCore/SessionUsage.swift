import Foundation

public struct SessionUsage: Equatable, Sendable {
    public let turns: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheWriteTokens: Int
    public let cacheReadTokens: Int
    public let costUSD: Double
    public let contextWindow: Int?
    public let lastTurnContextTokens: Int

    public static let empty = SessionUsage(
        turns: 0, inputTokens: 0, outputTokens: 0,
        cacheWriteTokens: 0, cacheReadTokens: 0,
        costUSD: 0, contextWindow: nil, lastTurnContextTokens: 0
    )

    public init(
        turns: Int,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int,
        costUSD: Double,
        contextWindow: Int?,
        lastTurnContextTokens: Int
    ) {
        self.turns = turns
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.contextWindow = contextWindow
        self.lastTurnContextTokens = lastTurnContextTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    public var contextFraction: Double? {
        guard let contextWindow, contextWindow > 0 else { return nil }
        return min(1, Double(lastTurnContextTokens) / Double(contextWindow))
    }

    public func adding(
        inputTokens newInput: Int,
        outputTokens newOutput: Int,
        cacheWriteTokens newWrite: Int,
        cacheReadTokens newRead: Int,
        costUSD newCost: Double,
        contextWindow newWindow: Int?
    ) -> SessionUsage {
        SessionUsage(
            turns: turns + 1,
            inputTokens: inputTokens + newInput,
            outputTokens: outputTokens + newOutput,
            cacheWriteTokens: cacheWriteTokens + newWrite,
            cacheReadTokens: cacheReadTokens + newRead,
            costUSD: costUSD + newCost,
            contextWindow: newWindow ?? contextWindow,
            lastTurnContextTokens: newInput + newWrite + newRead
        )
    }
}

public enum UsageFormat {
    public static func tokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func cost(_ value: Double) -> String {
        String(format: "$%.4f", value)
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public static let costNote =
        "Cost is what this traffic would bill on the API — a subscription is not charged per token."

    public static func duration(until date: Date, from now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3600 { return "\(Int((seconds / 60).rounded(.up))) min" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded())) hr" }
        let days = Int((seconds / 86_400).rounded())
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) hr ago"
    }

    public static func summary(_ usage: SessionUsage) -> String {
        guard usage.turns > 0 else {
            return "No tokens used yet this session — ask me something first."
        }
        var lines = [
            "Session usage over \(usage.turns) turn\(usage.turns == 1 ? "" : "s"):",
            "",
            "| | Tokens |",
            "| --- | ---: |",
            "| Input | \(tokens(usage.inputTokens)) |",
            "| Output | \(tokens(usage.outputTokens)) |",
            "| Cache write | \(tokens(usage.cacheWriteTokens)) |",
            "| Cache read | \(tokens(usage.cacheReadTokens)) |",
            "| **Total** | **\(tokens(usage.totalTokens))** |",
            ""
        ]
        if let fraction = usage.contextFraction, let window = usage.contextWindow {
            lines.append(
                "Context on the last turn: \(tokens(usage.lastTurnContextTokens)) of \(tokens(window)) (\(percent(fraction)))."
            )
        }
        lines.append("Equivalent API cost: \(cost(usage.costUSD)). \(costNote)")
        return lines.joined(separator: "\n")
    }
}

public func totalUsage(_ parts: [SessionUsage]) -> SessionUsage {
    parts.reduce(.empty) { running, part in
        SessionUsage(
            turns: running.turns + part.turns,
            inputTokens: running.inputTokens + part.inputTokens,
            outputTokens: running.outputTokens + part.outputTokens,
            cacheWriteTokens: running.cacheWriteTokens + part.cacheWriteTokens,
            cacheReadTokens: running.cacheReadTokens + part.cacheReadTokens,
            costUSD: running.costUSD + part.costUSD,
            contextWindow: [running.contextWindow, part.contextWindow].compactMap { $0 }.max(),
            lastTurnContextTokens: max(running.lastTurnContextTokens, part.lastTurnContextTokens)
        )
    }
}
