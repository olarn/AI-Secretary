import FunctionalCore
import XCTest
@testable import SecretaryCore

/// Which files the assistant may offer to hand over, and which names are
/// refused before they can become a button.
final class SaveFileBlockTests: XCTestCase {
    private let scratch = URL(fileURLWithPath: "/Users/someone/Library/Application Support/AISecretary/scratch")

    /// No symlinks and no disk: the containment rule is the thing under test,
    /// so both sides are left exactly as written.
    private let noLinks: (URL) -> URL = { $0 }

    private func offer(
        _ name: String,
        sizes: [String: Int] = ["/Users/someone/Library/Application Support/AISecretary/scratch/report.xlsx": 2048]
    ) -> Either<SaveOfferError, OfferedFile> {
        offeredFile(
            named: name,
            inScratch: scratch,
            resolveSymlinks: noLinks,
            size: { sizes[$0.path] }
        )
    }

    // MARK: - Reading the block

    func testTakesTheBlockOutOfTheMessage() {
        let parsed = SaveFileBlock.parse("Here's the report.\n\n```save-file\nreport.xlsx\n```")

        XCTAssertEqual(parsed.body, "Here's the report.")
        XCTAssertEqual(parsed.names, ["report.xlsx"])
    }

    /// Nearly every message. Left exactly as it was.
    func testAMessageWithNoBlockIsUntouched() {
        let text = "I've written that up for you, it's in the folder."
        let parsed = SaveFileBlock.parse(text)

        XCTAssertEqual(parsed.body, text)
        XCTAssertEqual(parsed.names, [])
    }

    func testSeveralFilesInOneBlock() {
        let parsed = SaveFileBlock.parse("Done.\n\n```save-file\nreport.xlsx\nchart.png\n```")

        XCTAssertEqual(parsed.names, ["report.xlsx", "chart.png"])
    }

    /// A card is something a person reads; a turn offering fifty files has gone
    /// wrong in a way a scrolling card would hide.
    func testStopsAtFive() {
        let names = (1...9).map { "file\($0).txt" }.joined(separator: "\n")
        let parsed = SaveFileBlock.parse("Done.\n\n```save-file\n\(names)\n```")

        XCTAssertEqual(parsed.names.count, 5)
        XCTAssertEqual(parsed.names.last, "file5.txt")
    }

    // MARK: - What may be offered

    func testOffersAFileThatIsReallyThere() {
        let file = offer("report.xlsx").fold({ _ -> OfferedFile? in nil }, { $0 })

        XCTAssertEqual(file?.name, "report.xlsx")
        XCTAssertEqual(file?.byteCount, 2048)
    }

    /// The reason this is a tested function and not a few lines in the view.
    func testRefusesAWayOut() {
        XCTAssertEqual(
            offer("../../../.ssh/id_rsa"),
            .left(.notInsideScratch(name: "../../../.ssh/id_rsa"))
        )
    }

    func testRefusesAnAbsolutePath() {
        XCTAssertEqual(
            offer("/etc/passwd"),
            .left(.notInsideScratch(name: "/etc/passwd"))
        )
    }

    /// A sibling folder whose name merely starts the same way. The trailing
    /// separator in the check is what catches this.
    func testRefusesASiblingWithASharedPrefix() {
        let sneaky = "../scratchings/secrets.txt"

        XCTAssertEqual(offer(sneaky), .left(.notInsideScratch(name: sneaky)))
    }

    /// A link written inside the scratch folder is a legal-looking path to
    /// anywhere, so the comparison happens after both sides are resolved.
    func testRefusesALinkThatPointsOut() {
        let offered = offeredFile(
            named: "escape.txt",
            inScratch: scratch,
            resolveSymlinks: { url in
                url.lastPathComponent == "escape.txt"
                    ? URL(fileURLWithPath: "/Users/someone/.ssh/id_rsa")
                    : url
            },
            size: { _ in 64 }
        )

        XCTAssertEqual(offered, .left(.notInsideScratch(name: "escape.txt")))
    }

    /// The scratch folder's own path can contain a link — `/var` is one on
    /// every Mac — and a contained file must not look foreign because of it.
    func testAcceptsWhenTheFolderItselfIsALink() {
        let linked = URL(fileURLWithPath: "/var/folders/T/scratch")
        let offered = offeredFile(
            named: "report.xlsx",
            inScratch: linked,
            resolveSymlinks: { url in
                URL(fileURLWithPath: url.path.replacingOccurrences(of: "/var/", with: "/private/var/"))
            },
            size: { _ in 10 }
        )

        XCTAssertEqual(offered.fold({ _ -> OfferedFile? in nil }, { $0 })?.url.path, "/private/var/folders/T/scratch/report.xlsx")
    }

    /// A button that fails when pressed is worse than no button.
    func testRefusesAFileThatIsNotThere() {
        XCTAssertEqual(offer("imaginary.pdf"), .left(.missing(name: "imaginary.pdf")))
    }

    func testRefusesAnEmptyName() {
        XCTAssertEqual(offer("   "), .left(.empty))
    }

    /// The person didn't write the block and can do nothing about a bad name in
    /// it, so the good ones still come through.
    func testKeepsTheGoodNamesAndDropsTheRest() {
        let files = offeredFiles(
            named: ["report.xlsx", "../../../etc/passwd", "imaginary.pdf"],
            inScratch: scratch,
            resolveSymlinks: noLinks,
            size: { $0.lastPathComponent == "report.xlsx" ? 2048 : nil }
        )

        XCTAssertEqual(files.map(\.name), ["report.xlsx"])
    }
}
