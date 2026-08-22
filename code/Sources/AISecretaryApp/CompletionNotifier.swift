import AppKit
import UserNotifications
import SecretaryCore

@MainActor
final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let onOpen: (UUID) -> Void

    private let isAvailable = Bundle.main.bundleIdentifier != nil

    init(onOpen: @escaping (UUID) -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    private nonisolated static let characterKey = "character"

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
                trigger: nil
            )
        ) { error in
            if let error {
                NSLog("AISecretary: could not post a notification — \(error.localizedDescription)")
            }
        }
    }

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
