import SwiftUI

struct MeetingList: View {
    let records: [MeetingRecord]
    let session: MeetingSession

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Rectangle().fill(Color.mtLine).frame(height: 1) }
                MeetingRow(record: record) { session.open(record) }
                    .disabled(!session.canSwitchMeeting)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.card))
        .mtGlass()
    }
}

private struct MeetingRow: View {
    let record: MeetingRecord
    let open: () -> Void
    @State private var hovering = false

    private var meta: String {
        [MeetingFormat.day(record.date), MeetingFormat.time(record.date), record.source]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var statusText: String {
        if record.transcript.isEmpty { return "À transcrire" }
        return record.transcriptIncomplete == true ? "Incomplète" : "Transcrite"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(.mtSans(14, weight: .medium)).lineLimit(1)
                    Text(meta).font(.mtSans(12)).foregroundStyle(Color.mtInk2).lineLimit(1)
                }
                Spacer(minLength: 12)
                MTPill(text: statusText, kind: record.transcript.isEmpty || record.transcriptIncomplete == true ? .run : .wait)
                Text(MeetingFormat.duration(record.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.mtInk2)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(hovering ? Color.mtInk.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

enum MeetingFormat {
    private static let french = Locale(identifier: "fr_FR")

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy"
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "\(max(Int(seconds.rounded()), 0)) s" }
        return "\(Int((seconds / 60).rounded())) min"
    }
}

struct MeetingsView: View {
    @Bindable var session: MeetingSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Réunions").font(.mtSerif(40)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Ouvrir un enregistrement", systemImage: "folder") { session.importRecording() }
                        .buttonStyle(.mtGhost)
                        .disabled(!session.canSwitchMeeting)
                }
                if session.capture != nil {
                    Text("Enregistrement en cours. Arrête-le pour rouvrir une réunion.")
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtInk2)
                }
                if let error = session.store.lastError {
                    Text(error).font(.mtSans(13)).foregroundStyle(Color.mtWarn).textSelection(.enabled)
                }
                if session.store.meetings.isEmpty {
                    Text("Aucune réunion pour l’instant. Ton premier enregistrement apparaîtra ici.")
                        .font(.mtSans(14))
                        .foregroundStyle(Color.mtInk2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .mtGlass()
                } else {
                    MeetingList(records: session.store.meetings, session: session)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

// Une réunion ouverte réutilise le carnet existant : notes, transcription et onglet Agent.
struct MeetingDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession

    private var titleBinding: Binding<String> {
        Binding(
            get: { session.currentMeeting?.title ?? "" },
            set: { value in
                guard let id = session.meetingID else { return }
                session.store.update(id) { $0.title = value }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { session.route = .meetings } label: {
                        Label("Réunions", systemImage: "chevron.left").font(.mtSans(13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.mtInk2)
                    Spacer()
                    if session.meetingIsActive {
                        Button("Afficher la réunion", systemImage: "rectangle.on.rectangle") {
                            openWindow(id: "meeting")
                        }
                        .buttonStyle(MTCapsuleLinkStyle())
                    }
                    Button("Nouvel enregistrement", systemImage: "plus") {
                        CaptureView.toggleRecording(session: session, openWindow: openWindow)
                    }
                    .buttonStyle(MTCapsuleLinkStyle())
                    .disabled(session.busy || session.agent.busy)
                }
                TextField("Titre de la réunion", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.mtSerif(34))
                    .accessibilityLabel("Titre de la réunion")
                if let meeting = session.currentMeeting {
                    Text([
                        MeetingFormat.day(meeting.date),
                        MeetingFormat.time(meeting.date),
                        MeetingFormat.duration(meeting.duration),
                        meeting.source
                    ].compactMap { $0 }.joined(separator: " · "))
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
                    if meeting.transcriptIncomplete == true {
                        Text("Transcription incomplète : le direct a été interrompu. « Transcrire » reprend tout l’appel depuis le fichier.")
                            .font(.mtSans(13))
                            .foregroundStyle(Color.mtWarn)
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)

            CaptureView(session: session)
                .id(session.meetingID)
        }
    }
}
