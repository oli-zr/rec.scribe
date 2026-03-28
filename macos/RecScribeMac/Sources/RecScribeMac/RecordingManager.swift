import AVFoundation
import Foundation

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?

    func startRecording() throws {
        let tempURL = Self.tempRecordingURL
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: tempURL, settings: settings)
        recorder?.isMeteringEnabled = false
        recorder?.record()
        isRecording = true
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        return FileManager.default.fileExists(atPath: Self.tempRecordingURL.path) ? Self.tempRecordingURL : nil
    }

    static var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recscribe-temp-recording.m4a")
    }
}
