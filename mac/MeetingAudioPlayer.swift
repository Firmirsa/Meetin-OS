import AVFoundation
import SwiftUI

@MainActor
@Observable
final class MeetingAudioPlayer {
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var failed = false

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var source: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func toggle(_ recording: URL) {
        if source != recording { stop() }
        if isPlaying {
            audio?.pause()
            if let audio { elapsed = audio.currentTime }
            isPlaying = false
            progressTask?.cancel()
            progressTask = nil
            return
        }

        do {
            guard recording.isFileURL else {
                failed = true
                return
            }
            let player = try audio ?? AVAudioPlayer(contentsOf: recording)
            guard player.duration.isFinite, player.duration > 0 else {
                failed = true
                return
            }
            if elapsed >= player.duration {
                player.currentTime = 0
                elapsed = 0
            }
            guard player.play() else {
                failed = true
                return
            }
            source = recording
            audio = player
            duration = player.duration
            failed = false
            isPlaying = true
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self, self.updateProgress() else { return }
                }
            }
        } catch {
            failed = true
        }
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        audio?.stop()
        audio = nil
        source = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        failed = false
    }

    private func updateProgress() -> Bool {
        guard let audio, audio.isPlaying else {
            isPlaying = false
            elapsed = duration
            progressTask = nil
            return false
        }
        elapsed = min(audio.currentTime, duration)
        return true
    }
}

struct MeetingAudioPlaybackStatus: View {
    let player: MeetingAudioPlayer

    var body: some View {
        if player.failed {
            Text("Impossible de lire cet enregistrement.")
                .font(.mtSans(12))
                .foregroundStyle(Color.mtWarn)
        } else if player.duration > 0 {
            let elapsed = timestamp(player.elapsed)
            let duration = timestamp(player.duration)
            HStack(spacing: 10) {
                ProgressView(value: player.elapsed, total: player.duration)
                    .accessibilityLabel("Progression de la lecture")
                    .accessibilityValue("\(elapsed) sur \(duration)")
                Text("\(elapsed) / \(duration)")
                    .font(.mtSans(12))
                    .monospacedDigit()
                    .foregroundStyle(Color.mtInk2)
                    .accessibilityHidden(true)
            }
        }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
