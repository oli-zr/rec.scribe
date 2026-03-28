import AVFoundation
import Foundation
import Speech

actor TranscriptionService {
    enum TranscriptionError: LocalizedError {
        case speechAuthorizationDenied
        case recognizerUnavailable
        case cannotReadAudio

        var errorDescription: String? {
            switch self {
            case .speechAuthorizationDenied:
                return "Spracherkennung ist nicht erlaubt. Erlaube den Zugriff in den Systemeinstellungen."
            case .recognizerUnavailable:
                return "Spracherkennung ist derzeit nicht verfügbar."
            case .cannotReadAudio:
                return "Audiodatei konnte nicht gelesen werden."
            }
        }
    }

    func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }

        let result = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }

        guard result == .authorized else {
            throw TranscriptionError.speechAuthorizationDenied
        }
    }

    func transcribe(audioURL: URL, localeIdentifier: String = "de-DE") async throws -> String {
        try await requestAuthorizationIfNeeded()

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.cannotReadAudio
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else { return }
                if result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
