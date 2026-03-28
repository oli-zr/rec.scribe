import AVKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    @StateObject private var recordingManager = RecordingManager()
    private let transcriptionService = TranscriptionService()

    @State private var selectedSessionID: Session.ID?
    @State private var searchText = ""
    @State private var alertMessage: String?
    @State private var isImporting = false
    @State private var player: AVPlayer?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Audio importieren", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                Button(recordingManager.isRecording ? "Stop" : "Aufnehmen", systemImage: recordingManager.isRecording ? "stop.circle" : "record.circle") {
                    toggleRecording()
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let first = urls.first else { return }
                importAudio(from: first)
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
        .alert("Hinweis", isPresented: .constant(alertMessage != nil), actions: {
            Button("OK") { alertMessage = nil }
        }, message: {
            Text(alertMessage ?? "")
        })
    }

    private var filteredSessions: [Session] {
        if searchText.isEmpty { return sessionStore.sessions }
        return sessionStore.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.transcript.localizedCaseInsensitiveContains(searchText)
            || $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedSessionID) {
            ForEach(filteredSessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.headline)
                    Text(session.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.transcriptStatus.localizedLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .tag(session.id)
                .contextMenu {
                    Button(role: .destructive) {
                        deleteSession(session)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Sitzungen durchsuchen")
        .navigationTitle("RecScribe")
    }

    @ViewBuilder
    private var detailView: some View {
        if let session = selectedSession {
            SessionDetailView(
                session: session,
                audioURL: sessionStore.audioURL(for: session),
                onChange: { updated in
                    sessionStore.update(updated)
                },
                onTranscribe: {
                    await transcribe(session)
                },
                onPlay: { url in
                    player = AVPlayer(url: url)
                    player?.play()
                }
            )
            .padding()
        } else {
            ContentUnavailableView(
                "Noch keine Sitzung ausgewählt",
                systemImage: "waveform.badge.mic",
                description: Text("Importiere eine Audiodatei oder nimm direkt eine neue Aufnahme auf.")
            )
        }
    }

    private var selectedSession: Session? {
        sessionStore.sessions.first(where: { $0.id == selectedSessionID })
    }

    private func importAudio(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let created = try sessionStore.addImportedAudio(fileURL: url)
            selectedSessionID = created.id
        } catch {
            alertMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func deleteSession(_ session: Session) {
        do {
            try sessionStore.remove(session)
            if selectedSessionID == session.id {
                selectedSessionID = sessionStore.sessions.first?.id
            }
        } catch {
            alertMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func toggleRecording() {
        if recordingManager.isRecording {
            guard let fileURL = recordingManager.stopRecording() else {
                alertMessage = "Aufnahme konnte nicht gespeichert werden."
                return
            }
            do {
                let title = "Aufnahme \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                let created = try sessionStore.addRecording(fileURL: fileURL, title: title)
                selectedSessionID = created.id
            } catch {
                alertMessage = "Aufnahme speichern fehlgeschlagen: \(error.localizedDescription)"
            }
        } else {
            do {
                try recordingManager.startRecording()
            } catch {
                alertMessage = "Aufnahme starten fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    private func transcribe(_ session: Session) async {
        guard let url = sessionStore.audioURL(for: session) else {
            await MainActor.run {
                alertMessage = "Keine Audiodatei für diese Sitzung gefunden."
            }
            return
        }

        await MainActor.run {
            var updating = session
            updating.transcriptStatus = .transcribing
            sessionStore.update(updating)
        }

        do {
            let transcript = try await transcriptionService.transcribe(audioURL: url)
            await MainActor.run {
                var updating = session
                updating.transcript = transcript
                updating.transcriptStatus = .done
                sessionStore.update(updating)
            }
        } catch {
            await MainActor.run {
                var updating = session
                updating.transcriptStatus = .error
                sessionStore.update(updating)
                alertMessage = "Transkription fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }
}

private struct SessionDetailView: View {
    @State var session: Session
    let audioURL: URL?
    let onChange: (Session) -> Void
    let onTranscribe: () async -> Void
    let onPlay: (URL) -> Void

    var body: some View {
        Form {
            Section("Sitzung") {
                TextField("Titel", text: $session.title)
                    .onChange(of: session.title) { _, _ in
                        onChange(session)
                    }
                LabeledContent("Status") {
                    Text(session.transcriptStatus.localizedLabel)
                }
            }

            Section("Transkript") {
                TextEditor(text: $session.transcript)
                    .font(.body)
                    .frame(minHeight: 180)
                    .onChange(of: session.transcript) { _, _ in
                        if session.transcriptStatus == .idle { session.transcriptStatus = .done }
                        onChange(session)
                    }
                Button("Transkribieren") {
                    Task { await onTranscribe() }
                }
                .disabled(audioURL == nil)
            }

            Section("Notizen") {
                TextEditor(text: $session.notes)
                    .font(.body)
                    .frame(minHeight: 180)
                    .onChange(of: session.notes) { _, _ in
                        onChange(session)
                    }
            }

            if let audioURL {
                Section("Audio") {
                    Text(audioURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Abspielen") {
                        onPlay(audioURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
