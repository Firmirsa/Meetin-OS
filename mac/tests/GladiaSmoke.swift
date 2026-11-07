import AVFoundation
import Foundation

final class StubGladia: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture"
        precondition(request.url?.host == "localhost" && request.value(forHTTPHeaderField: "x-gladia-key") == nil)
        let body: String
        switch (request.httpMethod, request.url!.path) {
        case ("POST", "/api/gladia"):
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            let id = request.value(forHTTPHeaderField: "Idempotency-Key")!
            body = #"{"id":"\#(id)"}"#
        case ("GET", "/api/gladia"):
            body = #"{"status":"done","segments":[{"start":1,"speaker":0,"text":"Bonjour."}]}"#
        default:
            fatalError("Unexpected Gladia request")
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: authorized ? 200 : 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
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
        let api = AccountClient(baseURL: URL(string: "http://localhost:3000")!, http: session)
        do {
            _ = try await Gladia(client: api, token: { "wrong" }).transcribe(mix)
            fatalError("Expected an authentication error")
        } catch let error as AccountClient.Failure where error.status == 401 {}

        let client = Gladia(client: api, token: { "fixture" })
        let mixedTranscript = try await client.transcribe(mix)
        precondition(mixedTranscript == "[00:01] Voix 1 · Bonjour.")
        let trackTranscript = try await client.transcribe(tracks: tracks)
        precondition(trackTranscript == "[00:01] Micro · Bonjour.\n[00:03] Audio de l’appel · Bonjour.")
        let silentTrack = Gladia.format(
            microphone: [.init(start: 1, speaker: 0, text: "Bonjour.")], system: [], tracks: tracks
        )
        precondition(silentTrack.contains("Audio de l’appel · aucune parole reconnue."))
        print("Mix, horodatage, pistes séparées, silence et compte requis vérifiés avec le serveur Meetin-OS simulé.")
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
