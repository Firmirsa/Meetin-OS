import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Liens entre la session en cours, l'historique local et la fenêtre principale.
extension MeetingSession {
    static let systemAudioStateKey = "systemAudioState"

    var currentMeeting: MeetingRecord? { store.meeting(id: meetingID) }
    var canSwitchMeeting: Bool { capture == nil && !busy && !agent.busy && launchingProposals.isEmpty }

    func showMain(_ target: MainRoute, openWindow: OpenWindowAction) {
        route = target
        if notebookCount == 0 { openWindow(id: "notebook") }
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("notebook") == true }?.makeKeyAndOrderFront(nil)
    }

    static let liveTranscriptionKey = "liveTranscription"

    var liveTranscriptionEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.liveTranscriptionKey) as? Bool ?? true
    }

    var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var liveWaitingMessage: String {
        if liveTranscriptionEnabled, trimmedKey.isEmpty {
            return "Ajoute une clé Gladia dans Paramètres pour le direct. L’enregistrement continue."
        }
        return "La transcription sera disponible après l’arrêt de l’enregistrement et l’envoi à Gladia."
    }

    var pendingProposalCount: Int { proposals.filter(\.isPending).count }

    func refreshNotificationPermission(request: Bool = false) {
        let update: @MainActor @Sendable (Bool) -> Void = { [weak self] denied in
            self?.notificationsDenied = denied
        }
        if request { LiveAlerts.requestPermission(onStatus: update) }
        else { LiveAlerts.readPermission(update) }
    }

    // Détection seulement si le direct tourne et si l'équipe a validé l'accès à l'agent.
    func startDetection(reading live: LiveTranscription) {
        let address = UserDefaults.standard.string(forKey: "webWorkspaceURL") ?? MeetinSite.defaultAddress
        guard agentAccess?.planning == true, let base = AgentClient.serverURL(address) else { return }
        let client = AgentClient(baseURL: base, accessCode: agentAccessCode)
        let transcript = live.transcript
        refreshNotificationPermission(request: true)
        let existing = proposals.map { TaskDetector.Proposal(id: $0.id, review: $0.review) }
        let detector = TaskDetector(known: existing, text: { transcript.confirmedText }) { text, known in
            try await client.detect(transcript: text, known: known)
        }
        detector.onNewProposal = { [weak self, weak detector] proposal in
            guard let self, self.detector === detector else { return }
            let task = TaskProposal(id: proposal.id, review: proposal.review)
            self.proposals.append(task)
            TaskNotifications.shared.post(task)
        }
        detector.onUpdatedProposal = { [weak self, weak detector] proposal in
            guard let self, self.detector === detector,
                  let index = self.proposals.firstIndex(where: { $0.id == proposal.id }),
                  self.proposals[index].state == .pending else { return }
            self.proposals[index].review = proposal.review
            self.proposalIssues[proposal.id] = nil
        }
        self.detector = detector
        detector.start()
    }

    // Agent connecté pendant l'enregistrement : la détection démarre ou reprend, sans recréer les cartes déjà là.
    func resumeDetectionIfNeeded() {
        guard capture != nil, let live, detector == nil || detector?.isStopped == true else { return }
        detector?.stop()
        startDetection(reading: live)
    }

    // Le dernier passage se termine après l'ajout de la réunion : ses résultats y sont enregistrés.
    private func finishDetection() {
        guard let detector else { return }
        detector.stop()
        Task {
            await detector.finish()
            if self.detector === detector { self.detector = nil }
        }
    }

    func ignore(_ proposal: TaskProposal) {
        guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        proposals[index].state = .ignored
        proposalIssues[proposal.id] = nil
        TaskNotifications.shared.remove(proposal.id)
    }

    // Reprend la tâche dans le formulaire de l'agent, pour la modifier ou préparer un nouveau plan.
    func edit(_ proposal: TaskProposal) {
        guard !agent.busy else { return }
        agent.newRecording()
        agent.request = proposal.review.task
        agent.excerpt = proposal.review.quote
        ignore(proposal)
    }

    var agentClient: AgentClient? {
        let address = UserDefaults.standard.string(forKey: "webWorkspaceURL") ?? MeetinSite.defaultAddress
        guard agentAccess != nil, let base = AgentClient.serverURL(address) else { return nil }
        return AgentClient(baseURL: base, accessCode: agentAccessCode)
    }

    // Seul un clic lance une tâche : sur la carte ou dans sa notification.
    // Avec un contexte, Holo réécrit le plan et il part sans nouvelle relecture : choix produit, signalé dans le guide Mac.
    func launch(_ proposal: TaskProposal, using client: AgentClient, context: String? = nil, notify: Bool = false) {
        guard !busy, !launchingProposals.contains(proposal.id), proposal.state == .pending else { return }
        launchingProposals.insert(proposal.id)
        proposalIssues[proposal.id] = nil
        Task {
            defer { launchingProposals.remove(proposal.id) }
            do {
                var review = proposal.review
                if let context {
                    switch try await TaskActions.rewrite(review, context: context, prepare: { task, quote, turns in
                        try await client.prepare(task: task, transcript: quote, clarifications: turns)
                    }) {
                    case .question(let question):
                        reportTaskIssue(proposal, "Holo demande une précision : \(question)", notify: notify)
                        return
                    case .review(let updated):
                        review = updated
                        if let index = proposals.firstIndex(where: { $0.id == proposal.id }) { proposals[index].review = updated }
                        if updated.executor != proposal.review.executor || updated.destination != proposal.review.destination {
                            reportTaskIssue(proposal, "L’outil ou la destination a changé. Relis la tâche avant de confirmer.", notify: notify)
                            return
                        }
                    }
                }
                let execution = try await client.launch(review)
                guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
                proposals[index].review = review
                proposals[index].state = .launched
                proposals[index].sessionURL = execution.url
                TaskNotifications.shared.remove(proposal.id)
                if notify { LiveAlerts.postTask("Tâche lancée", "\(review.title) · \(execution.executor.name)") }
            } catch {
                reportTaskIssue(proposal, error.localizedDescription, notify: notify)
            }
        }
    }

    private func reportTaskIssue(_ proposal: TaskProposal, _ message: String, notify: Bool) {
        proposalIssues[proposal.id] = message
        if notify { LiveAlerts.postTask("Tâche non lancée : \(proposal.review.title)", message) }
    }

    // Réponse à une notification de tâche. Sans lancement possible, ouvre la carte concernée.
    func handleTaskNotification(id: String, shownApproval: String?, confirm: Bool, context: String?) {
        if !proposals.contains(where: { $0.id == id }),
           let record = store.meetings.first(where: { $0.proposals?.contains { $0.id == id } == true }) {
            open(record)
        }
        guard let proposal = proposals.first(where: { $0.id == id }) else {
            showTaskCard()
            return
        }
        guard confirm else {
            showTaskCard()
            return
        }
        switch TaskActions.decide(
            state: proposal.state, currentApproval: proposal.review.approval,
            shownApproval: shownApproval, hasClient: agentClient != nil
        ) {
        case .launch:
            if let agentClient { launch(proposal, using: agentClient, context: context, notify: true) }
        case .stale:
            proposalIssues[id] = "Cette tâche a changé depuis la notification. Relis-la avant de confirmer."
            showTaskCard()
        case .needsAccess:
            proposalIssues[id] = "Connecte l’agent pour lancer cette tâche."
            showTaskCard()
        case .alreadyHandled:
            showTaskCard()
        }
    }

    private func showTaskCard() {
        showAgentTab = true
        guard let openWindowAction else {
            NSApp.activate()
            return
        }
        if capture != nil {
            openWindowAction(id: "meeting")
            NSApp.activate()
        } else {
            showMain(recording != nil ? .meetingDetail : .meetings, openWindow: openWindowAction)
        }
    }

    func makeLive() -> LiveTranscription? {
        guard liveTranscriptionEnabled, !trimmedKey.isEmpty else { return nil }
        refreshNotificationPermission(request: true)
        let live = LiveTranscription(key: trimmedKey)
        live.onProblem = { LiveAlerts.post($0) }
        return live
    }

    // Le texte du direct devient la transcription, avant l'ajout de la réunion à l'historique.
    func finishLive() async {
        guard let live else { return }
        status = "Finalisation de la transcription…"
        await live.finish()
        let text = live.transcript.finalText
        if !text.isEmpty {
            transcript = text
            transcriptIncomplete = live.isIncomplete
        }
        self.live = nil
        finishDetection()
    }

    func meetingDidStart() {
        if meetingID != nil {
            meetingID = nil
            notes = ""
        }
        startedAt = Date()
        startedInZoom = zoomDetector.inMeeting
        transcriptIncomplete = false
        detector = nil
        proposals = []
        proposalIssues = [:]
        route = .home
    }

    func meetingDidStop(recoveryFolder: URL? = nil) async {
        guard let source = recoveryFolder ?? recording?.deletingLastPathComponent() else { return }
        let id = UUID()
        let started = startedAt ?? Date()
        var audio = recording
        var tracks = recordedTracks
        do {
            let folder = try store.adoptRecording(from: source, id: id)
            audio = audio.map { folder.appendingPathComponent($0.lastPathComponent) }
            if let current = tracks {
                tracks = AudioCapture.Tracks(
                    microphone: folder.appendingPathComponent(current.microphone.lastPathComponent),
                    system: folder.appendingPathComponent(current.system.lastPathComponent),
                    microphoneOffset: current.microphoneOffset,
                    systemOffset: current.systemOffset
                )
            }
            recording = audio
            recordedTracks = tracks
        } catch {
            status += " · Audio resté dans le dossier temporaire : \(error.localizedDescription)"
        }
        if tracks != nil { UserDefaults.standard.set("ok", forKey: Self.systemAudioStateKey) }

        let audioLength: TimeInterval?
        if let audio { audioLength = await Self.audioDuration(audio) } else { audioLength = nil }
        let duration = audioLength ?? Date().timeIntervalSince(started)
        store.add(MeetingRecord(
            id: id,
            title: Self.defaultTitle(started, zoom: startedInZoom),
            date: started,
            duration: duration,
            audioPath: audio?.path ?? "",
            transcript: transcript,
            notes: notes,
            tracks: tracks.map {
                .init(
                    microphonePath: $0.microphone.path, systemPath: $0.system.path,
                    microphoneOffset: $0.microphoneOffset, systemOffset: $0.systemOffset
                )
            },
            source: startedInZoom ? "Zoom" : nil,
            transcriptIncomplete: transcriptIncomplete ? true : nil,
            proposals: proposals.isEmpty ? nil : proposals
        ))
        meetingID = id
        startedAt = nil
        statusBelongsToMeeting = true
        route = .meetingDetail
        reportStoreError()
    }

    // Un texte vide ne remplace jamais la transcription enregistrée.
    func syncMeeting() {
        guard let meetingID else { return }
        store.update(meetingID) {
            if !transcript.isEmpty { $0.transcript = transcript }
            $0.notes = notes
            $0.transcriptIncomplete = transcriptIncomplete ? true : nil
            $0.proposals = proposals.isEmpty ? nil : proposals
        }
    }

    func noteSystemAudioPermission() {
        switch permissionHelp {
        case .systemAudio: UserDefaults.standard.set("denied", forKey: Self.systemAudioStateKey)
        case .systemAudioSilent: UserDefaults.standard.set("silent", forKey: Self.systemAudioStateKey)
        case .systemAudioTimeout: UserDefaults.standard.removeObject(forKey: Self.systemAudioStateKey)
        case .microphone, nil: break
        }
    }

    func open(_ record: MeetingRecord) {
        guard canSwitchMeeting else { return }
        meetingID = nil
        recording = record.audioPath.isEmpty ? nil : URL(fileURLWithPath: record.audioPath)
        recordedTracks = record.tracks.map {
            AudioCapture.Tracks(
                microphone: URL(fileURLWithPath: $0.microphonePath),
                system: URL(fileURLWithPath: $0.systemPath),
                microphoneOffset: $0.microphoneOffset,
                systemOffset: $0.systemOffset
            )
        }
        transcript = record.transcript
        notes = record.notes
        transcriptIncomplete = record.transcriptIncomplete == true
        detector = nil
        proposals = record.proposals ?? []
        proposalIssues = [:]
        agent.newRecording()
        permissionHelp = nil
        if record.audioPath.isEmpty {
            status = "Réunion conservée sans audio exploitable : les notes et le texte restent disponibles."
        } else {
            status = FileManager.default.fileExists(atPath: record.audioPath)
                ? (record.transcript.isEmpty ? "Enregistrement prêt" : "Transcription prête")
                : "Fichier audio introuvable : \(record.audioPath)"
        }
        meetingID = record.id
        statusBelongsToMeeting = true
        route = .meetingDetail
    }

    func importRecording() {
        guard canSwitchMeeting else { return }
        busy = true
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.mpeg4Audio]
        picker.message = "Choisissez un fichier M4A à écouter ou à transcrire."
        picker.begin { [self] response in
            busy = false
            guard response == .OK, let file = picker.url else { return }
            Task { await self.addImportedRecording(file) }
        }
    }

    private func addImportedRecording(_ file: URL) async {
        let duration = await Self.audioDuration(file) ?? 0
        let record = MeetingRecord(
            id: UUID(),
            title: file.deletingPathExtension().lastPathComponent,
            date: Date(),
            duration: duration,
            audioPath: file.path,
            transcript: "",
            notes: "",
            tracks: nil,
            source: nil,
            transcriptIncomplete: nil,
            proposals: nil
        )
        store.add(record)
        open(record)
        if capture == nil, currentMeeting?.id == record.id { status = "Fichier audio prêt" }
        reportStoreError()
    }

    private func reportStoreError() {
        if let error = store.lastError { status = error }
    }

    private static func audioDuration(_ url: URL) async -> TimeInterval? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration), duration.seconds.isFinite else { return nil }
        return duration.seconds
    }

    private static func defaultTitle(_ date: Date, zoom: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM 'à' HH:mm"
        return "\(zoom ? "Réunion Zoom" : "Réunion") du \(formatter.string(from: date))"
    }
}
