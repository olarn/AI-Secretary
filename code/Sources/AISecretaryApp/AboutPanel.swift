import AppKit
import SecretaryCore

@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppVersion.current.description,
            .version: "",
            .credits: credits
        ])
    }

    private static var credits: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let origin = AppInfo.build.map { build in
            AppInfo.branch.map { "\n\nBuild \(build) on \($0)" } ?? "\n\nBuild \(build)"
        } ?? ""
        return NSAttributedString(
            string: AppInfo.tagline + origin,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        )
    }
}
