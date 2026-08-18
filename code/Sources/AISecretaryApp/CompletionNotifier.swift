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
    func post(_ notice: CompletionNotice, from characterID: UUID) {
        guard isAvailable else {
            NSLog("AISecretary: would notify — \(notice.title): \(notice.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = [Self.characterKey: characterID.uuidString]

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
    /// It normally cannot: `completionNotice` refuses to make one while the app
    /// is active with her chat open. It still can when the app is active and
    /// her chat is shut — someone typing to another character — and in that
    /// case the banner is the whole point, so it is shown rather than swallowed,
    /// which is what the system does by default.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
