import AVFoundation
import Foundation

@main
struct MeetingAudioPlayerSmoke {
    static func silentRecording(_ url: URL, seconds: Int) throws {
        let rate = 16_000
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1
        ])
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0 }
        try file.write(from: buffer)
    }

    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.m4a")
        let second = folder.appendingPathComponent("second.m4a")
        try silentRecording(first, seconds: 2)
        try silentRecording(second, seconds: 1)

        let player = MeetingAudioPlayer()
        precondition(!player.isPlaying && player.duration == 0, "pas de lecture automatique")
        player.toggle(first)
        precondition(player.isPlaying && abs(player.duration - 2) < 0.2)
        for _ in 0..<20 {
            if player.elapsed > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(player.elapsed > 0, "progression visible")
        player.toggle(first)
        let pausedAt = player.elapsed
        try await Task.sleep(for: .milliseconds(200))
        precondition(!player.isPlaying && player.elapsed == pausedAt, "pause stable")
        player.toggle(first)
        precondition(player.isPlaying && player.elapsed == pausedAt, "reprise au même endroit")

        player.toggle(second)
        precondition(player.isPlaying && player.elapsed == 0 && abs(player.duration - 1) < 0.2,
                     "un autre fichier repart au début")
        for _ in 0..<40 {
            if !player.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(!player.isPlaying && player.elapsed == player.duration, "fin détectée")
        player.toggle(second)
        precondition(player.isPlaying && player.elapsed == 0, "relecture depuis le début")
        player.stop()
        precondition(!player.isPlaying && player.duration == 0 && player.elapsed == 0, "arrêt et remise à zéro")
        player.toggle(folder.appendingPathComponent("missing.m4a"))
        precondition(player.failed && !player.isPlaying && player.duration == 0, "fichier introuvable")
        player.toggle(second)
        precondition(!player.failed && player.isPlaying, "lecture possible après une erreur")
        player.stop()
        print("MeetingAudioPlayerSmoke OK")
    }
}
