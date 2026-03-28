import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var baseDirectory: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RecScribeMac", isDirectory: true)
    }

    private var sessionsFileURL: URL {
        baseDirectory.appendingPathComponent("sessions.json")
    }

    private var recordingsDirectory: URL {
        baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    func load() {
        do {
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

            guard fm.fileExists(atPath: sessionsFileURL.path) else {
                sessions = []
                return
            }

            let data = try Data(contentsOf: sessionsFileURL)
            sessions = try decoder.decode([Session].self, from: data)
                .sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("SessionStore load failed: \(error)")
            sessions = []
        }
    }

    func addImportedAudio(fileURL: URL) throws -> Session {
        let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = recordingsDirectory.appendingPathComponent(fileName)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: fileURL, to: destination)

        let title = fileURL.deletingPathExtension().lastPathComponent
        let session = Session(title: title, audioFileName: fileName)
        sessions.insert(session, at: 0)
        try persist()
        return session
    }

    func addRecording(fileURL: URL, title: String) throws -> Session {
        let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = recordingsDirectory.appendingPathComponent(fileName)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: fileURL, to: destination)

        let session = Session(title: title, audioFileName: fileName)
        sessions.insert(session, at: 0)
        try persist()
        return session
    }

    func remove(_ session: Session) throws {
        sessions.removeAll { $0.id == session.id }
        if let fileName = session.audioFileName {
            let audioURL = recordingsDirectory.appendingPathComponent(fileName)
            if fm.fileExists(atPath: audioURL.path) {
                try fm.removeItem(at: audioURL)
            }
        }
        try persist()
    }

    func update(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        try? persist()
    }

    func audioURL(for session: Session) -> URL? {
        guard let fileName = session.audioFileName else { return nil }
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func persist() throws {
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsFileURL, options: .atomic)
    }
}
