import UserNotifications

// Notifications du direct : uniquement quand il ne marche pas.
enum LiveAlerts {
    static func requestPermission(onStatus: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            readPermission(onStatus)
        }
    }

    static func readPermission(_ onStatus: @escaping @MainActor @Sendable (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in onStatus(denied) }
        }
    }

    static func postTask(_ title: String, _ message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static func post(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription en direct interrompue"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
