import Foundation

enum MeetingSource: String, CaseIterable, Sendable {
    case zoom = "Zoom"
    case meet = "Google Meet"
    case whatsapp = "WhatsApp"

    var notificationTitle: String {
        self == .whatsapp ? "Appel WhatsApp détecté" : "Réunion \(rawValue) détectée"
    }
}

enum MeetingPresence: Equatable, Sendable {
    case active(String)
    case idle
    case unknown
}

struct MeetingDetector {
    struct Arrival: Equatable, Sendable {
        let id = UUID()
        let source: MeetingSource
        let key: String
    }

    private struct State {
        let arrival: Arrival
        var absences = 0
    }

    private var states: [MeetingSource: State] = [:]
    var arrivals: [Arrival] { MeetingSource.allCases.compactMap { states[$0]?.arrival } }
    func current(_ source: MeetingSource) -> Arrival? { states[source]?.arrival }

    mutating func observe(_ presence: MeetingPresence, for source: MeetingSource) -> (joined: Arrival?, left: Arrival?) {
        switch presence {
        case .unknown:
            return (nil, nil)
        case .active(let key):
            if var previous = states[source], previous.arrival.key == key {
                previous.absences = 0
                states[source] = previous
                return (nil, nil)
            }
            let arrival = Arrival(source: source, key: key)
            let previous = states.updateValue(State(arrival: arrival), forKey: source)
            return (arrival, previous?.arrival)
        case .idle:
            guard var previous = states[source] else { return (nil, nil) }
            previous.absences += 1
            if previous.absences >= 2 {
                states.removeValue(forKey: source)
                return (nil, previous.arrival)
            }
            states[source] = previous
            return (nil, nil)
        }
    }

    func accepts(_ arrival: Arrival, presence: MeetingPresence) -> Bool {
        current(arrival.source) == arrival && presence == .active(arrival.key)
    }
}

enum MeetingSignals {
    static func zoom(_ titles: [String]) -> MeetingPresence {
        let meetingTitles = ["zoom meeting", "réunion zoom", "zoom webinar", "webinaire zoom"]
        return titles.contains { meetingTitles.contains(normalized($0)) } ? .active("zoom") : .idle
    }

    static func chromeURL(_ address: String) -> URL? {
        if address.hasPrefix("meet.google.com/") {
            return URL(string: "https://" + address)
        }
        return URL(string: address)
    }

    static func meetRoom(_ url: URL) -> String? {
        guard url.scheme == "https", url.host == "meet.google.com", url.port == nil,
              url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/")
        let code = parts.count == 2 && parts.first == "meet" ? parts.last : (parts.count == 1 ? parts.first : nil)
        guard let code, code.range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil else { return nil }
        return String(code)
    }

    static func meetWindowRoom(_ title: String) -> String? {
        let prefix = "Meet – "
        guard title.hasPrefix(prefix) else { return nil }
        let room = title.dropFirst(prefix.count).split(separator: " ").first
        guard let room, let url = URL(string: "https://meet.google.com/" + room) else { return nil }
        return meetRoom(url)
    }

    static func meetHangUp(_ labels: [String]) -> Bool {
        let labels = labels.map(normalized)
        return labels.contains { ["leave call", "leave the call", "leave meeting", "end call", "quitter l'appel", "quitter la réunion", "raccrocher"].contains($0) }
    }

    static func whatsAppHangUp(_ labels: [String]) -> Bool {
        let labels = labels.map(normalized)
        let hangUp = ["end call", "end the call", "end voice call", "end video call", "hang up", "raccrocher",
                      "terminer l'appel", "terminer l'appel vocal", "terminer l'appel vidéo", "mettre fin à l'appel", "quitter l'appel"]
        return labels.contains(where: hangUp.contains)
    }

    static func whatsAppConnected(_ labels: [String]) -> Bool {
        labels.map(normalized).contains { label in
            ["call in progress", "appel en cours"].contains(label) ||
                label.range(of: #"^(?:[0-9]{1,2}:)?[0-9]{1,2}:[0-5][0-9]$"#, options: .regularExpression) != nil
        }
    }

    private static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
    }
}
