import AVFoundation
import Foundation

// Transcription en direct : flux parallèle à l'enregistrement.
// Une panne ici ne touche jamais les fichiers audio, et « Transcrire » reste disponible.

// MARK: - Conversion audio

// PCM 16 kHz, mono, 16 bits, le format annoncé à Gladia.
final class LiveAudioConverter {
    static let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private var converter: AVAudioConverter?
    private var input: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else { return nil }
        if input != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.output)
            converter?.downmix = true
            input = buffer.format
        }
        guard let converter else { return nil }
        let ratio = Self.output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1_024
        guard let result = AVAudioPCMBuffer(pcmFormat: Self.output, frameCapacity: capacity) else { return nil }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: result, error: &failure) { _, state in
            if supplied {
                state.pointee = .noDataNow
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, failure == nil, result.frameLength > 0, let samples = result.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(result.frameLength) * MemoryLayout<Int16>.size)
    }

    // Le tampon de l'audio système n'est valable que pendant l'appel : on le copie avant de changer de file.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == target.count else { return nil }
        for index in source.indices {
            guard let from = source[index].mData, let to = target[index].mData else { return nil }
            let size = min(source[index].mDataByteSize, target[index].mDataByteSize)
            memcpy(to, from, Int(size))
            target[index].mDataByteSize = size
        }
        return copy
    }
}

// Reçoit l'audio d'une piste, le convertit sur sa propre file et le regroupe par tranches de 100 ms.
final class LiveAudioPipe: @unchecked Sendable {
    // 600 tranches de 100 ms : au-delà de 60 s de coupure, le plus ancien est abandonné.
    static let maxChunks = 600
    private static let chunkBytes = 3_200

    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let queue = DispatchQueue(label: "MeetinOS.live.audio")
    private let converter = LiveAudioConverter()
    private var pending = Data()
    private var sawFirstBuffer = false
    private let onFirstBuffer: @Sendable (Double) -> Void
    private let onDrop: @Sendable () -> Void

    init(onFirstBuffer: @escaping @Sendable (Double) -> Void, onDrop: @escaping @Sendable () -> Void) {
        (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(Self.maxChunks))
        self.onFirstBuffer = onFirstBuffer
        self.onDrop = onDrop
    }

    func feed(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard let copy = LiveAudioConverter.copy(buffer) else { return }
        let seconds = AVAudioTime.seconds(forHostTime: hostTime)
        queue.async { [self] in
            if !sawFirstBuffer {
                sawFirstBuffer = true
                onFirstBuffer(seconds)
            }
            guard let data = converter.convert(copy) else { return }
            pending.append(data)
            guard pending.count >= Self.chunkBytes else { return }
            yield(pending)
            pending = Data()
        }
    }

    func finish() {
        queue.sync {
            if !pending.isEmpty { yield(pending) }
            pending = Data()
            continuation.finish()
        }
    }

    private func yield(_ data: Data) {
        if case .dropped = continuation.yield(data) { onDrop() }
    }
}

// MARK: - Connexion

protocol LiveSocket: AnyObject, Sendable {
    func send(_ data: Data) async throws
    func send(text: String) async throws
    // nil : fermeture normale par le serveur.
    func receive() async throws -> String?
    func close()
}

final class URLSessionLiveSocket: LiveSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = AccountClient.http) {
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func send(_ data: Data) async throws { try await task.send(.data(data)) }
    func send(text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> String? {
        do {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(data: data, encoding: .utf8) ?? ""
            @unknown default: return ""
            }
        } catch {
            if task.closeCode == .normalClosure { return nil }
            throw error
        }
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }
}

enum GladiaLive {
    struct Transcript: Equatable {
        let id: String
        let text: String
        let start: Double
        let isFinal: Bool
    }

    private struct Envelope: Decodable { let type: String }
    private struct Message: Decodable {
        struct Details: Decodable {
            struct Utterance: Decodable {
                let text: String
                let start: Double
            }
            let id: String
            let is_final: Bool
            let utterance: Utterance
        }
        let data: Details
    }

    static func parse(_ text: String) -> Transcript? {
        let data = Data(text.utf8)
        guard (try? JSONDecoder().decode(Envelope.self, from: data))?.type == "transcript",
              let message = try? JSONDecoder().decode(Message.self, from: data) else { return nil }
        return Transcript(
            id: message.data.id, text: message.data.utterance.text,
            start: message.data.utterance.start, isFinal: message.data.is_final
        )
    }
}

// Une session Gladia par piste : une piste en panne n'arrête pas l'autre.
actor GladiaLiveSession {
    enum Event {
        case connected
        case reconnecting
        case unauthorized
        case failed(String)
        case ended
        case transcript(GladiaLive.Transcript)
        case finished
    }

    private let openSocket: @Sendable () async throws -> LiveSocket
    private let audio: AsyncStream<Data>
    private let events: @MainActor @Sendable (Event) -> Void
    private let retryDelay: Double
    private var socket: LiveSocket?
    private var aborted = false
    private var serverClosed = false
    private var relayStopped = false

    init(
        audio: AsyncStream<Data>,
        retryDelay: Double = 1,
        openSocket: @escaping @Sendable () async throws -> LiveSocket,
        events: @escaping @MainActor @Sendable (Event) -> Void
    ) {
        self.audio = audio
        self.retryDelay = retryDelay
        self.openSocket = openSocket
        self.events = events
    }

    func abort() {
        aborted = true
        socket?.close()
    }

    func run() async {
        await stream()
        await events(.finished)
    }

    private func stream() async {
        var iterator = audio.makeAsyncIterator()
        var unsent: Data?
        var delay = retryDelay
        var sentBytes = 0
        var connection = 0
        while !aborted, !Task.isCancelled {
            let current: LiveSocket
            do {
                current = try await openSocket()
            } catch let error as AccountClient.Failure where error.status == 401 {
                await events(.unauthorized)
                return
            } catch {
                await events(.failed(error.localizedDescription))
                return
            }
            if aborted || Task.isCancelled { current.close(); return }
            socket = current
            serverClosed = false
            relayStopped = false
            connection += 1
            let offset = Double(sentBytes) / 32_000
            let number = connection
            let receiver = Task { try await self.receiveAll(from: current, offset: offset, connection: number) }
            do {
                var announced = false
                if let chunk = unsent {
                    try await current.send(chunk)
                    sentBytes += chunk.count
                    unsent = nil
                    announced = true
                    await events(.connected)
                }
                while let chunk = await iterator.next() {
                    unsent = chunk
                    try await current.send(chunk)
                    sentBytes += chunk.count
                    unsent = nil
                    delay = retryDelay
                    if !announced {
                        announced = true
                        await events(.connected)
                    }
                }
                try await current.send(text: #"{"type":"stop_recording"}"#)
                try await receiver.value
                current.close()
                return
            } catch {
                current.close()
                _ = await receiver.result
                if aborted || Task.isCancelled { return }
                // Fermeture normale en plein appel, par exemple la limite de 3 h : pas de reprise possible.
                if serverClosed || relayStopped {
                    if !relayStopped { await events(.ended) }
                    return
                }
                await events(.reconnecting)
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 15)
            }
        }
    }

    private func receiveAll(from socket: LiveSocket, offset: Double, connection: Int) async throws {
        struct RelayMessage: Decodable { let type: String; let message: String? }
        while let text = try await socket.receive() {
            if let transcript = GladiaLive.parse(text) {
                await events(.transcript(.init(
                    id: "\(connection)-\(transcript.id)", text: transcript.text,
                    start: transcript.start + offset, isFinal: transcript.isFinal
                )))
            } else if let relay = try? JSONDecoder().decode(RelayMessage.self, from: Data(text.utf8)),
                      ["meetinos_limit", "meetinos_error"].contains(relay.type) {
                relayStopped = true
                await events(.failed(relay.message ?? "Le direct a été interrompu."))
            }
        }
        serverClosed = true
    }
}

// MARK: - Texte

@MainActor
@Observable
final class LiveTranscript {
    struct Line: Identifiable, Equatable {
        let id: String
        let time: Double
        let track: AudioTrack
        let text: String
        let isFinal: Bool

        var formatted: String { Gladia.line(at: time, label: track.label, text: text) }
    }

    private struct Key: Hashable {
        let track: AudioTrack
        let id: String
    }

    private var utterances: [Key: GladiaLive.Transcript] = [:]
    private var firstAudio: [AudioTrack: Double] = [:]

    func noteFirstAudio(_ track: AudioTrack, at seconds: Double) {
        if firstAudio[track] == nil { firstAudio[track] = seconds }
    }

    func apply(_ transcript: GladiaLive.Transcript, track: AudioTrack) {
        let key = Key(track: track, id: transcript.id)
        if transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            utterances[key] = nil
        } else {
            utterances[key] = transcript
        }
    }

    private func offset(_ track: AudioTrack) -> Double {
        guard let first = firstAudio[track], let origin = firstAudio.values.min() else { return 0 }
        return first - origin
    }

    var lines: [Line] {
        let all = utterances.map { key, value in
            Line(
                id: "\(key.track.rawValue)-\(key.id)", time: value.start + offset(key.track),
                track: key.track, text: value.text, isFinal: value.isFinal
            )
        }
        .sorted { ($0.time, $0.id) < ($1.time, $1.id) }
        let call = all.filter { $0.track == .system }
        return all.filter { !Self.isEcho($0, of: call) }
    }

    // Sans casque, le micro capte les haut-parleurs. La piste de l'appel, plus nette, garde la phrase.
    // Les réponses courtes restent : « Oui » ou « D'accord » ne prouvent pas un écho.
    private static let echoWindow = 10.0
    private static let echoMinWords = 3
    private static let echoOverlap = 0.7

    private static func isEcho(_ line: Line, of call: [Line]) -> Bool {
        guard line.track == .microphone else { return false }
        let words = Self.words(line.text)
        guard words.count >= echoMinWords else { return false }
        let heard = Set(call.filter { abs($0.time - line.time) <= echoWindow }.flatMap { Self.words($0.text) })
        guard !heard.isEmpty else { return false }
        return Double(words.filter(heard.contains).count) / Double(words.count) >= echoOverlap
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    // Texte définitif uniquement : c'est lui que lit la détection de tâches.
    var confirmedText: String { lines.filter(\.isFinal).map(\.formatted).joined(separator: "\n") }

    // Un texte encore provisoire à l'arrêt est gardé : mieux vaut lui que rien.
    var finalText: String { lines.map(\.formatted).joined(separator: "\n") }
}

// MARK: - Orchestration

@MainActor
@Observable
final class LiveTranscription {
    enum State: Equatable {
        case connecting, live, reconnecting, unauthorized, ended
        case failed(String)
    }

    let transcript = LiveTranscript()
    private(set) var state: State = .connecting
    private(set) var lostAudio = false
    // Vrai si le texte peut manquer une partie de l'appel : panne, audio perdu ou derniers textes non reçus.
    private(set) var isIncomplete = false
    // Appelé une fois par panne durable.
    @ObservationIgnored var onProblem: ((String) -> Void)?

    @ObservationIgnored private let openSocket: @Sendable () async throws -> LiveSocket
    @ObservationIgnored private let retryDelay: Double
    @ObservationIgnored private let finishTimeout: Double
    @ObservationIgnored private let outageAlertDelay: Double
    @ObservationIgnored private var outageAlert: Task<Void, Never>?
    @ObservationIgnored private var alerted = false
    @ObservationIgnored private var finishing = false
    @ObservationIgnored private var trackStates: [AudioTrack: State] = [:]
    @ObservationIgnored private var sessions: [GladiaLiveSession] = []
    @ObservationIgnored private var finishedCount = 0
    @ObservationIgnored nonisolated(unsafe) private var pipes: [AudioTrack: LiveAudioPipe] = [:]

    convenience init(
        retryDelay: Double = 1,
        finishTimeout: Double = 8,
        outageAlertDelay: Double = 30,
        createSession: @escaping @Sendable () async throws -> URL,
        connect: @escaping @Sendable (URL) -> LiveSocket
    ) {
        self.init(retryDelay: retryDelay, finishTimeout: finishTimeout, outageAlertDelay: outageAlertDelay,
                  openSocket: { connect(try await createSession()) })
    }

    init(
        retryDelay: Double = 1,
        finishTimeout: Double = 8,
        outageAlertDelay: Double = 30,
        openSocket: @escaping @Sendable () async throws -> LiveSocket
    ) {
        self.retryDelay = retryDelay
        self.finishTimeout = finishTimeout
        self.outageAlertDelay = outageAlertDelay
        self.openSocket = openSocket
        for track in AudioTrack.allCases {
            pipes[track] = LiveAudioPipe(
                onFirstBuffer: { [weak self] seconds in
                    Task { @MainActor in self?.transcript.noteFirstAudio(track, at: seconds) }
                },
                onDrop: { [weak self] in
                    Task { @MainActor in
                        self?.lostAudio = true
                        self?.isIncomplete = true
                    }
                }
            )
        }
    }

    // Appelé depuis les fils audio : copie le tampon et rend la main tout de suite.
    nonisolated func feed(_ track: AudioTrack, _ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        pipes[track]?.feed(buffer, hostTime: hostTime)
    }

    func start() {
        guard sessions.isEmpty else { return }
        for track in AudioTrack.allCases {
            guard let pipe = pipes[track] else { continue }
            let session = GladiaLiveSession(
                audio: pipe.stream, retryDelay: retryDelay, openSocket: openSocket
            ) { [weak self] event in
                self?.handle(event, track: track)
            }
            sessions.append(session)
            Task { await session.run() }
        }
    }

    // Envoie la fin de l'audio et attend les derniers textes, sans jamais dépasser le délai.
    func finish() async {
        finishing = true
        outageAlert?.cancel()
        for pipe in pipes.values { pipe.finish() }
        let deadline = Date().addingTimeInterval(finishTimeout)
        while finishedCount < sessions.count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if finishedCount < sessions.count { isIncomplete = true }
        for session in sessions { await session.abort() }
    }

    private func handle(_ event: GladiaLiveSession.Event, track: AudioTrack) {
        switch event {
        case .transcript(let value):
            transcript.apply(value, track: track)
        case .connected:
            update(.live, track: track)
        case .reconnecting:
            update(.reconnecting, track: track)
        case .unauthorized:
            update(.unauthorized, track: track)
        case .failed(let message):
            update(.failed(message), track: track)
        case .ended:
            update(.ended, track: track)
        case .finished:
            finishedCount += 1
        }
    }

    private func update(_ value: State, track: AudioTrack) {
        trackStates[track] = value
        let states = Array(trackStates.values)
        reportProblems(states)
        if states.contains(.unauthorized) {
            state = .unauthorized
        } else if states.contains(.reconnecting) {
            state = .reconnecting
        } else if states.contains(.live) {
            state = .live
        } else if states.contains(.ended) {
            state = .ended
        } else if let failure = states.first(where: { if case .failed = $0 { true } else { false } }) {
            state = failure
        }
    }

    private func reportProblems(_ states: [State]) {
        guard !finishing else { return }
        // Une piste définitivement perdue compte même si l'autre continue.
        if states.contains(.unauthorized) {
            isIncomplete = true
            alert("La connexion à Meetin-OS a expiré. L’enregistrement continue.")
        } else if let failure = states.compactMap({ state -> String? in
            if case .failed(let message) = state { return message }
            return nil
        }).first {
            isIncomplete = true
            alert("\(failure) L’enregistrement continue.")
        } else if states.contains(.ended) {
            isIncomplete = true
            alert("Le direct s’est arrêté. L’enregistrement continue.")
        } else if states.contains(.reconnecting) {
            guard outageAlert == nil else { return }
            let delay = outageAlertDelay
            outageAlert = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, !self.finishing else { return }
                self.isIncomplete = true
                self.alert("Le direct est coupé depuis \(Int(delay)) s. L’enregistrement continue.")
            }
        } else {
            // Tout est reparti : une prochaine panne pourra de nouveau prévenir.
            outageAlert?.cancel()
            outageAlert = nil
            alerted = false
        }
    }

    private func alert(_ message: String) {
        guard !alerted else { return }
        alerted = true
        onProblem?(message)
    }
}
