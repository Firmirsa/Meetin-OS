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
        if !notebookIsOpen { openWindow(id: "notebook") }
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("notebook") == true }?.makeKeyAndOrderFront(nil)
    }

    func setCallDetection(_ enabled: Bool, openWindow: OpenWindowAction) {
        guard enabled else {
            callMonitor?.cancel()
            callMonitor = nil
            callAccessibility = nil
            for arrival in callDetector.arrivals { TaskNotifications.shared.removeMeetingArrival(arrival.id) }
            callDetector = MeetingDetector()
            return
        }
        guard callMonitor == nil else { return }
        LiveAlerts.requestPermission()
        let accessibility = MeetingAccessibility()
        callAccessibility = accessibility
        callMonitor = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                let trackedRoom = self?.callDetector.current(.meet)?.key
                let presence = await accessibility.readAll(trackedMeet: trackedRoom)
                guard !Task.isCancelled else { break }
                self?.observeCalls(presence, openWindow: openWindow)
                do { try await Task.sleep(for: .seconds(2)) }
                catch { break }
            }
            await accessibility.stop()
        }
    }

    private func observeCalls(_ presence: [MeetingSource: MeetingPresence], openWindow: OpenWindowAction) {
        for source in MeetingSource.allCases {
            let change = callDetector.observe(presence[source] ?? .unknown, for: source)
            if let left = change.left { TaskNotifications.shared.removeMeetingArrival(left.id) }
            if let joined = change.joined {
                openWindow(id: "meeting")
                if capture == nil { TaskNotifications.shared.postMeetingArrival(joined) }
            }
        }
    }

    func handleMeetingArrivalNotification(id: UUID, start: Bool) async {
        guard accountConnected, let openWindowAction, let accessibility = callAccessibility,
              let arrival = callDetector.arrivals.first(where: { $0.id == id }) else { return }
        let presence = await accessibility.read(arrival.source, trackedKey: arrival.key)
        guard accountConnected, callDetector.accepts(arrival, presence: presence) else { return }
        NSApp.activate()
        openWindowAction(id: "meeting")
        if start, capture == nil {
            CaptureView.toggleRecording(session: self, openWindow: openWindowAction, source: arrival.source)
        }
    }

    static let liveTranscriptionKey = "liveTranscription"

    var liveTranscriptionEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.liveTranscriptionKey) as? Bool ?? true
    }

    var accountClient: AccountClient? {
        let address = UserDefaults.standard.string(forKey: "webWorkspaceURL") ?? MeetinSite.defaultAddress
        return MeetinSite.baseURL(address).map { AccountClient(baseURL: $0) }
    }

    var accountConnected: Bool { account.connected(to: accountClient?.baseURL) }

    var liveWaitingMessage: String {
        if liveTranscriptionEnabled, !accountConnected {
            return "Connecte-toi à Meetin-OS pour transcrire. L’enregistrement continue sur ce Mac."
        }
        return "La transcription sera disponible après l’arrêt de l’enregistrement et l’envoi à Gladia."
    }

    var pendingProposalCount: Int { proposals.filter { $0.state == .pending }.count }

    // Détection seulement si le direct tourne et si l'équipe a validé l'accès à l'agent.
    func startDetection(reading live: LiveTranscription) {
        guard let client = agentClient else { return }
        let transcript = live.transcript
        LiveAlerts.requestPermission()
        let detector = TaskDetector(text: { transcript.confirmedText }) { [weak self] text, known in
            guard let self else { throw CancellationError() }
            let revision = self.captureRevision
            let result = try await client.detect(transcript: text, known: known)
            guard self.captureRevision == revision else { throw CancellationError() }
            return result
        }
        detector.onNewProposal = { [weak self, weak detector] proposal in
            guard let self, self.detector === detector else { return }
            let task = TaskProposal(id: proposal.id, review: proposal.review)
            self.proposals.append(task)
            TaskNotifications.shared.post(task)
        }
        detector.onUpdatedProposal = { [weak self, weak detector] proposal in
            guard let self, self.detector === detector,
                  !self.launchingProposals.contains(proposal.id),
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
        guard let client = accountClient, accountConnected else { return nil }
        return AgentClient(baseURL: client.baseURL) { [account] in
            try await account.token(client)
        }
    }

    // Seul un clic lance une tâche : sur la carte ou dans sa notification.
    // Avec un contexte, Holo réécrit le plan et il part sans nouvelle relecture : choix produit, signalé dans le guide Mac.
    func launch(_ proposal: TaskProposal, using client: AgentClient, context: String? = nil, notify: Bool = false) {
        guard !launchingProposals.contains(proposal.id), proposal.state == .pending else { return }
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
                    }
                }
                let execution = try await client.launch(review)
                guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
                proposals[index].state = .launched
                proposals[index].sessionURL = execution.url
                proposals[index].execution = execution
                TaskNotifications.shared.remove(proposal.id)
                if notify { LiveAlerts.postTask("Tâche lancée", "\(review.title) · \(execution.executor.name)") }
            } catch {
                reportTaskIssue(proposal, error.localizedDescription, notify: notify)
            }
        }
    }

    func saveTrelloResult(_ result: TrelloExecutionResult, for id: String, trackingToken: String?) {
        guard let trackingToken, let index = proposals.firstIndex(where: { $0.id == id }),
              proposals[index].execution?.trackingToken == trackingToken else { return }
        proposals[index].execution?.trelloResult = result
    }

    private func reportTaskIssue(_ proposal: TaskProposal, _ message: String, notify: Bool) {
        proposalIssues[proposal.id] = message
        if notify { LiveAlerts.postTask("Vérifier le lancement : \(proposal.review.title)", message) }
    }

    // Réponse à une notification de tâche. Sans lancement possible, ouvre la carte concernée.
    func handleTaskNotification(id: String, shownApproval: String?, confirm: Bool, context: String?) {
        guard accountConnected else { return }
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

    func pauseCapture() async {
        guard !busy, captureState == .recording, let capture else { return }
        busy = true
        defer { busy = false }
        captureRevision += 1
        detector?.stop()
        capturePaused = true
        recordingLevel.stop()
        status = "Enregistrement en pause"
        do { try capture.pause() }
        catch { status = "Enregistrement en pause. \(error.localizedDescription)" }
        await finishCaptureSegment()
    }

    func resumeCapture() async {
        guard !busy, captureState == .paused, let capture else { return }
        busy = true
        defer { busy = false }
        let nextSegment = captureSegment + 1
        let next = makeLive(transcript: live?.transcript, segment: nextSegment, startTime: capture.activeDuration)
        let meter = audioLevelMeter
        let listener: (AudioTrack, AVAudioPCMBuffer, UInt64) -> Void = { track, buffer, time in
            meter.feed(buffer)
            next?.feed(track, buffer, hostTime: time)
        }
        do {
            try capture.resume(onAudio: listener)
            capturePaused = false
            recordingLevel.start(reading: audioLevelMeter, since: Date())
            captureSegment = nextSegment
            if let next {
                live = next
                next.start()
                if let detector { detector.start() }
                else { startDetection(reading: next) }
            } else if live != nil {
                transcriptIncomplete = true
            }
            status = "Enregistrement en cours"
        } catch let help as AudioPermissionHelp {
            permissionHelp = help
            status = "Enregistrement en pause. \(help.localizedDescription)"
        } catch {
            status = "Enregistrement en pause. \(error.localizedDescription)"
        }
    }

    func makeLive(transcript: LiveTranscript? = nil, segment: Int = 0, startTime: Double = 0) -> LiveTranscription? {
        guard liveTranscriptionEnabled, let client = accountClient, accountConnected else { return nil }
        LiveAlerts.requestPermission()
        let live = LiveTranscription(transcript: transcript, segment: segment, startTime: startTime, openSocket: { [account] in
            let usage = try await account.refreshUsage(client)
            guard usage.remainingMs > 0 else {
                throw CaptureError("Ton quota audio est atteint. Consulte ton plan dans Compte.")
            }
            guard let url = usage.liveUrl, url.host == client.baseURL.host, url.user == nil,
                  url.password == nil, url.query == nil, url.fragment == nil,
                  url.scheme == "wss" || (url.scheme == "ws" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) else {
                throw CaptureError("Le direct n’est pas disponible sur ce serveur.")
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await account.token(client))", forHTTPHeaderField: "Authorization")
            return URLSessionLiveSocket(request: request)
        })
        live.onProblem = { LiveAlerts.post($0) }
        return live
    }

    func finishCaptureSegment() async {
        guard let live else { return }
        await live.finish()
        if live.isIncomplete { transcriptIncomplete = true }
    }

    // Le texte du direct devient la transcription, avant l'ajout de la réunion à l'historique.
    func finishLive() async {
        guard let live else { return }
        status = "Finalisation de la transcription…"
        await finishCaptureSegment()
        structuredLines = live.transcript.lines.map(\.structured)
        let text = participants?.render(structuredLines ?? []) ?? live.transcript.finalText
        if !text.isEmpty { transcript = text }
        self.live = nil
        finishDetection()
    }

    func meetingDidStart(source: MeetingSource?) {
        capturePaused = false
        captureSegment = 0
        captureRevision += 1
        if meetingID != nil {
            meetingID = nil
            notes = ""
        }
        structuredLines = nil
        participants = .newMeeting(localName: account.profileName(for: accountClient?.baseURL) ?? AudioTrack.microphone.label)
        startedAt = Date()
        recordingSource = source ?? callDetector.arrivals.first?.source
        for arrival in callDetector.arrivals { TaskNotifications.shared.removeMeetingArrival(arrival.id) }
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
            title: Self.defaultTitle(started, source: recordingSource),
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
            source: recordingSource?.rawValue,
            transcriptIncomplete: transcriptIncomplete ? true : nil,
            proposals: proposals.isEmpty ? nil : proposals,
            participants: participants,
            structuredLines: structuredLines
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
            $0.participants = participants
            $0.structuredLines = structuredLines
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
        structuredLines = nil
        participants = record.participants
        structuredLines = record.structuredLines
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

    // Renvoie false si le titre est vide : l'ancien titre reste affiché.
    @discardableResult
    func renameMeeting(_ id: UUID, to title: String) -> Bool {
        let renamed = store.rename(id, to: title)
        reportStoreError()
        return renamed
    }

    // Pendant un enregistrement, une transcription ou une action de l'agent, aucune réunion n'est supprimée.
    var canDeleteMeetings: Bool { canSwitchMeeting }

    func deleteMeeting(_ id: UUID) {
        guard canDeleteMeetings, let record = store.meeting(id: id) else { return }
        guard store.delete(id) else {
            reportStoreError()
            return
        }
        record.proposals?.forEach { TaskNotifications.shared.remove($0.id) }
        if meetingID == id { closeMeeting() }
        reportStoreError()
    }

    // Vide le carnet après la suppression de la réunion ouverte et revient à la liste.
    private func closeMeeting() {
        meetingID = nil
        recording = nil
        recordedTracks = nil
        transcript = ""
        notes = ""
        transcriptIncomplete = false
        detector = nil
        proposals = []
        proposalIssues = [:]
        agent.newRecording()
        permissionHelp = nil
        status = "Prêt à enregistrer"
        statusBelongsToMeeting = false
        if route == .meetingDetail { route = .meetings }
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

    private static func defaultTitle(_ date: Date, source: MeetingSource?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM 'à' HH:mm"
        let title = source.map { $0 == .whatsapp ? "Appel WhatsApp" : "Réunion \($0.rawValue)" } ?? "Réunion"
        return "\(title) du \(formatter.string(from: date))"
    }
}
