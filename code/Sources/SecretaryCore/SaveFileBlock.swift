import FunctionalCore
import Foundation

/// A file the assistant made and is offering to hand over.
///
/// Work done without a project open happens in the scratch folder, which lives
/// under Application Support — a path nobody browses to. Before this the
/// spreadsheet she had just built was, from the person's side, nowhere: the
/// answer said "I've made the file" and there was no way to get it.
///
/// Same shape as `LoopBlock`, `SkillInstallBlock` and `MessageChoices`, for the
/// same reason: "I've written that up for you" is a sentence the model produces
/// constantly, and a Save button that appeared whenever it did would be a
/// button for a file that often doesn't exist. The offer is a marker or it is
/// prose.
///
/// ```save-file
/// report.xlsx
/// ```
public struct SaveFileBlock: Equatable, Sendable {
    /// The message with the block taken out, ready to render.
    public let body: String
    /// The names it offered, in the order written, already capped.
    public let names: [String]

    static let fence = "```save-file"

    /// How many files one block may offer.
    ///
    /// Not a technical limit — each file gets its own row and its own save
    /// panel, so nothing breaks at fifty. It is there because the card is a
    /// thing the person reads, and a turn that offers fifty files has gone
    /// wrong in a way that a scrolling card would hide rather than show.
    static let limit = 5

    public init(body: String, names: [String]) {
        self.body = body
        self.names = names
    }

    /// Splits a message. Anything without a block comes back untouched, which
    /// is nearly every message.
    public static func parse(_ text: String) -> SaveFileBlock {
        guard text.contains(fence) else { return SaveFileBlock(body: text, names: []) }

        var body: [String] = []
        var block: [String] = []
        var insideBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !insideBlock, trimmed == fence {
                insideBlock = true
                continue
            }
            if insideBlock {
                if trimmed.hasPrefix("```") {
                    insideBlock = false
                    continue
                }
                block.append(trimmed)
                continue
            }
            body.append(line)
        }

        return SaveFileBlock(
            body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            names: Array(block.filter { !$0.isEmpty }.prefix(limit))
        )
    }
}

/// One file on the card: what it is called, where it really is, and how big.
public struct OfferedFile: Equatable, Sendable, Identifiable {
    /// The resolved location is the identity — two rows for one file would be
    /// two buttons that do the same thing.
    public var id: String { url.path }
    /// What the card calls it, and what the save panel is pre-filled with.
    public let name: String
    public let url: URL
    public let byteCount: Int

    public init(name: String, url: URL, byteCount: Int) {
        self.name = name
        self.url = url
        self.byteCount = byteCount
    }
}

/// Why a name in the block is not something to offer.
public enum SaveOfferError: Error, Equatable, Sendable {
    case empty
    case notInsideScratch(name: String)
    case missing(name: String)
}

/// Turns one name from the block into a file that may be offered — or refuses.
///
/// **This is the security half of the feature, and the reason it is a function
/// with tests rather than a few lines in the view.** The name is written by the
/// model, and the button it produces copies a file wherever the person points
/// it. `../../.ssh/id_rsa`, or a plain `/etc/passwd`, must not become a
/// friendly Save button — so the name is resolved against the scratch folder
/// and has to land inside it.
///
/// Symlinks are resolved on both sides before the comparison, for two separate
/// reasons: a link written *into* the scratch folder would otherwise be a legal
/// path to anywhere, and the scratch folder's own path can contain a link that
/// makes a perfectly contained file look foreign (`/var` is a link to
/// `/private/var` on every Mac).
///
/// - Parameters:
///   - resolveSymlinks: injected so the containment rule can be tested without
///     making real links on disk; production passes the Foundation one.
///   - size: the file's length, absent when there is no file. Existence and
///     size are one question here — a card that offers something already gone
///     is a button that fails when pressed.
public func offeredFile(
    named raw: String,
    inScratch root: URL,
    resolveSymlinks: (URL) -> URL = { $0.resolvingSymlinksInPath() },
    size: (URL) -> Int? = { url in
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }
) -> Either<SaveOfferError, OfferedFile> {
    let name = raw.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return .left(.empty) }
    // Refused here rather than left to the containment check below, which would
    // accept it for the wrong reason: `appendingPathComponent("/etc/passwd")`
    // quietly produces `…/scratch/etc/passwd`, so an absolute name comes back as
    // "no such file" — safe, but it reads as though the path was searched, and
    // the next person to touch this would have no idea the rule was accidental.
    guard !name.hasPrefix("/"), !name.hasPrefix("~") else {
        return .left(.notInsideScratch(name: name))
    }

    let candidate = resolveSymlinks(root.appendingPathComponent(name).standardized)
    let base = resolveSymlinks(root.standardized)
    // The trailing separator matters: without it "/scratchings/x" reads as
    // being inside "/scratch".
    guard candidate.path.hasPrefix(base.path + "/") else {
        return .left(.notInsideScratch(name: name))
    }

    return Option.fromOptional(size(candidate))
        .fold(
            { .left(.missing(name: name)) },
            {
                .right(
                    OfferedFile(
                        name: candidate.lastPathComponent,
                        url: candidate,
                        byteCount: $0
                    )
                )
            }
        )
}

/// Every offer in one block that survives the rules above.
///
/// The refusals are dropped rather than reported: the person did not write the
/// block and can do nothing about a bad name in it, so the only useful outcome
/// is the files that are really there. A block where nothing survives leaves no
/// card at all.
public func offeredFiles(
    named raws: [String],
    inScratch root: URL,
    resolveSymlinks: (URL) -> URL = { $0.resolvingSymlinksInPath() },
    size: (URL) -> Int? = { url in
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }
) -> [OfferedFile] {
    raws
        .map { offeredFile(named: $0, inScratch: root, resolveSymlinks: resolveSymlinks, size: size) }
        // `fold`, because Bow's `Either` has no `toOptional` — only `Option` does.
        .compactMap { $0.fold({ _ -> OfferedFile? in nil }, { $0 }) }
}
