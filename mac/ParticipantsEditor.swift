import SwiftUI

struct ParticipantsEditor: View {
    @Bindable var session: MeetingSession
    @State private var newName = ""

    private var sources: [TranscriptSource] {
        var seen = Set<TranscriptSource>()
        return session.participantLines.map(\.source).filter { seen.insert($0).inserted }
    }

    var body: some View {
        DisclosureGroup("Participants · modifier les noms et les sources") {
            editor
        }
        .font(.mtSans(14, weight: .medium))
        .mtCard()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Participants").font(.mtSans(14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Le micro utilise le nom de ton profil Google lorsqu’il est disponible, sinon le nom de ce Mac. Tu peux modifier les noms ici. Aucune identité distante n’est reconnue automatiquement.")
                .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
            ForEach(session.participants?.people ?? []) { person in
                HStack {
                    TextField("Nom", text: Binding(
                        get: { session.participants?.people.first { $0.id == person.id }?.name ?? "" },
                        set: { name in
                            guard let index = session.participants?.people.firstIndex(where: { $0.id == person.id }) else { return }
                            session.participants?.people[index].name = name
                        }
                    ))
                    .accessibilityLabel("Nom du participant \(person.name)")
                    if person.id == session.participants?.localParticipantID {
                        Text("Micro local").font(.mtSans(11)).foregroundStyle(Color.mtInk2)
                    }
                }
            }
            HStack {
                TextField("Ajouter un nom", text: $newName).onSubmit(addPerson)
                Button("Ajouter", action: addPerson)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source \(index + 1) · \(source.label) · segment \(source.segment + 1)")
                        .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                    Picker("Affecter la source \(index + 1)", selection: Binding<UUID?>(
                        get: { session.participants?.assignments.first { $0.source == source }?.participantID },
                        set: { session.participants?.assign($0, to: source) }
                    )) {
                        Text("Sans affectation").tag(nil as UUID?)
                        ForEach(Array((session.participants?.people ?? []).enumerated()), id: \.element.id) { number, person in
                            Text("\(person.name) · \(number + 1)").tag(Optional(person.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Affecter la source \(index + 1)")
                }
            }
            if sources.isEmpty {
                Text("Les sources du direct apparaîtront ici. Le texte ancien ou différé n’est pas réattribué.")
                    .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
            }
            Text("Chaque nouvelle session ou reprise garde ses propres sources. Le nom du micro est un repère modifiable.")
                .font(.mtSans(11)).foregroundStyle(Color.mtInk2)
        }
        .textFieldStyle(.roundedBorder)
        .mtCard()
    }

    private func addPerson() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        session.participants?.people.append(.init(id: UUID(), name: name))
        newName = ""
    }
}
