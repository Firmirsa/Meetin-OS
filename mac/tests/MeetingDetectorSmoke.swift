import Foundation

@main
struct MeetingDetectorSmoke {
    static func main() {
        precondition(MeetingSignals.zoom(["Zoom Workplace"]) == .idle)
        precondition(MeetingSignals.zoom([" Réunion Zoom "]) == .active("zoom"))

        let room = "abc-defg-hij"
        for path in ["/\(room)", "/meet/\(room)?authuser=0"] {
            precondition(MeetingSignals.meetRoom(URL(string: "https://meet.google.com" + path)!) == room)
        }
        precondition(MeetingSignals.meetRoom(URL(string: "https://meet.google.com.evil.test/\(room)")!) == nil)
        precondition(MeetingSignals.meetRoom(URL(string: "https://meet.google.com/landing")!) == nil)
        precondition(!MeetingSignals.meetHangUp(["Participer à la réunion", "Demander à participer"]))
        precondition(MeetingSignals.meetHangUp(["Quitter l’appel"]))
        precondition(MeetingSignals.meetHangUp(["Leave call"]))

        precondition(!MeetingSignals.whatsAppHangUp(["Accepter", "Refuser", "Appel vocal"]))
        precondition(!MeetingSignals.whatsAppConnected(["Sonnerie…", "Ringing…", "Appel terminé"]))
        precondition(MeetingSignals.whatsAppHangUp(["Raccrocher"]))
        precondition(MeetingSignals.whatsAppHangUp(["End call"]))
        precondition(MeetingSignals.whatsAppConnected(["00:17"]))
        precondition(MeetingSignals.whatsAppConnected(["Appel en cours"]))

        var detector = MeetingDetector()
        let meet = detector.observe(.active(room), for: .meet).joined!
        precondition(detector.observe(.active(room), for: .meet).joined == nil)
        precondition(detector.observe(.unknown, for: .meet).left == nil)
        precondition(detector.observe(.active(room), for: .meet).joined == nil, "Le retour sur l’onglet ne renvoie pas une alerte")
        let whatsApp = detector.observe(.active("whatsapp"), for: .whatsapp).joined!
        precondition(detector.arrivals.count == 2)
        precondition(detector.accepts(whatsApp, presence: .active("whatsapp")))
        precondition(!detector.accepts(meet, presence: .idle), "Une action périmée ne peut pas enregistrer")
        precondition(!detector.accepts(meet, presence: .unknown))
        precondition(detector.observe(.idle, for: .meet).left == nil)
        precondition(detector.observe(.idle, for: .meet).left == meet)
        precondition(detector.current(.whatsapp) == whatsApp)
        let next = detector.observe(.active(room), for: .meet).joined!
        precondition(next.id != meet.id)
        precondition(!detector.accepts(meet, presence: .active(room)))
        precondition(detector.accepts(next, presence: .active(room)))
        let otherRoom = detector.observe(.active("xyz-uvwx-yza"), for: .meet)
        precondition(otherRoom.left == next && otherRoom.joined != nil)
        print("Meet, Zoom et WhatsApp : indices, arrivée unique et actions périmées vérifiés en simulé")
    }
}
