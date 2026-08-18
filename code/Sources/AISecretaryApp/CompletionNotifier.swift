import AppKit
import UserNotifications
import SecretaryCore

/// Puts a macOS banner up when a character finishes work nobody was watching,
/// and opens her chat when it is clicked.
///
/// **Nothing here works without a bundle.** `UNUserNotificationCenter.current()`
/// looks the process up by bundle identifier and raises an ObjC exception when
/// there isn't one — which cannot be caught from Swift, so it is a crash, not an
/// error. `swift run AISecretaryApp` has no bundle, and that is the command the
/// charter's "drive it before committing" step uses, so every entry point here
/// checks `isAvailable` first and does nothing when the answer is no. Under
/// `swift run` the decision still runs and is logged; the banner itself can
/// only be checked from the packaged `.app`.
///
/// There is no setting for any of this on purpose: the backlog asks for
/// "notification settings ตาม macOS", so System Settings → Notifications is the
/// control surface, and a second switch inside the app would only be a way for
/// the two to disagree.
@MainActor
final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Which character a click should open. The id travels in the
    /// notification's `userInfo` rather than being remembered here, because the
    /// click that matters most arrives at a process that has only just
    /// launched and remembers nothing.
    private let onOpen: (UUID) -> Void

    /// Whether this process can talk to the notification centre at all — see
    /// the note on the type.
    private let isAvailable = Bundle.main.bundleIdentifier != nil

    init(onOpen: @escaping (UUID) -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    /// Read from the delegate callback, which the system calls off the main
    /// actor — hence `nonisolated`, without which Swift 6 rejects it.
    private nonisolated static let characterKey = "character"

    /// Claims the delegate and asks, once, for permission.
    ///
    /// **Must be called from `applicationDidFinishLaunching` before it
    /// returns.** A click on a banner is allowed to launch the app, and the
    /// system delivers that click as soon as the delegate exists; installed any
    /// later, the launch-by-click path silently does nothing.
    func start() {
        guard isAvailable else {
            NSLog("AISecretary: no bundle — notifications are off for this run.")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("AISecretary: notification authorization failed — \(error.localizedDescription)")
            } else if !granted {
                NSLog("AISecretary: notifications not permitted; System Settings → Notifications.")
            }
        }
    }

    /// Posts one banner for one character.
    ///
    /// The identifier is the character's, so a second answer from the same
    /// character replaces her own waiting banner instead of stacking — ten
    /// loop checks while you are out should leave the latest, not a column.
    ///
    /// - Parameter picture: her own portrait, when she has one. It becomes the
    ///   image on the right of the banner — **not** the small icon on the left,
    ///   which is the app's and cannot be set per notification: macOS reads that
    ///   one from the bundle. With four characters answering, the portrait is
    ///   what says which of them this is before you read the name.
    func post(_ notice: CompletionNotice, from characterID: UUID, picture: URL?) {
        guard isAvailable else {
            NSLog("AISecretary: would notify — \(notice.title): \(notice.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = [Self.characterKey: characterID.uuidString]
        if let attachment = picture.flatMap(Self.attachment) {
            content.attachments = [attachment]
        }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: characterID.uuidString,
                content: content,
                // nil means "now" — a trigger would schedule it.
                trigger: nil
            )
        ) { error in
            if let error {
                NSLog("AISecretary: could not post a notification — \(error.localizedDescription)")
            }
        }
    }

    /// Her portrait, wrapped for the notification centre.
    ///
    /// **Attaches a copy, never the original.** `UNNotificationAttachment`
    /// takes ownership of the file it is given and moves it into its own store,
    /// so handing it `ProfileArtwork`'s URL would take the character's picture
    /// off disk — she would lose her face the first time she finished something
    /// unwatched. The copy goes to the temporary directory, which the system
    /// empties by itself; if the attachment can't be made, the copy is removed
    /// here rather than left behind.
    private nonisolated static func attachment(for picture: URL) -> UNNotificationAttachment? {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("notice-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: picture, to: copy)
            return try UNNotificationAttachment(identifier: "", url: copy, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            NSLog("AISecretary: could not attach the picture — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let id = (info[Self.characterKey] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if let id { self.onOpen(id) }
            completionHandler()
        }
    }

    /// What to do when one arrives while the app is frontmost.
    ///
    /// It can: `completionNotice` refuses only while *her* chat is on screen, so
    /// somebody typing to another character still gets one. There the banner is
    /// the whole point, and it is shown rather than swallowed, which is what the
    /// system does by default with the app in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
