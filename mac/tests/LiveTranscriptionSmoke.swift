import AVFoundation
import Foundation

final class FakeSocket: LiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var failSends: Bool
    private var incoming: [String?]
    private var waiting: CheckedContinuation<String?, Error>?
    private(set) var sent = 0
    private(set) var stopped = false

    init(failSends: Bool = false, incoming: [String?] = []) {
        self.failSends = failSends
        self.incoming = incoming
    }

    func send(_ data: Data) async throws {
        if failSends { throw URLError(.networkConnectionLost) }
        lock.withLock { sent += 1 }
    }

    func send(text: String) async throws {
        if failSends { throw URLError(.networkConnectionLost) }
        lock.withLock { stopped = text.contains("stop_recording") }
        deliver(nil)
    }

    func deliver(_ message: String?) {
        let pending = lock.withLock { () -> CheckedContinuation<String?, Error>? in
            defer { waiting = nil }
            if waiting == nil { incoming.append(message) }
            return waiting
        }
        pending?.resume(returning: message)
    }

    func receive() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let ready = lock.withLock { () -> String?? in
                if incoming.isEmpty {
                    waiting = continuation
                    return .none
                }
                return .some(incoming.removeFirst())
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func close() {
        let pending = lock.withLock { () -> CheckedContinuation<String?, Error>? in
            defer { waiting = nil }
            return waiting
        }
        pending?.resume(throwing: URLError(.cancelled))
    }
}

func message(_ id: String, _ text: String, start: Double, final: Bool) -> String {
    #"{"type":"transcript","data":{"id":"\#(id)","is_final":\#(final),"utterance":{"text":"\#(text)","start":\#(start),"end":\#(start + 1),"channel":0}}}"#
}

func tone(rate: Double, channels: UInt32, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<Int(channels) {
        for frame in 0..<Int(frames) {
            buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.05) * 0.4
        }
    }
    return buffer
}

@MainActor
func waitUntil(_ label: String, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(5)
    while !condition() {
        precondition(Date() < deadline, "délai dépassé : \(label)")
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@main
struct LiveTranscriptionSmoke {
    @MainActor
    static func main() async {
        let url = URL(string: "wss://api.gladia.io/v2/live?token=fixture")!

        // Analyse des messages
        precondition(GladiaLive.parse(#"{"type":"speech_start"}"#) == nil)
        precondition(GladiaLive.parse("pas du json") == nil)
        let parsed = GladiaLive.parse(message("a", "Bonjour", start: 1.5, final: true))
        precondition(parsed == .init(id: "a", text: "Bonjour", start: 1.5, isFinal: true))

        // Provisoire remplacé par définitif, tri entre pistes avec décalage
        let text = LiveTranscript()
        text.noteFirstAudio(.microphone, at: 100)
        text.noteFirstAudio(.system, at: 102)
        text.apply(.init(id: "1", text: "Bonj", start: 1, isFinal: false), track: .microphone)
        precondition(text.lines.first?.isFinal == false)
        text.apply(.init(id: "1", text: "Bonjour", start: 1, isFinal: true), track: .microphone)
        text.apply(.init(id: "1", text: "Salut", start: 0, isFinal: true), track: .system)
        text.apply(.init(id: "2", text: "Ça va ?", start: 4, isFinal: true), track: .microphone)
        precondition(text.lines.count == 3, "même id sur deux pistes : deux énoncés")
        let expected = "[00:01] Micro · Bonjour\n[00:02] Audio de l’appel · Salut\n[00:04] Micro · Ça va ?"
        precondition(text.finalText == expected, text.finalText)

        // Écho du micro : la piste de l'appel garde la phrase, et les vraies répliques restent
        let echo = LiveTranscript()
        echo.noteFirstAudio(.microphone, at: 0)
        echo.noteFirstAudio(.system, at: 0)
        echo.apply(.init(id: "1", text: "Merci à tous, on se retrouve la semaine prochaine.", start: 19, isFinal: true), track: .system)
        echo.apply(.init(id: "1", text: "Merci à tous, on se retrouve la semaine prochaine.", start: 19, isFinal: true), track: .microphone)
        echo.apply(.init(id: "2", text: "Port des notes avant mardi.", start: 12, isFinal: true), track: .microphone)
        echo.apply(.init(id: "2", text: "Karim corrige l'export des notes avant mardi.", start: 11, isFinal: true), track: .system)
        echo.apply(.init(id: "3", text: "Oui, voilà.", start: 20, isFinal: true), track: .microphone)
        echo.apply(.init(id: "4", text: "Je pense plutôt envoyer le devis lundi.", start: 21, isFinal: true), track: .microphone)
        echo.apply(.init(id: "5", text: "Merci à tous, on se retrouve la semaine prochaine.", start: 60, isFinal: true), track: .microphone)
        let kept = echo.lines.filter { $0.track == .microphone }.map(\.text)
        precondition(kept == ["Oui, voilà.", "Je pense plutôt envoyer le devis lundi.", "Merci à tous, on se retrouve la semaine prochaine."], "\(kept)")
        precondition(echo.lines.filter { $0.track == .system }.count == 2, "piste de l'appel intacte")
        precondition(echo.confirmedText.contains("Oui, voilà.") && !echo.confirmedText.contains("Port des notes"))

        // Conversion 48 kHz stéréo vers 16 kHz mono, sur plusieurs tampons
        let converter = LiveAudioConverter()
        var total = 0
        for _ in 0..<10 {
            let data = converter.convert(tone(rate: 48_000, channels: 2, frames: 4_800))
            total += data?.count ?? 0
        }
        precondition(abs(total - 32_000) < 3_200, "1 s attendue en 16 kHz 16 bits : \(total)")
        precondition(LiveAudioConverter.copy(tone(rate: 44_100, channels: 1, frames: 128))?.frameLength == 128)

        // Parcours complet : les deux pistes envoient, reçoivent et se terminent
        let sockets = Mutex<[FakeSocket]>([])
        let full = LiveTranscription(createSession: { url }, connect: { _ in
            let socket = FakeSocket(incoming: [message("x", "Bonjour", start: 0, final: true)])
            sockets.withLock { $0.append(socket) }
            return socket
        })
        full.start()
        for track in AudioTrack.allCases {
            full.feed(track, tone(rate: 48_000, channels: 1, frames: 9_600), hostTime: mach_absolute_time())
        }
        await waitUntil("connexion") { full.state == .live }
        await full.finish()
        await waitUntil("transcription reçue") { full.transcript.lines.count == 2 }
        precondition(sockets.withLock { $0.count } == 2, "une session par piste")
        precondition(sockets.withLock { $0.allSatisfy { $0.stopped && $0.sent > 0 } }, "audio puis stop_recording")

        // Coupure puis reprise sur la même adresse
        let attempts = Mutex<[FakeSocket]>([])
        let urls = Mutex<[URL]>([])
        let flaky = LiveTranscription(retryDelay: 0.01, createSession: { url }, connect: { used in
            urls.withLock { $0.append(used) }
            let isFirst = attempts.withLock { $0.isEmpty }
            let socket = FakeSocket(failSends: isFirst)
            attempts.withLock { $0.append(socket) }
            return socket
        })
        flaky.start()
        flaky.feed(.microphone, tone(rate: 48_000, channels: 1, frames: 9_600), hostTime: mach_absolute_time())
        flaky.feed(.system, tone(rate: 48_000, channels: 1, frames: 9_600), hostTime: mach_absolute_time())
        await waitUntil("reprise") { attempts.withLock { $0.count } >= 3 }
        await flaky.finish()
        precondition(urls.withLock { $0.allSatisfy { $0 == url } })
        precondition(attempts.withLock { $0.contains { $0.sent > 0 } }, "tranche renvoyée après la reprise")

        // Serveur muet : finish() reste borné
        let silent = LiveTranscription(finishTimeout: 0.3, createSession: { url }, connect: { _ in HangingSocket() })
        silent.start()
        let started = Date()
        await silent.finish()
        precondition(Date().timeIntervalSince(started) < 3, "finish() borné par le délai")

        // Clé refusée et panne d'ouverture : état signalé, aucun blocage
        let refused = LiveTranscription(createSession: { throw AccountClient.Failure(message: "Non connecté", status: 401) }, connect: { _ in FakeSocket() })
        var refusedAlerts: [String] = []
        refused.onProblem = { refusedAlerts.append($0) }
        refused.start()
        await waitUntil("clé refusée") { refused.state == .unauthorized }
        await waitUntil("une alerte par panne") { refusedAlerts.count == 1 && refused.isIncomplete }
        await refused.finish()

        let down = LiveTranscription(createSession: { throw URLError(.notConnectedToInternet) }, connect: { _ in FakeSocket() })
        down.start()
        await waitUntil("panne") { if case .failed = down.state { true } else { false } }
        await down.finish()
        precondition(down.transcript.finalText.isEmpty, "rien à écrire si le direct n'a rien reçu")

        // Coupure courte : ni alerte ni texte incomplet. Coupure durable : une seule alerte.
        func outage(healsAfter failures: Int, delay: Double) -> LiveTranscription {
            let count = Mutex(0)
            return LiveTranscription(retryDelay: 0.05, outageAlertDelay: delay, createSession: { url }, connect: { _ in
                let attempt = count.withLock { value -> Int in value += 1; return value }
                return FakeSocket(failSends: attempt <= failures)
            })
        }
        func pump(_ live: LiveTranscription) {
            for track in AudioTrack.allCases {
                live.feed(track, tone(rate: 48_000, channels: 1, frames: 9_600), hostTime: mach_absolute_time())
            }
        }
        var alerts: [String] = []
        let brief = outage(healsAfter: 1, delay: 5)
        brief.onProblem = { alerts.append($0) }
        brief.start()
        pump(brief)
        await waitUntil("reprise rapide") { brief.state == .live }
        try? await Task.sleep(for: .milliseconds(200))
        pump(brief)
        await brief.finish()
        precondition(alerts.isEmpty && !brief.isIncomplete, "coupure courte silencieuse")

        let lasting = outage(healsAfter: 10_000, delay: 0.1)
        lasting.onProblem = { alerts.append($0) }
        lasting.start()
        pump(lasting)
        await waitUntil("alerte de coupure") { alerts.count == 1 }
        try? await Task.sleep(for: .milliseconds(300))
        precondition(alerts.count == 1 && lasting.isIncomplete, "une seule alerte par panne")
        await lasting.finish()

        print("Transcription en direct : tests réussis")
    }
}

final class HangingSocket: LiveSocket, @unchecked Sendable {
    private let inner = FakeSocket()
    func send(_ data: Data) async throws {}
    func send(text: String) async throws {}
    func receive() async throws -> String? { try await inner.receive() }
    func close() { inner.close() }
}

final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}
