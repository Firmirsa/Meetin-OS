import AVFoundation
import Foundation

final class StubGladia: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let authorized = request.value(forHTTPHeaderField: "x-gladia-key") == "fixture"
        let body: String
        switch (request.httpMethod, request.url!.path) {
        case ("POST", "/v2/upload"):
            precondition(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
            var sent = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    sent.append(contentsOf: buffer.prefix(count))
                }
            }
            precondition(sent.range(of: Data("ftyp".utf8)) != nil, "l’audio envoyé doit être un vrai M4A, même après récupération d’un CAF")
            body = #"{"audio_url":"https://example.invalid/test.m4a"}"#
        case ("POST", "/v2/pre-recorded"):
            body = #"{"result_url":"https://api.gladia.io/v2/pre-recorded/test"}"#
        case ("GET", "/v2/pre-recorded/test"):
            body = #"{"status":"done","result":{"transcription":{"full_transcript":"Bonjour.","utterances":[{"start":1,"speaker":0,"text":"Bonjour."}]}}}"#
        default:
            fatalError("Unexpected Gladia request")
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: authorized ? 200 : 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

// Réponses séquentielles pour vérifier les reprises du GET sans recréer le travail distant.
final class PollingGladia: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var failures: [Int] = []
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func reset(_ statuses: [Int]) { lock.withLock { failures = statuses; counts = [:] } }
    static func count(_ method: String) -> Int { lock.withLock { counts[method, default: 0] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let method = request.httpMethod!
        let status = Self.lock.withLock {
            Self.counts[method, default: 0] += 1
            return method == "GET" && !Self.failures.isEmpty ? Self.failures.removeFirst() : 200
        }
        if status == -1 {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let body: String
        if method == "GET" {
            body = #"{"status":"done","result":{"transcription":{"full_transcript":"Reprise réussie."}}}"#
        } else if request.url!.lastPathComponent == "upload" {
            body = #"{"audio_url":"https://example.invalid/test.m4a"}"#
        } else {
            body = #"{"result_url":"https://api.gladia.io/v2/pre-recorded/test"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct GladiaSmoke {
    static func main() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let microphone = dir.appendingPathComponent("microphone.caf")
        let system = dir.appendingPathComponent("appel.caf")
        try writeTone(at: microphone)
        try writeTone(at: system)
        let recovered = AudioCapture.recover(microphone: microphone, system: system, microphoneStart: 100, systemStart: 102)
        precondition(recovered.audio == microphone && recovered.audio?.pathExtension == "caf")
        precondition(recovered.tracks?.systemOffset == 2, "les deux pistes partielles gardent leur décalage")
        let missing = dir.appendingPathComponent("absent.caf")
        precondition(AudioCapture.recover(microphone: missing, system: system).audio == system, "piste appel conservée seule")
        precondition(AudioCapture.recover(microphone: missing, system: missing).audio == nil, "aucun faux fichier en cas de panne totale")
        let tracks = AudioCapture.Tracks(
            microphone: microphone, system: system, microphoneOffset: 0, systemOffset: 2
        )
        let mix = dir.appendingPathComponent("mix.m4a")
        try await AudioCapture.mix(microphone: microphone, system: system, to: mix, systemOffset: 2)
        let duration = try await AVURLAsset(url: mix).load(.duration).seconds
        precondition(abs(duration - 3) < 0.15, "The mix must keep the track offset")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubGladia.self]
        let session = URLSession(configuration: configuration)
        do {
            _ = try await Gladia(key: "wrong", session: session).transcribe(mix)
            fatalError("Expected an authentication error")
        } catch Gladia.RequestError.unauthorized {}

        let client = Gladia(key: "fixture", session: session)
        let mixedTranscript = try await client.transcribe(mix)
        precondition(mixedTranscript == "[00:01] Voix 1 · Bonjour.")
        let recoveredTranscript = try await client.transcribe(microphone)
        precondition(recoveredTranscript == mixedTranscript, "un CAF récupéré est converti avant envoi")
        let trackTranscript = try await client.transcribe(tracks: tracks)
        precondition(trackTranscript == "[00:01] Micro · Bonjour.\n[00:03] Audio de l’appel · Bonjour.")
        let silentTrack = Gladia.format(
            microphone: [.init(start: 1, speaker: 0, text: "Bonjour.")], system: [], tracks: tracks
        )
        precondition(silentTrack.contains("Audio de l’appel · aucune parole reconnue."))
        let pollingConfiguration = URLSessionConfiguration.ephemeral
        pollingConfiguration.protocolClasses = [PollingGladia.self]
        let polling = Gladia(key: "fixture", session: URLSession(configuration: pollingConfiguration), pollingRetryDelay: 0.01)
        for failures in [[-1, 503], [429]] {
            PollingGladia.reset(failures)
            let text = try await polling.transcribe(mix)
            precondition(text.contains("Reprise réussie.") && PollingGladia.count("GET") == failures.count + 1)
            precondition(PollingGladia.count("POST") == 2, "un upload et un seul POST de transcription, malgré les reprises")
        }
        for terminal in [401, 402, 400] {
            PollingGladia.reset([terminal])
            do {
                _ = try await polling.transcribe(mix)
                fatalError("erreur terminale attendue")
            } catch { precondition(PollingGladia.count("GET") == 1 && PollingGladia.count("POST") == 2) }
        }
        PollingGladia.reset([503, 503, 503, 200])
        do {
            _ = try await polling.transcribe(mix)
            fatalError("budget de reprises épuisé attendu")
        } catch { precondition(PollingGladia.count("GET") == 3 && PollingGladia.count("POST") == 2) }
        for status in [402, 429] {
            let text = Gladia.RequestError.http(stage: "ouverture du direct", status: status).localizedDescription
            precondition(!text.contains("HTTP") && !text.contains(String(status)), "limites Gladia expliquées sans code brut")
        }
        print("Mix, horodatage, pistes séparées, silence et refus de clé vérifiés avec Gladia simulé.")
        print("Polling Gladia : réseau, 5xx, 429 repris ; 401 et quota terminaux ; budget borné ; aucun POST répété.")
    }

    static func writeTone(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<48_000 {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48_000) * 0.2)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
