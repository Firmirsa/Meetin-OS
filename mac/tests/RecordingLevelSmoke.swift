import AVFoundation

@main
struct RecordingLevelSmoke {
    static func sine(amplitude: Float, channels: AVAudioChannelCount = 1, interleaved: Bool = false, onlyLast: Bool = false) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: interleaved)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
        buffer.frameLength = 2048
        let data = buffer.floatChannelData!
        for frame in 0..<2048 {
            let value = amplitude * sin(Float(frame) * 2 * .pi * 440 / 48_000)
            for channel in 0..<Int(channels) {
                let sample = onlyLast && channel != Int(channels) - 1 ? 0 : value
                if interleaved { data[0][frame * Int(channels) + channel] = sample } else { data[channel][frame] = sample }
            }
        }
        return buffer
    }

    @MainActor
    static func main() async {
        precondition(AudioLevelMeter.normalized(AudioLevelMeter.rms(sine(amplitude: 0))) == 0, "silence : barres à plat")
        precondition(AudioLevelMeter.normalized(AudioLevelMeter.rms(sine(amplitude: 0.001))) == 0, "bruit de fond : barres à plat")
        precondition(AudioLevelMeter.normalized(AudioLevelMeter.rms(sine(amplitude: 0.5))) > 0.95, "voix forte : barres hautes")
        let medium = AudioLevelMeter.normalized(AudioLevelMeter.rms(sine(amplitude: 0.03)))
        precondition(medium > 0.2 && medium < 0.8, "voix normale : barres à mi-hauteur")
        precondition(AudioLevelMeter.rms(sine(amplitude: 0.5, channels: 2, interleaved: true, onlyLast: true)) > 0.3,
                     "stéréo entrelacée : le canal droit compte")
        precondition(AudioLevelMeter.rms(sine(amplitude: 0.5, channels: 2, onlyLast: true)) > 0.3,
                     "stéréo séparée : le canal droit compte")

        let meter = AudioLevelMeter()
        meter.feed(sine(amplitude: 0.001))
        meter.feed(sine(amplitude: 0.5))
        precondition(meter.take() > 0.95, "le son le plus fort depuis la dernière lecture")
        precondition(meter.take() == 0, "remis à zéro après lecture")

        let level = RecordingLevel()
        level.start(reading: meter, since: Date())
        let talking = Task.detached {
            for _ in 0..<10 {
                meter.feed(sine(amplitude: 0.5))
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await talking.value
        precondition(level.level > 0.5, "les barres montent quand on parle")
        try? await Task.sleep(for: .seconds(1.5))
        precondition(level.level == 0, "les barres redescendent au silence")
        precondition(level.elapsed > 1.5, "le chrono avance")
        level.stop()
        let frozen = level.elapsed
        try? await Task.sleep(for: .milliseconds(200))
        precondition(level.elapsed == frozen, "le chrono s’arrête avec l’enregistrement")
        print("RecordingLevelSmoke OK")
    }
}
