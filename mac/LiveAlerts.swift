import UserNotifications

// Notifications du direct : uniquement quand il ne marche pas.
enum LiveAlerts {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
