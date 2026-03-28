# RecScribeMac (SwiftUI)

Diese macOS-Version liegt bewusst in einem separaten Ordner und nutzt die Standard-Apple-Designsprache (SwiftUI, NavigationSplitView, Form, Toolbar).

## Features

- Audio-Dateien importieren (`.audio` über `fileImporter`)
- Direktaufnahme via Mikrofon
- Sitzungsliste mit Suche
- Detailansicht mit Titel, Transkript und Notizen
- Lokale Persistenz in `~/Library/Application Support/RecScribeMac/`
- Transkription über Apple Speech Framework (`SFSpeechRecognizer`)

## Projekt öffnen

1. Ordner `macos/RecScribeMac` in Xcode als Swift Package öffnen.
2. Executable `RecScribeMac` ausführen.

## Hinweise

- Für Audioaufnahme und Transkription sind Systemberechtigungen nötig (Mikrofon / Speech Recognition).
- Die Sprachtranskription verwendet standardmäßig Locale `de-DE`.
