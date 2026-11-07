import AVFoundation
import CoreGraphics
import ScreenCaptureKit

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class AudioCapture: NSObject, SCStreamOutput {
    private let queue = DispatchQueue(label: "MeetinOS.audio")
    private var files: [SCStreamOutputType: AVAudioFile] = [:]
    private var failure: Error?
    private var firstSamples: [SCStreamOutputType: CMTime] = [:]
    private var stream: SCStream?
    private let folder: URL
    let microphone: URL
    let system: URL

    override init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        microphone = folder.appendingPathComponent("microphone.caf")
        system = folder.appendingPathComponent("appel.caf")
    }

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw CaptureError("Autorisez le microphone dans Réglages Système.")
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError("Autorisez la capture d’écran et d’audio système dans Réglages Système, puis relancez l’app.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError("Aucun écran disponible.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let settings = SCStreamConfiguration()
        settings.capturesAudio = true
        settings.excludesCurrentProcessAudio = true
        settings.captureMicrophone = true
        settings.sampleRate = 48_000
        settings.channelCount = 2
        let capture = SCStream(filter: filter, configuration: settings, delegate: nil)
        // Register only the two audio outputs. No video frames are written.
        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try capture.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        try await capture.startCapture()
        stream = capture
    }

    struct Tracks {
        let microphone: URL
        let system: URL
        let microphoneOffset: Double
        let systemOffset: Double
    }

    func stop() async throws -> (mix: URL, tracks: Tracks) {
        guard let stream else { throw CaptureError("Aucun enregistrement en cours.") }
        self.stream = nil
        try await stream.stopCapture()
        let tracks: Tracks = try queue.sync {
            defer { files.removeAll() }
            if let failure { throw failure }
            guard files[.microphone]?.length ?? 0 > 0, files[.audio]?.length ?? 0 > 0 else {
                throw CaptureError("Une piste audio manque. Vérifiez le micro et le son de l’appel.")
            }
            let micStart = firstSamples[.microphone]?.seconds ?? 0
            let systemStart = firstSamples[.audio]?.seconds ?? 0
            let origin = min(micStart, systemStart)
            return Tracks(
                microphone: microphone, system: system,
                microphoneOffset: micStart - origin, systemOffset: systemStart - origin
            )
        }
        let output = folder.appendingPathComponent("reunion.m4a")
        try await Self.mix(
            microphone: microphone, system: system, to: output,
            microphoneOffset: tracks.microphoneOffset, systemOffset: tracks.systemOffset
        )
        return (output, tracks)
    }

    static func mix(
        microphone: URL, system: URL, to output: URL,
        microphoneOffset: Double = 0, systemOffset: Double = 0
    ) async throws {
        try await exportAudio([(microphone, microphoneOffset), (system, systemOffset)], to: output)
    }

    static func exportAudio(_ inputs: [(URL, Double)], to output: URL) async throws {
        let composition = AVMutableComposition()
        for (url, offset) in inputs {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CaptureError("Impossible de lire une piste audio.")
            }
            let range = try await source.load(.timeRange)
            try track.insertTimeRange(range, of: source, at: CMTime(seconds: offset, preferredTimescale: 48_000))
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptureError("Impossible de préparer l’export audio.")
        }
        try await exporter.export(to: output, as: .m4a)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard failure == nil, sample.isValid, sample.numSamples > 0,
              let description = sample.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples)) else { return }
        buffer.frameLength = buffer.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(sample.numSamples), into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            failure = CaptureError("Impossible de lire les données audio (\(status)).")
            return
        }
        do {
            if files[type] == nil {
                let timestamp = sample.presentationTimeStamp
                if timestamp.seconds.isFinite { firstSamples[type] = timestamp }
                files[type] = try AVAudioFile(
                    forWriting: type == .microphone ? microphone : system,
                    settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved
                )
            }
            try files[type]?.write(from: buffer)
        } catch { failure = error }
    }
}
