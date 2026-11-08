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

// L'identifiant de piste (rawValue) reste interne : écho, tri et fichiers s'appuient dessus.
// Le libellé n'est que le nom affiché devant chaque phrase de la transcription.
enum AudioTrack: String, CaseIterable, Hashable, Sendable {
    case microphone, system

    var label: String { self == .microphone ? Self.userLabel : "Audio de l’appel" }

    static let userLabel = speakerName(NSFullUserName())

    // Nom complet du compte macOS, ou « Vous » s'il est vide.
    static func speakerName(_ fullName: String) -> String {
        let name = fullName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return name.isEmpty ? "Vous" : name
    }
}

final class AudioCapture {
    // Les rappels audio et la fermeture des pistes se synchronisent via cette barrière.
    private final class InputGate {
        private let condition = NSCondition()
        private var enabled = false
        private var receiving = 0

        func setEnabled(_ value: Bool) {
            condition.lock()
            enabled = value
            while !enabled && receiving > 0 { condition.wait() }
            condition.unlock()
        }

        func receive(_ action: () -> Void) {
            condition.lock()
            guard enabled else {
                condition.unlock()
                return
            }
            receiving += 1
            condition.unlock()
            action()
            condition.lock()
            receiving -= 1
            if receiving == 0 { condition.signal() }
            condition.unlock()
        }
    }

    struct SampleSpan {
        let start: Double
        let duration: Double
        let hasSignal: Bool
    }

    struct Segment {
        let microphone: SampleSpan?
        let system: SampleSpan?

        var origin: Double { min(microphone?.start ?? .infinity, system?.start ?? .infinity) }
        var duration: Double { max(end(microphone), end(system)) }

        func offset(_ span: SampleSpan) -> Double { span.start - origin }
        private func end(_ span: SampleSpan?) -> Double {
            guard let span else { return 0 }
            return offset(span) + span.duration
        }
    }

    // Copie de l'audio pour le direct. Ne doit jamais bloquer.
    var onAudio: ((AudioTrack, AVAudioPCMBuffer, UInt64) -> Void)?
    private let engine = AVAudioEngine()
    private var inputTapInstalled = false
    private var systemTap: SystemAudioTap?
    private var gate: InputGate?
    private var micWriter: TrackWriter?
    private var systemWriter: TrackWriter?
    private let folder: URL
    private let rawFolder: URL
    private let microphone: URL
    private let system: URL
    private var segments: [Segment] = []
    private var nextSegment = 0
    private var started = false

    private var currentSegment: Segment {
        Segment(microphone: micWriter?.span, system: systemWriter?.span)
    }

    var activeDuration: Double { segments.reduce(0) { $0 + $1.duration } + currentSegment.duration }

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        rawFolder = folder.appendingPathComponent("tranches", isDirectory: true)
        microphone = folder.appendingPathComponent("microphone.m4a")
        system = folder.appendingPathComponent("appel.m4a")
    }

    func start() async throws {
        guard !started else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw AudioPermissionHelp.microphone }
        try FileManager.default.createDirectory(at: rawFolder, withIntermediateDirectories: true)
        try startInputs(listener: onAudio)
        started = true
    }

    func pause() throws {
        guard gate != nil else { return }
        stopInputs()
        let mic = micWriter
        let call = systemWriter
        micWriter = nil
        systemWriter = nil
        // Conserver les fichiers lisibles même si une des deux pistes a rencontré une erreur.
        let microphone = mic?.span
        let system = call?.span
        segments.append(Segment(microphone: microphone, system: system))
        nextSegment += 1
        let microphoneError = mic?.finish()
        let systemError = call?.finish()
        if let error = microphoneError ?? systemError { throw error }
    }

    func resume(onAudio listener: ((AudioTrack, AVAudioPCMBuffer, UInt64) -> Void)?) throws {
        guard started, gate == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioPermissionHelp.microphone
        }
        try startInputs(listener: listener)
    }

    private func rawFile(_ track: AudioTrack, segment: Int) -> URL {
        rawFolder.appendingPathComponent("\(segment)-\(track.rawValue).caf")
    }

    private func startInputs(listener: ((AudioTrack, AVAudioPCMBuffer, UInt64) -> Void)?) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError("Aucun micro disponible. Vérifiez votre périphérique d’entrée.")
        }
        let tap = try SystemAudioTap()
        let mic = TrackWriter(url: rawFile(.microphone, segment: nextSegment))
        let call = TrackWriter(url: rawFile(.system, segment: nextSegment), checkSignal: true)
        let gate = InputGate()
        systemTap = tap
        self.gate = gate
        do {
            try tap.start { buffer, time in
                gate.receive {
                    call.append(buffer, hostTime: time)
                    listener?(.system, buffer, time)
                }
            }
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
                let hostTime = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
                gate.receive {
                    mic.append(buffer, hostTime: hostTime)
                    listener?(.microphone, buffer, hostTime)
                }
            }
            inputTapInstalled = true
            try engine.start()
            micWriter = mic
            systemWriter = call
            gate.setEnabled(true)
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
        guard started else { throw CaptureError("Aucun enregistrement en cours.") }
        try pause()
        let output = folder.appendingPathComponent("reunion.m4a")
        var mic: [(URL, Double)] = []
        var call: [(URL, Double)] = []
        var offset = 0.0
        var callHasSignal = false
        for (index, segment) in segments.enumerated() {
            if let span = segment.microphone { mic.append((rawFile(.microphone, segment: index), offset + segment.offset(span))) }
            if let span = segment.system {
                call.append((rawFile(.system, segment: index), offset + segment.offset(span)))
                callHasSignal = callHasSignal || span.hasSignal
            }
            offset += segment.duration
        }

        let micStart = mic.first?.1
        let callStart = callHasSignal ? call.first?.1 : nil
        let tracks: Tracks?
        let help: AudioPermissionHelp?
        if let micStart, let callStart {
            try await Self.exportAudioLanes([mic.map { ($0.0, $0.1 - micStart) }], to: microphone)
            try await Self.exportAudioLanes([call.map { ($0.0, $0.1 - callStart) }], to: system)
            try await Self.exportAudioLanes([mic, call], to: output)
            tracks = Tracks(microphone: microphone, system: system, microphoneOffset: micStart, systemOffset: callStart)
            help = nil
        } else if micStart != nil {
            try await Self.exportAudioLanes([mic], to: output)
            tracks = nil
            help = .systemAudioSilent
        } else if callStart != nil {
            try await Self.exportAudioLanes([call], to: output)
            tracks = nil
            help = .microphone
        } else {
            throw AudioPermissionHelp.microphone
        }
        try? FileManager.default.removeItem(at: rawFolder)
        started = false
        return (output, tracks, help)
    }

    private func stopInputs() {
        gate?.setEnabled(false)
        gate = nil
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
        try await exportAudioLanes(inputs.map { [$0] }, to: output)
    }

    static func exportAudioLanes(_ lanes: [[(URL, Double)]], to output: URL) async throws {
        let composition = try await audioComposition(lanes)
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptureError("Impossible de préparer l’export audio.")
        }
        try await exporter.export(to: output, as: .m4a)
    }

    static func audioComposition(_ lanes: [[(URL, Double)]]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        for lane in lanes {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CaptureError("Impossible de préparer une piste audio.")
            }
            for (index, input) in lane.enumerated() {
                let (url, offset) = input
                let asset = AVURLAsset(url: url)
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw CaptureError("Impossible de lire une piste audio.")
                }
                let range = try await source.load(.timeRange)
                let position = CMTime(seconds: offset, preferredTimescale: 192_000)
                // L'arrondi des durées ne doit jamais insérer une tranche à l'intérieur de la précédente.
                // Une piste vide a une fin invalide : la comparer efface le décalage initial.
                let insertion = index == 0 ? position : CMTimeMaximum(position, track.timeRange.end)
                try track.insertTimeRange(range, of: source, at: insertion)
            }
        }
        return composition
    }

    private final class TrackWriter {
        private let url: URL
        private let queue = DispatchQueue(label: "MeetinOS.audio.file")
        private var file: AVAudioFile?
        private var firstSample: Double?
        private var hasSignal: Bool
        private var failure: Error?

        init(url: URL, checkSignal: Bool = false) {
            self.url = url
            hasSignal = !checkSignal
        }

        func append(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
            guard buffer.frameLength > 0 else { return }
            queue.sync {
                guard failure == nil else { return }
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

        var span: SampleSpan? {
            queue.sync {
                guard let firstSample, let file, file.length > 0 else { return nil }
                return SampleSpan(start: firstSample, duration: Double(file.length) / file.processingFormat.sampleRate,
                                  hasSignal: hasSignal)
            }
        }

        func finish() -> Error? {
            queue.sync {
                file = nil
                return failure
            }
        }

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
