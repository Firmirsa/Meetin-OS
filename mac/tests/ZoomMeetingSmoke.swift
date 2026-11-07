import Foundation

@main
struct ZoomMeetingSmoke {
    static func main() {
        var detector = ZoomMeetingDetector()
        let meeting = [" Réunion Zoom "]
        precondition(!detector.observe(["Zoom Workplace"]))
        precondition(detector.observe(meeting))
        guard let first = detector.arrivalID else { preconditionFailure("Arrivée Zoom manquante") }
        precondition(!detector.observe(meeting), "Une réunion ne doit déclencher qu’une arrivée")
        precondition(detector.isCurrentArrival(first, titles: meeting))
        precondition(!detector.isCurrentArrival(first, titles: nil), "Une lecture AX impossible interdit de lancer la capture")
        precondition(!detector.observe([]) && detector.inMeeting)
        precondition(!detector.isCurrentArrival(first, titles: []), "L’action est périmée dès que la fenêtre disparaît")
        precondition(!detector.observe(nil) && detector.inMeeting, "Une erreur AX ne termine pas la réunion")
        precondition(!detector.observe([]) && !detector.inMeeting)
        precondition(detector.observe(["Zoom Meeting"]))
        precondition(!detector.isCurrentArrival(first, titles: meeting), "L’alerte précédente ne peut pas lancer la nouvelle réunion")
        print("Arrivée unique, fin de réunion et rejet des actions périmées vérifiés")
    }
}
