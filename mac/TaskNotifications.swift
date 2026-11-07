import UserNotifications

// Délègue les actions des notifications de tâches et d’arrivée en réunion.
final class TaskNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TaskNotifications()

    private static let category = "meetin.task"
    private static let confirm = "meetin.task.confirm"
    private static let context = "meetin.task.context"
    private static let proposalKey = "proposalID"
    private static let approvalKey = "approval"
    private static let meetingCategory = "meetin.meeting-arrival"
    private static let record = "meetin.meeting-arrival.record"
    private static let arrivalKey = "meetingArrivalID"

    @MainActor private weak var session: MeetingSession?

    @MainActor func attach(_ session: MeetingSession) {
        self.session = session
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let taskCategory = UNNotificationCategory(
            identifier: Self.category,
            actions: [
                UNNotificationAction(identifier: Self.confirm, title: "Confirmer", options: [.authenticationRequired]),
                UNTextInputNotificationAction(
                    identifier: Self.context, title: "Ajouter du contexte et lancer", options: [.authenticationRequired],
                    textInputButtonTitle: "Lancer", textInputPlaceholder: "Contexte pour l’agent"
                )
            ],
            intentIdentifiers: []
        )
        let meetingCategory = UNNotificationCategory(
            identifier: Self.meetingCategory,
            actions: [UNNotificationAction(identifier: Self.record, title: "Enregistrer",
                                           options: [.foreground, .authenticationRequired])],
            intentIdentifiers: []
        )
        center.setNotificationCategories([taskCategory, meetingCategory])
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

    func postMeetingArrival(_ arrival: MeetingDetector.Arrival) {
        let content = UNMutableNotificationContent()
        content.title = arrival.source.notificationTitle
        content.body = "Démarre l’enregistrement avec Meetin-OS."
        content.categoryIdentifier = Self.meetingCategory
        content.userInfo = [Self.arrivalKey: arrival.id.uuidString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: meetingNotificationID(arrival.id), content: content, trigger: nil)
        )
    }

    func removeMeetingArrival(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        let identifiers = [meetingNotificationID(id)]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func meetingNotificationID(_ id: UUID) -> String { "\(Self.meetingCategory).\(id.uuidString)" }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let info = content.userInfo
        let action = response.actionIdentifier
        if content.categoryIdentifier == Self.meetingCategory {
            guard let raw = info[Self.arrivalKey] as? String, let id = UUID(uuidString: raw),
                  action == Self.record || action == UNNotificationDefaultActionIdentifier else { return }
            let start = action == Self.record
            await session?.handleMeetingArrivalNotification(id: id, start: start)
            return
        }
        guard let id = info[Self.proposalKey] as? String else { return }
        let approval = info[Self.approvalKey] as? String
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
