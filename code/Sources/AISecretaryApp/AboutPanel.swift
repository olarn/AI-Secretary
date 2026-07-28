import AppKit
import SecretaryCore

/// The About window, opened from the status bar menu.
///
/// AppKit's own panel rather than a hand-built window: it already lays out the
/// icon, name, version and credits the way every other Mac app does, and this
/// app has no reason to look different in the one place users go to check what
/// they're running.
///
/// The values are passed explicitly instead of being read from the bundle. The
/// app is often run straight from the SwiftPM build directory, where there is no
/// `Info.plist` at all, and an About window that says "AISecretaryApp" with no
/// version is worse than none.
@MainActor
enum AboutPanel {
    static func show() {
        // The panels never take focus, so without this the window opens behind
        // whatever the user is working in — it looks like nothing happened.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppVersion.current.description,
            // Blank, or AppKit appends its own build number in parentheses;
            // there is only one number worth showing here.
            .version: "",
            .credits: credits
        ])
    }

    private static var credits: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        // The commit is here rather than in the version line so the version
        // stays the thing people quote, while "which build is this?" — the
        // question that comes up when a fixed thing looks broken again — is
        // still answerable without a terminal.
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
