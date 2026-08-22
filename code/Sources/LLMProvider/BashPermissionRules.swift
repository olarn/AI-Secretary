import Foundation

public func bashPermissionRules(for command: String) -> [String] {
    var seen = Set<String>()
    return bashSubcommands(command)
        .map(bashRulePrefix)
        .filter { !$0.isEmpty }
        .map { "Bash(\($0) *)" }
        .filter { seen.insert($0).inserted }
}

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
            let isARealSeparatorRatherThanPartOfARedirect = doubled || character == "|"
            guard isARealSeparatorRatherThanPartOfARedirect else {
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
