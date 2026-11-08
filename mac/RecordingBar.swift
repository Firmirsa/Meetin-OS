import Accelerate
import AVFoundation
import SwiftUI

/// Mesure le volume des deux pistes (micro et son de l'appel) pour la barre d'enregistrement.
/// `feed` est appelé par les fils audio et ne fait qu'un calcul rapide ; `take` est lu par l'interface.
final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var loudest: Float = 0

    func feed(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.rms(buffer)
        lock.lock()
        loudest = max(loudest, rms)
        lock.unlock()
    }

    /// Le son le plus fort reçu depuis la dernière lecture, entre 0 (silence) et 1 (voix forte).
    func take() -> Double {
        lock.lock()
        let value = loudest
        loudest = 0
        lock.unlock()
        return Self.normalized(value)
    }

    /// Puissance moyenne (RMS) du morceau audio, sur le canal le plus fort.
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = vDSP_Length(buffer.frameLength)
        let stride = vDSP_Stride(buffer.stride)
        var result: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            // Entrelacé : tous les canaux dans le premier tableau, décalés d'un échantillon.
            let samples = buffer.format.isInterleaved ? channels[0] + channel : channels[channel]
            var value: Float = 0
            vDSP_rmsqv(samples, stride, &value, frames)
            result = max(result, value)
        }
        return result.isFinite ? result : 0
    }

    /// Convertit en décibels : -50 dB ou moins (silence, bruit de fond) donne 0, -10 dB donne 1.
    static func normalized(_ rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(1, max(0, (decibels + 50) / 40))
    }
}

/// Niveau lissé et chrono affichés par la barre, mis à jour 25 fois par seconde pendant l'enregistrement.
@MainActor
@Observable
final class RecordingLevel {
    private(set) var level = 0.0
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start(reading meter: AudioLevelMeter, since start: Date) {
        stop()
        elapsed = 0
        _ = meter.take()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, !Task.isCancelled else { return }
                self.update(heard: meter.take(), elapsed: Date().timeIntervalSince(start))
            }
        }
    }

    /// Fige le chrono et remet les barres à plat.
    func stop() {
        loop?.cancel()
        loop = nil
        level = 0
    }

    private func update(heard: Double, elapsed: TimeInterval) {
        // Monte vite quand quelqu'un parle, redescend en douceur au silence : les barres ne tremblent pas.
        let speed = heard > level ? 0.55 : 0.18
        let next = level + (heard - level) * speed
        level = next < 0.02 ? 0 : next
        self.elapsed = elapsed
    }
}

/// La barre de `brand/` reliée au vrai son. Vue séparée : seule la barre se redessine 25 fois par seconde.
struct LiveRecordingBar: View {
    let level: RecordingLevel
    let elapsed: TimeInterval
    let paused: Bool
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        MTRecordingBar(elapsed: elapsed, level: paused ? 0 : level.level,
                       paused: paused, onPause: onPause, onStop: onStop)
    }
}
