import Foundation

enum TranscriptStatus: String, Codable, CaseIterable {
    case idle
    case transcribing
    case done
    case error

    var localizedLabel: String {
        switch self {
        case .idle: return "Bereit"
        case .transcribing: return "Transkribiert…"
        case .done: return "Fertig"
        case .error: return "Fehler"
        }
    }
}

struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date
    var transcriptStatus: TranscriptStatus
    var transcript: String
    var notes: String
    var audioFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        transcriptStatus: TranscriptStatus = .idle,
        transcript: String = "",
        notes: String = "",
        audioFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.transcriptStatus = transcriptStatus
        self.transcript = transcript
        self.notes = notes
        self.audioFileName = audioFileName
    }
}
