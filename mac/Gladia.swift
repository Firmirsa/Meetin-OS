import AVFoundation
import Foundation

struct Gladia {
    let key: String
    var session: URLSession = .shared

    enum RequestError: LocalizedError {
        case unauthorized
        case http(stage: String, status: Int)
        case invalidResponse(stage: String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Gladia a refusé la clé API. Remplacez-la dans les réglages, puis relancez la transcription."
            case let .http(stage, status):
                return "Gladia · \(stage) impossible (HTTP \(status))."
            case let .invalidResponse(stage):
                return "Gladia · réponse illisible pendant \(stage)."
            }
        }
    }

    struct Segment: Decodable {
        let start: Double
        let speaker: Int?
        let text: String
    }

    private struct Upload: Decodable { let audio_url: String }
    private struct Job: Decodable { let result_url: URL }
    private struct Result: Decodable {
        struct Details: Decodable {
            struct Transcription: Decodable {
                let full_transcript: String
                let utterances: [Segment]?

                var segments: [Segment] {
                    if let utterances, !utterances.isEmpty { return utterances }
                    let text = full_transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? [] : [Segment(start: 0, speaker: nil, text: text)]
                }
            }
            let transcription: Transcription?
        }
        let status: String
        let result: Details?
    }

    func transcribe(_ file: URL) async throws -> String {
        let transcript = try await fetchTranscript(file)
        let segments = transcript.segments
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
        let local = microphone.map { ($0.start + tracks.microphoneOffset, "Micro", $0.text) }
        let remote = system.map { ($0.start + tracks.systemOffset, "Audio de l’appel", $0.text) }
        var lines = (local + remote).sorted { $0.0 < $1.0 }.map { line(at: $0.0, label: $0.1, text: $0.2) }
        if microphone.isEmpty { lines.append("Micro · aucune parole reconnue.") }
        if system.isEmpty { lines.append("Audio de l’appel · aucune parole reconnue.") }
        return lines.joined(separator: "\n")
    }

    static func line(at start: Double, label: String, text: String) -> String {
        let seconds = Int(start.isFinite ? min(max(0, start), 86_400) : 0)
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return "[\(time)] \(label) · \(text)"
    }

    private func transcribeTrack(_ file: URL) async throws -> [Segment] {
        let output = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: output) }
        try await AudioCapture.exportAudio([(file, 0)], to: output)
        return try await fetchTranscript(output).segments
    }

    private func fetchTranscript(_ file: URL) async throws -> Result.Details.Transcription {
        let boundary = UUID().uuidString
        let audio = try Data(contentsOf: file)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"reunion.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8)
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let upload: Upload = try await request(
            URL(string: "https://api.gladia.io/v2/upload")!, stage: "envoi de l’audio", body: body,
            type: "multipart/form-data; boundary=\(boundary)"
        )
        let payload = try JSONSerialization.data(withJSONObject: [
            "audio_url": upload.audio_url,
            "diarization": true,
            "language_config": ["languages": ["fr", "en"], "code_switching": true]
        ] as [String: Any])
        let job: Job = try await request(URL(string: "https://api.gladia.io/v2/pre-recorded")!, stage: "lancement de la transcription", body: payload)
        guard job.result_url.scheme == "https", job.result_url.host == "api.gladia.io" else {
            throw CaptureError("URL de résultat Gladia inattendue.")
        }
        for _ in 0..<90 {
            let result: Result = try await request(job.result_url, stage: "récupération du résultat")
            switch result.status {
            case "done":
                guard let transcript = result.result?.transcription else {
                    throw CaptureError("Gladia a terminé sans renvoyer de transcription.")
                }
                return transcript
            case "error", "failed":
                throw CaptureError("La transcription a échoué chez Gladia.")
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw CaptureError("Le résultat Gladia n’est pas disponible après le délai d’attente.")
    }

    private func request<T: Decodable>(_ url: URL, stage: String, body: Data? = nil, type: String = "application/json") async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(key, forHTTPHeaderField: "x-gladia-key")
        if let body {
            request.httpMethod = "POST"
            request.setValue(type, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RequestError.invalidResponse(stage: stage)
        }
        if http.statusCode == 401 { throw RequestError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw RequestError.http(stage: stage, status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RequestError.invalidResponse(stage: stage)
        }
    }
}
