import SwiftUI

struct MeetingList: View {
    let records: [MeetingRecord]
    let session: MeetingSession
    @State private var renaming: MeetingRecord?
    @State private var draftTitle = ""
    @State private var deleting: MeetingRecord?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Rectangle().fill(Color.mtLine).frame(height: 1) }
                MeetingRow(
                    record: record,
                    canOpen: session.canSwitchMeeting,
                    canDelete: session.canDeleteMeetings,
                    open: { session.open(record) },
                    rename: {
                        draftTitle = record.title
                        renaming = record
                    },
                    delete: { deleting = record }
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.card))
        .mtGlass()
        .alert("Renommer la réunion", isPresented: isPresent($renaming), presenting: renaming) { record in
            TextField("Titre de la réunion", text: $draftTitle)
            Button("Renommer") { session.renameMeeting(record.id, to: draftTitle) }
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Le nouveau titre est enregistré sur ce Mac.")
        }
        .meetingDeletion($deleting, session: session)
    }
}

// Vrai tant qu'une réunion est choisie ; fermer la fenêtre remet le choix à nil.
private func isPresent<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

// Confirmation commune à la liste et à la fiche avant de supprimer une réunion.
struct MeetingDeletion: ViewModifier {
    @Binding var record: MeetingRecord?
    let session: MeetingSession

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Supprimer cette réunion ?", isPresented: isPresent($record), titleVisibility: .visible, presenting: record
        ) { record in
            Button("Supprimer", role: .destructive) { session.deleteMeeting(record.id) }
            Button("Annuler", role: .cancel) {}
        } message: { record in
            Text(session.store.ownsAudio(record.id)
                ? "« \(record.title) » : l’audio et la transcription seront effacés. Le dossier audio part dans la Corbeille de macOS, d’où tu peux encore le récupérer."
                : "« \(record.title) » : la transcription et les notes seront effacées. Le fichier audio d’origine reste à sa place.")
        }
    }
}

extension View {
    func meetingDeletion(_ record: Binding<MeetingRecord?>, session: MeetingSession) -> some View {
        modifier(MeetingDeletion(record: record, session: session))
    }
}

private struct MeetingRow: View {
    let record: MeetingRecord
    let canOpen: Bool
    let canDelete: Bool
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    @ViewBuilder private var actions: some View {
        Button("Renommer…", systemImage: "pencil", action: rename)
        Button("Supprimer…", systemImage: "trash", role: .destructive, action: delete)
            .disabled(!canDelete)
    }

    private var meta: String {
        [MeetingFormat.day(record.date), MeetingFormat.time(record.date), record.source]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var statusText: String {
        if record.pendingProposals > 0 { return "\(record.pendingProposals) à valider" }
        if record.transcript.isEmpty { return "À transcrire" }
        return record.transcriptIncomplete == true ? "Incomplète" : "Transcrite"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title).font(.mtSans(14, weight: .medium)).lineLimit(1)
                        Text(meta).font(.mtSans(12)).foregroundStyle(Color.mtInk2).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    MTPill(
                        text: statusText,
                        kind: record.pendingProposals > 0 || record.transcript.isEmpty || record.transcriptIncomplete == true ? .run : .wait
                    )
                    Text(MeetingFormat.duration(record.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.mtInk2)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .padding(.leading, 18)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)

            Menu { actions } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Renommer ou supprimer")
            .accessibilityLabel("Actions pour « \(record.title) »")
            .padding(.trailing, 12)
        }
        .background(hovering ? Color.mtInk.opacity(0.04) : Color.clear)
        .contextMenu { actions }
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
    @State private var titleDraft = ""
    @State private var draftMeetingID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var deleting: MeetingRecord?

    // Le titre est enregistré à la validation (Entrée) ou quand le champ perd le focus. Vide, l'ancien titre revient.
    // Le brouillon garde l'identifiant de sa réunion : il ne peut pas renommer une autre réunion ouverte entre-temps.
    private func commitTitle() {
        guard let id = draftMeetingID else { return }
        if !session.renameMeeting(id, to: titleDraft) {
            titleDraft = session.store.meeting(id: id)?.title ?? ""
        }
    }

    private func loadDraft() {
        commitTitle()
        draftMeetingID = session.meetingID
        titleDraft = session.currentMeeting?.title ?? ""
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
                    Button("Supprimer", systemImage: "trash") { deleting = session.currentMeeting }
                        .buttonStyle(MTCapsuleLinkStyle())
                        .disabled(session.currentMeeting == nil || !session.canDeleteMeetings)
                        .help(session.canDeleteMeetings
                            ? "Supprimer cette réunion"
                            : "Attends la fin de l’enregistrement ou de la transcription pour supprimer")
                }
                TextField("Titre de la réunion", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.mtSerif(34))
                    .focused($titleFocused)
                    .onSubmit(commitTitle)
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
                    .onChange(of: session.meetingID, initial: true) { loadDraft() }
                    .onChange(of: session.currentMeeting?.title) { _, title in
                        if !titleFocused { titleDraft = title ?? "" }
                    }
                    .onDisappear(perform: commitTitle)
                    .help("Clique pour renommer la réunion")
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
        .meetingDeletion($deleting, session: session)
    }
}
