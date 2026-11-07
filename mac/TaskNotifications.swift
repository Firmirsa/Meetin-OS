import UserNotifications

// Notification par tâche détectée : titre, Confirmer et champ de contexte.
final class TaskNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TaskNotifications()

    private static let category = "meetin.task"
    private static let confirm = "meetin.task.confirm"
    private static let context = "meetin.task.context"
    private static let proposalKey = "proposalID"
    private static let approvalKey = "approval"

    @MainActor private weak var session: MeetingSession?

    @MainActor func attach(_ session: MeetingSession) {
        self.session = session
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category,
            actions: [
                UNNotificationAction(identifier: Self.confirm, title: "Confirmer", options: [.authenticationRequired]),
                UNTextInputNotificationAction(
                    identifier: Self.context, title: "Ajouter du contexte et lancer", options: [.authenticationRequired],
                    textInputButtonTitle: "Lancer", textInputPlaceholder: "Contexte pour l’agent"
                )
            ],
            intentIdentifiers: []
        )])
    }

    func post(_ proposal: TaskProposal) {
        let content = UNMutableNotificationContent()
        content.title = "À valider : \(proposal.review.title)"
        content.body = "\(proposal.review.executor.name) · \(proposal.review.destination)"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.proposalKey: proposal.id, Self.approvalKey: proposal.review.approval]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: proposal.id, content: content, trigger: nil)
        )
    }

    func remove(_ proposalID: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [proposalID])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = info[Self.proposalKey] as? String else { return }
        let approval = info[Self.approvalKey] as? String
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            guard action != UNNotificationDismissActionIdentifier else { return }
            switch action {
            case Self.confirm: session?.handleTaskNotification(id: id, shownApproval: approval, confirm: true, context: nil)
            case Self.context: session?.handleTaskNotification(id: id, shownApproval: approval, confirm: true, context: text)
            default: session?.handleTaskNotification(id: id, shownApproval: approval, confirm: false, context: nil)
            }
        }
    }
}
