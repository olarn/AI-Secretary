import Foundation

/// The permission rules one refused `Bash` call needs before it will run.
///
/// Written because approving did nothing. Claude Code splits a command on its
/// shell operators and requires **every part** to be permitted — it says so
/// when it refuses: *"This Bash command contains multiple operations. The
/// following parts require approval: …"*. One rule built from the head of the
/// whole command therefore authorises, at best, the first operation, and the
/// retry is refused exactly as before. The person is asked, says yes, and
/// watches the same wall (verified against Claude Code 2.1.229).
///
/// The second half of the same bug was the head itself: it was the first two
/// space-separated tokens, so a quoted path with a space in it was cut in the
/// middle — `cd "/Users/…/TISCO - AI Sharing"` became the rule
/// `Bash(cd "/Users/…/TISCO *)`, with the quote left open, matching nothing.
public func bashPermissionRules(for command: String) -> [String] {
    var seen = Set<String>()
    return bashSubcommands(command)
        .map(bashRulePrefix)
        .filter { !$0.isEmpty }
        .map { "Bash(\($0) *)" }
        .filter { seen.insert($0).inserted }
}

/// Splits on `&&`, `||`, `|` and `;` that are outside quotes.
///
/// Quote state is the whole reason this is not `components(separatedBy:)`: a
/// `;` or `|` inside an argument is data, not an operator, and splitting there
/// would produce rules for fragments that are not commands.
func bashSubcommands(_ command: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var index = command.startIndex

    while index < command.endIndex {
        let character = command[index]

        if let open = quote {
            current.append(character)
            if character == open { quote = nil }
            index = command.index(after: index)
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
            current.append(character)
            index = command.index(after: index)
            continue
        }
        if character == ";" {
            parts.append(current)
            current = ""
            index = command.index(after: index)
            continue
        }
        if character == "&" || character == "|" {
            let next = command.index(after: index)
            let doubled = next < command.endIndex && command[next] == character
            // A lone `&` is not a separator worth splitting on: in `2>&1` — the
            // tail of the very command that started this — it is part of a
            // redirect, and splitting there invented a rule for a sub-command
            // called `1`. Backgrounding with a trailing `&` is left attached to
            // its command for the same reason: no rule is better than a wrong
            // one. A lone `|` is a real pipe and does split.
            guard doubled || character == "|" else {
                current.append(character)
                index = next
                continue
            }
            parts.append(current)
            current = ""
            index = doubled ? command.index(after: next) : next
            continue
        }
        current.append(character)
        index = command.index(after: index)
    }
    parts.append(current)

    return parts
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

/// The first two words of one sub-command, as they were written.
///
/// Two words rather than one so that approving `npm test` does not hand over
/// `npm publish`, and rather than the whole command so that a retry which
/// phrases the tail slightly differently is still covered.
///
/// Returned as a slice of the original rather than rebuilt from parsed tokens,
/// so the quoting a path needs is still around it.
func bashRulePrefix(_ subcommand: String) -> String {
    var quote: Character?
    var words = 0
    var inWord = false
    var index = subcommand.startIndex
    var endOfSecondWord = subcommand.endIndex

    while index < subcommand.endIndex {
        let character = subcommand[index]

        if let open = quote {
            if character == open { quote = nil }
        } else if character == "\"" || character == "'" {
            quote = character
            if !inWord { inWord = true; words += 1 }
        } else if character == " " || character == "\t" {
            if inWord {
                inWord = false
                if words == 2 {
                    endOfSecondWord = index
                    break
                }
            }
        } else if !inWord {
            inWord = true
            words += 1
        }
        index = subcommand.index(after: index)
    }

    return String(subcommand[subcommand.startIndex..<endOfSecondWord])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
