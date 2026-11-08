import AVFoundation
import Foundation

// Audio goes to the authenticated Meetin-OS API. Provider credentials stay on the server.
struct Gladia {
    let client: AccountClient
    let token: @Sendable () async throws -> String
    private static let chunkBytes = 90 * 32_000

    struct Segment: Decodable {
        let start: Double
        let speaker: Int?
        let text: String
    }

    private struct Started: Decodable { let id: UUID }
    private struct Result: Decodable {
        let status: String
        let segments: [Segment]?
    }

    static func audioMs(_ files: [URL]) throws -> Double {
        try files.reduce(0) { sum, url in
            let file = try AVAudioFile(forReading: url)
            return sum + 1_000 * Double(file.length) / file.processingFormat.sampleRate
        }
    }

    func transcribe(_ file: URL) async throws -> String {
        let segments = try await transcribeTrack(file)
        guard !segments.isEmpty else { return "Aucune parole reconnue." }
        return segments.map {
            let label = $0.speaker.map { "Voix \($0 + 1)" } ?? "Voix"
            return Self.line(at: $0.start, label: label, text: $0.text)
        }.joined(separator: "\n")
    }

    func transcribe(tracks: AudioCapture.Tracks) async throws -> String {
        async let microphone = transcribeTrack(tracks.microphone)
        async let system = transcribeTrack(tracks.system)
        let (mic, call) = try await (microphone, system)
        return Self.format(microphone: mic, system: call, tracks: tracks)
    }

    static func format(microphone: [Segment], system: [Segment], tracks: AudioCapture.Tracks) -> String {
        let me = AudioTrack.microphone.label, call = AudioTrack.system.label
        let local = microphone.map { ($0.start + tracks.microphoneOffset, me, $0.text) }
        let remote = system.map { ($0.start + tracks.systemOffset, call, $0.text) }
        var lines = (local + remote).sorted { $0.0 < $1.0 }.map { line(at: $0.0, label: $0.1, text: $0.2) }
        if microphone.isEmpty { lines.append("\(me) · aucune parole reconnue.") }
        if system.isEmpty { lines.append("\(call) · aucune parole reconnue.") }
        return lines.joined(separator: "\n")
    }

    static func line(at start: Double, label: String, text: String) -> String {
        let seconds = Int(start.isFinite ? min(max(0, start), 86_400) : 0)
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return "[\(time)] \(label) · \(text)"
    }

    private func transcribeTrack(_ url: URL) async throws -> [Segment] {
        let file = try AVAudioFile(forReading: url)
        let converter = LiveAudioConverter()
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192) else {
            throw CaptureError("Impossible de préparer cette piste audio.")
        }
        var audio = Data()
        var sent = 0
        var segments: [Segment] = []
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: input)
            guard input.frameLength > 0 else { break }
            if let converted = converter.convert(input) { audio.append(converted) }
            if audio.count >= Self.chunkBytes {
                let chunk = Data(audio.prefix(Self.chunkBytes))
                segments += try await transcribeChunk(chunk, offset: Double(sent) / 32_000)
                sent += chunk.count
                audio.removeFirst(chunk.count)
            }
        }
        if !audio.isEmpty {
            segments += try await transcribeChunk(audio, offset: Double(sent) / 32_000)
        }
        return segments
    }

    private func transcribeChunk(_ audio: Data, offset: Double) async throws -> [Segment] {
        let id = UUID()
        let endpoint = client.url("gladia")
        let started: Started
        do {
            started = try await client.request(endpoint, token: token(), body: audio,
                                               type: "application/octet-stream", idempotency: id)
        } catch let error as URLError where error.code == .networkConnectionLost || error.code == .timedOut {
            // The same ID is safe even if the first request already reached the server.
            started = try await client.request(endpoint, token: token(), body: audio,
                                               type: "application/octet-stream", idempotency: id)
        }
        guard started.id == id, var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw CaptureError("Identifiant de transcription inattendu.")
        }
        parts.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        guard let resultURL = parts.url else { throw CaptureError("Adresse de transcription invalide.") }
        for _ in 0..<90 {
            let result: Result = try await client.request(resultURL, token: token())
            switch result.status {
            case "done":
                return (result.segments ?? []).map {
                    Segment(start: $0.start + offset, speaker: offset == 0 ? $0.speaker : nil, text: $0.text)
                }
            case "failed": throw CaptureError("La transcription a échoué chez Gladia.")
            default: try await Task.sleep(for: .seconds(2))
            }
        }
        throw CaptureError("Le résultat Gladia n’est pas disponible après le délai d’attente.")
    }
}
