import FunctionalCore
import XCTest
@testable import SecretaryCore

final class SaveFileBlockTests: XCTestCase {
    private let scratch = URL(fileURLWithPath: "/Users/someone/Library/Application Support/AISecretary/scratch")

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

    func testTakesTheBlockOutOfTheMessage() {
        let parsed = SaveFileBlock.parse("Here's the report.\n\n```save-file\nreport.xlsx\n```")

        XCTAssertEqual(parsed.body, "Here's the report.")
        XCTAssertEqual(parsed.names, ["report.xlsx"])
    }

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

    func testStopsAtFive() {
        let names = (1...9).map { "file\($0).txt" }.joined(separator: "\n")
        let parsed = SaveFileBlock.parse("Done.\n\n```save-file\n\(names)\n```")

        XCTAssertEqual(parsed.names.count, 5)
        XCTAssertEqual(parsed.names.last, "file5.txt")
    }

    func testOffersAFileThatIsReallyThere() {
        let file = offer("report.xlsx").fold({ _ -> OfferedFile? in nil }, { $0 })

        XCTAssertEqual(file?.name, "report.xlsx")
        XCTAssertEqual(file?.byteCount, 2048)
    }

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

    func testRefusesASiblingWithASharedPrefix() {
        let sneaky = "../scratchings/secrets.txt"

        XCTAssertEqual(offer(sneaky), .left(.notInsideScratch(name: sneaky)))
    }

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

    func testRefusesAFileThatIsNotThere() {
        XCTAssertEqual(offer("imaginary.pdf"), .left(.missing(name: "imaginary.pdf")))
    }

    func testRefusesAnEmptyName() {
        XCTAssertEqual(offer("   "), .left(.empty))
    }

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
