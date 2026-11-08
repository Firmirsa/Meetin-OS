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
        do {
            _ = try await Gladia(key: "wrong", session: session).transcribe(mix)
            fatalError("Expected an authentication error")
        } catch Gladia.RequestError.unauthorized {}

        let client = Gladia(key: "fixture", session: session)
        let mixedTranscript = try await client.transcribe(mix)
        precondition(mixedTranscript == "[00:01] Voix 1 · Bonjour.")
        let trackTranscript = try await client.transcribe(tracks: tracks)
        let me = AudioTrack.microphone.label
        precondition(me == AudioTrack.speakerName(NSFullUserName()))
        precondition(trackTranscript == "[00:01] \(me) · Bonjour.\n[00:03] Audio de l’appel · Bonjour.")
        precondition(AudioTrack.speakerName("  Léa   Martin\n") == "Léa Martin")
        precondition(AudioTrack.speakerName(" ") == "Vous")
        let silentTrack = Gladia.format(
            microphone: [.init(start: 1, speaker: 0, text: "Bonjour.")], system: [], tracks: tracks
        )
        precondition(silentTrack.contains("Audio de l’appel · aucune parole reconnue."))
        let silentMicrophone = Gladia.format(
            microphone: [], system: [.init(start: 1, speaker: 0, text: "Bonjour.")], tracks: tracks
        )
        precondition(silentMicrophone.contains("\(me) · aucune parole reconnue."))
        print("Mix, horodatage, pistes séparées, nom de l’utilisateur, silence et refus de clé vérifiés avec Gladia simulé.")
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
