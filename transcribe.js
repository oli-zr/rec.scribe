/**
 * transcribe.js – Whisper Worker verwalten + Audio dekodieren
 *
 * Flow:
 *  1. Audio-Blob (webm) → AudioContext → Float32Array @ 16 kHz
 *  2. Float32Array per Transferable an Worker übergeben (kein Kopieren)
 *  3. Worker schickt Status-Updates + finales Transkript zurück
 */

let worker = null;
let workerConfiguredRoot = null;

const PREFERRED_AUDIO_MIME_TYPE = 'audio/webm;codecs=opus';
const FALLBACK_AUDIO_MIME_TYPE = 'audio/webm';
const NORMALIZED_AUDIO_BITS_PER_SECOND = 24000;

function ensureWorker() {
  if (!worker) {
    // Module Worker: Transformers.js kann ESM-Imports nutzen
    worker = new Worker('./worker.js', { type: 'module' });
  }
  return worker;
}

function isPreferredAudioBlob(blob) {
  const mimeType = blob?.type?.split(';', 1)[0]?.trim()?.toLowerCase();
  return mimeType === 'audio/webm';
}

function getPreferredRecorderMimeType() {
  if (typeof MediaRecorder === 'undefined') return null;
  if (MediaRecorder.isTypeSupported(PREFERRED_AUDIO_MIME_TYPE)) return PREFERRED_AUDIO_MIME_TYPE;
  if (MediaRecorder.isTypeSupported(FALLBACK_AUDIO_MIME_TYPE)) return FALLBACK_AUDIO_MIME_TYPE;
  return null;
}

async function decodeAudioToBuffer(blob) {
  const arrayBuffer = await blob.arrayBuffer();
  const audioCtx = new AudioContext();

  try {
    return await audioCtx.decodeAudioData(arrayBuffer);
  } finally {
    await audioCtx.close();
  }
}

export async function normalizeAudioBlob(blob) {
  if (isPreferredAudioBlob(blob)) return blob;

  const recorderMimeType = getPreferredRecorderMimeType();
  if (!recorderMimeType) return blob;

  const audioBuffer = await decodeAudioToBuffer(blob);
  const audioCtx = new AudioContext();
  const source = audioCtx.createBufferSource();
  const destination = audioCtx.createMediaStreamDestination();
  const recorder = new MediaRecorder(destination.stream, {
    mimeType: recorderMimeType,
    audioBitsPerSecond: NORMALIZED_AUDIO_BITS_PER_SECOND,
  });
  const chunks = [];

  source.buffer = audioBuffer;
  source.connect(destination);

  return new Promise((resolve, reject) => {
    const cleanup = async () => {
      source.disconnect();
      destination.disconnect();
      if (audioCtx.state !== 'closed') await audioCtx.close().catch(() => {});
    };

    recorder.ondataavailable = (event) => {
      if (event.data?.size) chunks.push(event.data);
    };

    recorder.onerror = async () => {
      await cleanup();
      reject(recorder.error || new Error('Audio-Konvertierung fehlgeschlagen.'));
    };

    recorder.onstop = async () => {
      const normalizedBlob = chunks.length > 0
        ? new Blob(chunks, { type: recorder.mimeType || recorderMimeType })
        : blob;
      await cleanup();
      resolve(normalizedBlob);
    };

    source.onended = () => {
      if (recorder.state !== 'inactive') recorder.stop();
    };

    audioCtx.resume()
      .then(() => {
        recorder.start();
        source.start(0);
      })
      .catch(async (error) => {
        await cleanup();
        reject(error);
      });
  });
}

export async function configureModelCache(rootDirHandle) {
  const w = ensureWorker();
  if (rootDirHandle === workerConfiguredRoot) return;

  await new Promise((resolve, reject) => {
    const handleMessage = ({ data }) => {
      if (data.type === 'cache-configured') {
        cleanup();
        workerConfiguredRoot = rootDirHandle;
        resolve();
      } else if (data.type === 'cache-error') {
        cleanup();
        reject(new Error(data.message));
      }
    };

    const handleError = (err) => {
      cleanup();
      reject(err instanceof Error ? err : new Error('Worker-Konfiguration fehlgeschlagen.'));
    };

    const cleanup = () => {
      w.removeEventListener('message', handleMessage);
      w.removeEventListener('error', handleError);
    };

    w.addEventListener('message', handleMessage);
    w.addEventListener('error', handleError, { once: true });
    w.postMessage({ type: 'configure-cache', rootDirHandle });
  });
}

/**
 * Audio-Blob dekodieren → Float32Array @ 16 kHz (Whisper-Eingangsformat)
 * @param {Blob} blob
 * @returns {Promise<Float32Array>}
 */
export async function decodeAudioToFloat32(blob) {
  const audioBuffer = await decodeAudioToBuffer(blob);
  const offlineCtx = new OfflineAudioContext(1, Math.ceil(audioBuffer.duration * 16000), 16000);
  const source = offlineCtx.createBufferSource();

  source.buffer = audioBuffer;
  source.connect(offlineCtx.destination);
  source.start(0);

  const renderedBuffer = await offlineCtx.startRendering();

  // Erster Kanal (Mono) als Float32Array zurückgeben
  return renderedBuffer.getChannelData(0);
}

/**
 * Transkription starten
 *
 * @param {Blob}     audioBlob   - Aufnahme-Blob (webm/wav/mp3)
 * @param {'small'|'medium'} modelSize
 * @param {FileSystemDirectoryHandle | null} rootDirHandle
 * @param {function} onStatus    - (status: string, extra?: object) => void
 *   Mögliche Status-Werte:
 *     'decoding'    – Audio wird dekodiert
 *     'loading'     – Whisper-Modell lädt (inkl. Download beim 1. Mal)
 *     'transcribing'– Transkription läuft
 *     'done'        – fertig (text kommt über Promise)
 *     'error'       – Fehler
 *
 * @returns {Promise<string>} Transkriptions-Text
 */
export function transcribeAudio(audioBlob, modelSize, rootDirHandle, onStatus) {
  return new Promise(async (resolve, reject) => {
    let w;

    try {
      onStatus?.('decoding');
      const audioData = await decodeAudioToFloat32(audioBlob);

      w = ensureWorker();

      // Nachrichten-Handler für diesen Job
      const handleMessage = ({ data }) => {
        switch (data.type) {
          case 'status':
            onStatus?.(data.value);
            break;

          case 'download':
            // Download-Fortschritt weiterleiten
            onStatus?.('loading', data.progress);
            break;

          case 'result':
            w.removeEventListener('message', handleMessage);
            onStatus?.('done');
            resolve(data.text);
            break;

          case 'error':
            w.removeEventListener('message', handleMessage);
            onStatus?.('error');
            reject(new Error(data.message));
            break;
        }
      };

      w.addEventListener('message', handleMessage);

      // Nur den Buffer übertragen und im Worker als Float32Array rekonstruieren.
      // Das vermeidet Struktur-/Typ-Probleme beim structured clone.
      const transferBuffer = audioData.buffer;
      w.postMessage(
        { type: 'transcribe', audioBuffer: transferBuffer, sampleRate: 16000, modelSize, rootDirHandle },
        [transferBuffer]
      );

    } catch (err) {
      onStatus?.('error');
      reject(err);
    }
  });
}

/**
 * Worker vorab initialisieren (optional, für schnelleren Start).
 * Wird im Hintergrund gestartet ohne Transkription.
 */
export async function warmUpWorker(rootDirHandle = null) {
  ensureWorker();
  if (rootDirHandle) {
    await configureModelCache(rootDirHandle);
  }
}
