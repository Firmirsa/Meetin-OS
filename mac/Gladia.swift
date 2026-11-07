import Foundation

struct Gladia {
    let key: String
    var session: URLSession = .shared

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
            }
            let transcription: Transcription?
        }
        let status: String
        let result: Details?
    }

    func transcribe(_ file: URL) async throws -> String {
        let boundary = UUID().uuidString
        let audio = try Data(contentsOf: file)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"reunion.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8)
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let upload: Upload = try await request(
            URL(string: "https://api.gladia.io/v2/upload")!, body: body,
            type: "multipart/form-data; boundary=\(boundary)"
        )
        let payload = try JSONSerialization.data(withJSONObject: ["audio_url": upload.audio_url, "diarization": true])
        let job: Job = try await request(URL(string: "https://api.gladia.io/v2/transcription")!, body: payload)
        guard job.result_url.scheme == "https", job.result_url.host == "api.gladia.io" else {
            throw CaptureError("URL de résultat Gladia inattendue.")
        }
        for _ in 0..<90 {
            let result: Result = try await request(job.result_url)
            switch result.status {
            case "done":
                guard let transcript = result.result?.transcription else {
                    throw CaptureError("Gladia a terminé sans renvoyer de transcription.")
                }
                let lines = (transcript.utterances ?? []).map { segment -> String in
                    let seconds = Int(segment.start)
                    let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
                    let speaker = segment.speaker.map { "Voix \($0 + 1)" } ?? "Voix"
                    return "[\(time)] \(speaker) · \(segment.text)"
                }
                return lines.isEmpty ? transcript.full_transcript : lines.joined(separator: "\n")
            case "error", "failed":
                throw CaptureError("La transcription a échoué chez Gladia.")
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw CaptureError("Le résultat Gladia n’est pas disponible après le délai d’attente.")
    }

    private func request<T: Decodable>(_ url: URL, body: Data? = nil, type: String = "application/json") async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(key, forHTTPHeaderField: "x-gladia-key")
        if let body {
            request.httpMethod = "POST"
            request.setValue(type, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CaptureError("Gladia a renvoyé une erreur HTTP \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
