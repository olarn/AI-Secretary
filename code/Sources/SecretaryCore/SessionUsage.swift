import Foundation

/// What one turn cost, and what the session has cost so far.
///
/// The four token counts are kept apart rather than summed into one number,
/// because they are priced differently and behave differently: a cache read is
/// most of the traffic on a long conversation and a fraction of the price, while
/// a cache write is the expensive one. Reporting only `input + output` — which
/// is what this app did until now — understates a real turn by orders of
/// magnitude: measured at 2 in / 5 out against 11,768 written and 24,436 read.
public struct SessionUsage: Equatable, Sendable {
    public let turns: Int
    public let inputTokens: Int
    public let outputTokens: Int
    /// Tokens written into the prompt cache. Charged at a premium.
    public let cacheWriteTokens: Int
    /// Tokens served from the prompt cache. Charged at a discount.
    public let cacheReadTokens: Int
    /// What the same traffic would cost on the API. Not money charged to a
    /// subscription — see `costNote`.
    public let costUSD: Double
    /// The model's context window, when the backend reported one.
    public let contextWindow: Int?
    /// Tokens the *last* turn put into the context window, which is what decides
    /// how much room is left — unlike the totals, this one does not accumulate.
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

    /// Everything that crossed the wire, in both directions.
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    /// How full the model's context window was on the last turn, 0…1.
    ///
    /// Everything the model had to read counts — fresh input plus whatever came
    /// from the cache — since the cache is a billing arrangement, not a smaller
    /// prompt.
    public var contextFraction: Double? {
        guard let contextWindow, contextWindow > 0 else { return nil }
        return min(1, Double(lastTurnContextTokens) / Double(contextWindow))
    }

    /// A new total including this turn. The window is carried forward from
    /// whichever turn last reported one, so a turn that omits it doesn't erase it.
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

/// Formatting, kept next to the numbers so the chat command and the panel can
/// never disagree about what a figure means.
public enum UsageFormat {
    /// Thousands separators, because six-digit token counts are unreadable
    /// without them.
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

    /// The line that must always accompany a dollar figure here. Claude Code
    /// reports `total_cost_usd` whether or not anyone is paying per token, so on
    /// a subscription the number is a comparison, not a charge — and a bare
    /// dollar amount in a chat window reads as a bill.
    public static let costNote =
        "Cost is what this traffic would bill on the API — a subscription is not charged per token."

    /// The whole summary, as shown by `/usage`.
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
