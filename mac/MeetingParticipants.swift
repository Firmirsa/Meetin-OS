import Foundation

struct MeetingParticipant: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
}

struct TranscriptSource: Codable, Hashable {
    let track: String
    let segment: Int
    let session: String
    let speaker: Int?

    var label: String {
        let audio = track == "microphone" ? "Micro" : "Audio distant"
        let voice = speaker.map { " · voix \($0 + 1)" } ?? " · source non séparée"
        return "\(audio)\(voice)"
    }
}

struct StructuredTranscriptLine: Codable, Identifiable, Equatable {
    let id: String
    let time: Double
    let source: TranscriptSource
    let text: String
}

struct ParticipantAssignment: Codable, Equatable {
    let source: TranscriptSource
    var participantID: UUID
}

struct MeetingParticipants: Codable, Equatable {
    var people: [MeetingParticipant] = []
    var assignments: [ParticipantAssignment] = []
    var localParticipantID: UUID?

    static func newMeeting(localName: String) -> Self {
        let local = MeetingParticipant(id: UUID(), name: localName)
        return Self(people: [local], localParticipantID: local.id)
    }

    func label(for source: TranscriptSource) -> String {
        if let assignment = assignments.first(where: { $0.source == source }),
           let person = people.first(where: { $0.id == assignment.participantID }) {
            return "\(person.name) (\(source.label))"
        }
        if source.track == "microphone",
           let local = people.first(where: { $0.id == localParticipantID }) {
            return "\(local.name) (\(source.label))"
        }
        return source.label
    }

    mutating func assign(_ participantID: UUID?, to source: TranscriptSource) {
        assignments.removeAll { $0.source == source }
        if let participantID, people.contains(where: { $0.id == participantID }) {
            assignments.append(.init(source: source, participantID: participantID))
        }
    }

    func render(_ lines: [StructuredTranscriptLine]) -> String {
        lines.map { line in
            let seconds = Int(line.time.isFinite ? min(max(0, line.time), 86_400) : 0)
            let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            return "[\(time)] \(label(for: line.source)) · \(line.text)"
        }.joined(separator: "\n")
    }
}
