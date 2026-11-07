import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Liens entre la session en cours, l'historique local et la fenêtre principale.
extension MeetingSession {
    static let systemAudioStateKey = "systemAudioState"

    var currentMeeting: MeetingRecord? { store.meeting(id: meetingID) }
    var canSwitchMeeting: Bool { capture == nil && !busy && !agent.busy }

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

    var pendingProposalCount: Int { proposals.filter { $0.state == .pending }.count }

    // Détection seulement si le direct tourne et si l'équipe a validé l'accès à l'agent.
    func startDetection(reading live: LiveTranscription) {
        let address = UserDefaults.standard.string(forKey: "webWorkspaceURL") ?? "http://localhost:3000"
        guard agentAccess?.planning == true, let base = AgentClient.serverURL(address) else { return }
        let client = AgentClient(baseURL: base, accessCode: agentAccessCode)
        let transcript = live.transcript
        let detector = TaskDetector(text: { transcript.confirmedText }) { text, known in
            try await client.detect(transcript: text, known: known)
        }
        detector.onNewProposal = { [weak self, weak detector] proposal in
            guard let self, self.detector === detector else { return }
            self.proposals.append(TaskProposal(id: proposal.id, review: proposal.review))
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
    }

    // Reprend la tâche dans le formulaire de l'agent, pour la modifier ou préparer un nouveau plan.
    func edit(_ proposal: TaskProposal) {
        guard !agent.busy else { return }
        agent.newRecording()
        agent.request = proposal.review.task
        agent.excerpt = proposal.review.quote
        ignore(proposal)
    }

    // Validation explicite : seul ce clic lance le plan signé.
    func launch(_ proposal: TaskProposal, using client: AgentClient) {
        guard launchingProposal == nil, proposal.state == .pending else { return }
        launchingProposal = proposal.id
        proposalIssues[proposal.id] = nil
        Task {
            defer { launchingProposal = nil }
            do {
                let execution = try await client.launch(proposal.review)
                guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
                proposals[index].state = .launched
                proposals[index].sessionURL = execution.url
            } catch {
                proposalIssues[proposal.id] = error.localizedDescription
            }
        }
    }

    func makeLive() -> LiveTranscription? {
        guard liveTranscriptionEnabled, !trimmedKey.isEmpty else { return nil }
        LiveAlerts.requestPermission()
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

    func meetingDidStop() async {
        guard let mix = recording else { return }
        let id = UUID()
        let started = startedAt ?? Date()
        var audio = mix
        var tracks = recordedTracks
        do {
            let folder = try store.adoptRecording(from: mix.deletingLastPathComponent(), id: id)
            audio = folder.appendingPathComponent(mix.lastPathComponent)
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

        let duration = await Self.audioDuration(audio) ?? Date().timeIntervalSince(started)
        store.add(MeetingRecord(
            id: id,
            title: Self.defaultTitle(started, zoom: startedInZoom),
            date: started,
            duration: duration,
            audioPath: audio.path,
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

    // Une transcription relancée vide le texte affiché : la version enregistrée reste jusqu'au résultat.
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
        case .microphone, nil: break
        }
    }

    func open(_ record: MeetingRecord) {
        guard canSwitchMeeting else { return }
        meetingID = nil
        recording = URL(fileURLWithPath: record.audioPath)
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
        status = FileManager.default.fileExists(atPath: record.audioPath)
            ? (record.transcript.isEmpty ? "Enregistrement prêt" : "Transcription prête")
            : "Fichier audio introuvable : \(record.audioPath)"
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
