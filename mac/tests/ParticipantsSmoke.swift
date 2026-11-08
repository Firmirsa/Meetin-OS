import Foundation

@main
struct ParticipantsSmoke {
    static func main() throws {
        var participants = MeetingParticipants.newMeeting(localName: "Vous")
        let first = MeetingParticipant(id: UUID(), name: "Léni")
        let second = MeetingParticipant(id: UUID(), name: "Léni")
        participants.people += [first, second]
        let source = TranscriptSource(track: "system", segment: 0, session: "connection-a:session-a", speaker: 0)
        let otherSession = TranscriptSource(track: "system", segment: 0, session: "connection-b:session-b", speaker: 0)
        let resumed = TranscriptSource(track: "system", segment: 1, session: "connection-a:session-a", speaker: 0)
        let unsplit = TranscriptSource(track: "system", segment: 0, session: "connection-a:session-a", speaker: nil)
        let line = StructuredTranscriptLine(id: "one", time: 1.5, source: source, text: "Bonjour.")
        participants.assign(first.id, to: source)
        participants.assign(second.id, to: otherSession)
        precondition(participants.assignments.count == 2)
        precondition(participants.assignments[0].participantID != participants.assignments[1].participantID)
        participants.people[1].name = "Léni renommé"
        precondition(participants.render([line]).contains("Léni renommé"))
        precondition(!participants.label(for: otherSession).contains("renommé"))
        precondition(!participants.label(for: resumed).contains("Léni"))
        precondition(participants.label(for: unsplit).contains("source non séparée"))
        precondition(!participants.label(for: unsplit).contains("Léni"))

        struct Fixture: Codable {
            var transcript: String
            var notes: String
            var audioPath: String
            var participants: MeetingParticipants?
            var structuredLines: [StructuredTranscriptLine]?
        }
        let fixture = Fixture(transcript: participants.render([line]), notes: "Décision",
                              audioPath: "/fixture/audio.m4a", participants: participants, structuredLines: [line])
        let restored = try JSONDecoder().decode(Fixture.self, from: JSONEncoder().encode(fixture))
        precondition(restored.participants == participants && restored.structuredLines == [line])
        precondition(restored.participants?.render(restored.structuredLines!) == fixture.transcript)
        let legacy = Data(#"{"transcript":"[00:01] Voix · Texte original","notes":"note","audioPath":"/ancien.m4a"}"#.utf8)
        let old = try JSONDecoder().decode(Fixture.self, from: legacy)
        precondition(old.participants == nil && old.structuredLines == nil)
        precondition(old.transcript == "[00:01] Voix · Texte original" && old.notes == "note" && old.audioPath == "/ancien.m4a")
        participants.assign(nil, to: source)
        precondition(!participants.label(for: source).contains("Léni"))
        print("Participants: identity, scope, rendering and Codable smoke passed")
    }
}
