import AVFoundation

/// Records the default microphone to a small mono AAC file and exposes a live input level.
final class Recorder {
    private var recorder: AVAudioRecorder?
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("openwhisper-recording.m4a")

    func start() throws {
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
    }

    /// Current input level in 0...1.
    func level() -> CGFloat {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0) // -160...0
        let normalized = (db + 50) / 45
        return CGFloat(min(max(normalized, 0), 1))
    }

    /// Stops recording and returns the recorded duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        guard let recorder else { return 0 }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return duration
    }

    func discard() {
        stop()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum RecorderError: LocalizedError {
    case couldNotStart
    var errorDescription: String? { "Couldn't start the microphone" }
}
