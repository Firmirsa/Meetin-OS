import AVFoundation
import CoreAudio

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum AudioPermissionHelp: LocalizedError {
    case microphone
    case systemAudio
    case systemAudioSilent
    case systemAudioTimeout

    var settingsLabel: String {
        self == .microphone ? "Ouvrir les réglages du micro" : "Ouvrir les réglages de l’audio système"
    }

    var settingsURL: URL {
        let pane = self == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    var errorDescription: String? {
        switch self {
        case .microphone:
            "Activez Meetin-OS dans les réglages du micro, puis réessayez."
        case .systemAudio:
            "Activez Meetin-OS dans « Audio du système uniquement », puis réessayez."
        case .systemAudioSilent:
            "Aucun son de l’appel détecté. Vérifiez le son et l’autorisation « Audio du système uniquement »."
        case .systemAudioTimeout:
            "macOS n’a pas répondu pour l’audio du système. Répondez à la demande d’autorisation si elle est affichée, puis réessayez."
        }
    }
}

enum AudioTrack: String, CaseIterable, Hashable, Sendable {
    case microphone, system

    var label: String { self == .microphone ? "Micro" : "Audio de l’appel" }
}

final class AudioCapture {
    // Copie de l'audio pour le direct, à renseigner avant start(). Ne doit jamais bloquer.
    var onAudio: ((AudioTrack, AVAudioPCMBuffer, UInt64) -> Void)?
    var onWarning: (@MainActor @Sendable (String) -> Void)?
    private let engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    private var inputTapInstalled = false
    private var systemTap: SystemAudioTap?
    private var micWriter: TrackWriter?
    private var systemWriter: TrackWriter?
    let folder: URL
    let microphone: URL
    let system: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        microphone = folder.appendingPathComponent("microphone.caf")
        system = folder.appendingPathComponent("appel.caf")
    }

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw AudioPermissionHelp.microphone
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError("Aucun micro disponible. Vérifiez votre périphérique d’entrée.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let tap = try SystemAudioTap()
        let mic = TrackWriter(url: microphone)
        let call = TrackWriter(url: system, checkSignal: true)
        systemTap = tap
        micWriter = mic
        systemWriter = call
        do {
            let listener = onAudio
            try tap.start { buffer, time in
                call.append(buffer, hostTime: time)
                listener?(.system, buffer, time)
            }
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
                let hostTime = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
                mic.append(buffer, hostTime: hostTime)
                listener?(.microphone, buffer, hostTime)
            }
            inputTapInstalled = true
            try engine.start()
            let warning = onWarning
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { _ in
                // Le fichier a un format fixe : ne pas redémarrer avec celui du nouveau périphérique.
                Task { @MainActor in
                    warning?("Le périphérique audio a changé : la piste micro s’est arrêtée. L’audio de l’appel continue. Arrête puis relance l’enregistrement pour reprendre le micro.")
                }
            }
        } catch {
            stopInputs()
            throw error
        }
    }

    struct Tracks {
        let microphone: URL
        let system: URL
        let microphoneOffset: Double
        let systemOffset: Double
    }

    func stop() async throws -> (mix: URL, tracks: Tracks?, help: AudioPermissionHelp?) {
        guard systemTap != nil else { throw CaptureError("Aucun enregistrement en cours.") }
        stopInputs()
        // Fermer les deux fichiers même si l'écriture de la première piste a échoué.
        let micResult = Result { try micWriter?.finish() }
        let callResult = Result { try systemWriter?.finish() }
        let mic = try micResult.get()
        let call = try callResult.get()
        let output = folder.appendingPathComponent("reunion.m4a")

        guard let mic else {
            guard let call, call.hasSignal else { throw AudioPermissionHelp.microphone }
            try await Self.exportAudio([(system, 0)], to: output)
            return (output, nil, .microphone)
        }
        guard let call, call.hasSignal else {
            try await Self.exportAudio([(microphone, 0)], to: output)
            return (output, nil, .systemAudioSilent)
        }
        let origin = min(mic.start, call.start)
        let tracks = Tracks(
            microphone: microphone, system: system,
            microphoneOffset: mic.start - origin, systemOffset: call.start - origin
        )
        try await Self.mix(
            microphone: microphone, system: system, to: output,
            microphoneOffset: tracks.microphoneOffset, systemOffset: tracks.systemOffset
        )
        return (output, tracks, nil)
    }

    // Repli après une erreur d'écriture ou d'export. Les CAF restent des CAF.
    var recovery: (audio: URL?, tracks: Tracks?) {
        Self.recover(
            microphone: microphone, system: system,
            microphoneStart: micWriter?.startTime, systemStart: systemWriter?.startTime
        )
    }

    static func recover(
        microphone: URL, system: URL, microphoneStart: Double? = nil, systemStart: Double? = nil
    ) -> (audio: URL?, tracks: Tracks?) {
        let hasMic = ((try? AVAudioFile(forReading: microphone))?.length ?? 0) > 0
        let hasCall = ((try? AVAudioFile(forReading: system))?.length ?? 0) > 0
        let origin = min(microphoneStart ?? 0, systemStart ?? 0)
        let tracks = hasMic && hasCall ? Tracks(
            microphone: microphone, system: system,
            microphoneOffset: (microphoneStart ?? 0) - origin, systemOffset: (systemStart ?? 0) - origin
        ) : nil
        return (hasMic ? microphone : (hasCall ? system : nil), tracks)
    }

    private func stopInputs() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if inputTapInstalled {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        systemTap?.stop()
        systemTap = nil
    }

    deinit { stopInputs() }

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

    private final class TrackWriter {
        private let url: URL
        private let queue = DispatchQueue(label: "MeetinOS.audio.file")
        private var file: AVAudioFile?
        private var firstSample: Double?
        private var hasSignal: Bool
        private var failure: Error?
        private var closed = false

        init(url: URL, checkSignal: Bool = false) {
            self.url = url
            hasSignal = !checkSignal
        }

        func append(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
            guard buffer.frameLength > 0 else { return }
            queue.sync {
                // Un tampon tardif après finish() ne doit pas recréer, donc vider, le fichier.
                guard failure == nil, !closed else { return }
                do {
                    if file == nil {
                        let format = buffer.format
                        file = try AVAudioFile(
                            forWriting: url, settings: format.settings,
                            commonFormat: format.commonFormat, interleaved: format.isInterleaved
                        )
                        firstSample = AVAudioTime.seconds(forHostTime: hostTime)
                    }
                    if !hasSignal { hasSignal = Self.containsSignal(buffer) }
                    try file?.write(from: buffer)
                } catch { failure = error }
            }
        }

        func finish() throws -> (start: Double, hasSignal: Bool)? {
            try queue.sync {
                defer { file = nil; closed = true }
                if let failure { throw failure }
                guard let firstSample, let file, file.length > 0 else { return nil }
                return (firstSample, hasSignal)
            }
        }

        var startTime: Double? { queue.sync { firstSample } }

        private static func containsSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
            guard let samples = buffer.floatChannelData else {
                return UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList).contains { channel in
                    UnsafeRawBufferPointer(start: channel.mData, count: Int(channel.mDataByteSize)).contains { $0 != 0 }
                }
            }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) where abs(samples[channel][frame * buffer.stride]) > 0.00001 {
                    return true
                }
            }
            return false
        }
    }
}

private final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var running = false
    private let queue = DispatchQueue(label: "MeetinOS.audio.system")
    private let format: AVAudioFormat

    init() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.processToExclude())
        description.name = "Meetin-OS"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tap))
        do {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamFormat = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &streamFormat))
            guard let format = AVAudioFormat(streamDescription: &streamFormat) else {
                throw CaptureError("Format audio du système indisponible.")
            }
            let properties: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Meetin-OS Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]]
            ]
            var device = AudioObjectID(kAudioObjectUnknown)
            try Self.check(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &device))
            self.format = format
            tapID = tap
            deviceID = device
        } catch {
            AudioHardwareDestroyProcessTap(tap)
            throw error
        }
    }

    func start(_ receive: @escaping (AVAudioPCMBuffer, UInt64) -> Void) throws {
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, queue) { [format] _, input, time, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            buffer.frameLength = buffer.frameCapacity
            let timestamp = time.pointee
            let hostTime = timestamp.mFlags.contains(.hostTimeValid) ? timestamp.mHostTime : mach_absolute_time()
            receive(buffer, hostTime)
        })
        guard let ioProc else { throw CaptureError("Impossible de préparer l’audio du système.") }
        try Self.check(AudioDeviceStart(deviceID, ioProc))
        running = true
    }

    func stop() {
        if let ioProc {
            if running { AudioDeviceStop(deviceID, ioProc) }
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
            self.ioProc = nil
            running = false
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit { stop() }

    private static func check(_ status: OSStatus) throws {
        if status == kAudioDevicePermissionsError { throw AudioPermissionHelp.systemAudio }
        // MACH_RCV_TIMED_OUT : le service audio n'a pas répondu, par exemple pendant une demande d'autorisation.
        if status == OSStatus(bitPattern: 0x1000_4003) { throw AudioPermissionHelp.systemAudioTimeout }
        guard status == noErr else { throw CaptureError("Impossible de démarrer l’audio du système (\(status)).") }
    }

    private static func processToExclude() -> [AudioObjectID] {
        var pid = getpid()
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process
        )
        return result == noErr && process != kAudioObjectUnknown ? [process] : []
    }
}
