// Transcription seam. Everything else talks to `Transcriber`; swap the
// implementation (whisper.cpp, Parakeet/CoreML, …) without touching the gesture code.

import AVFoundation
import Speech

protocol Transcriber: AnyObject {
    /// Identifies the engine in saved session metadata (for engine comparisons).
    var engineName: String { get }
    /// Live text (finalized + volatile) while recording. Called on the main queue.
    var onPartial: ((String) -> Void)? { get set }
    /// Fired once, on the main queue, when the first mic buffer arrives (start-latency probe).
    var onFirstAudio: (() -> Void)? { get set }
    /// Begin capturing mic audio immediately; if `recordingTo` is set, also write it as WAV.
    func start(recordingTo url: URL?)
    /// Stop capturing and return the final transcript.
    func stop() async -> String
    /// Abort without producing text.
    func cancel()
}

/// Custom vocabulary that biases recognition toward your jargon: a few generic defaults plus
/// one term per line in ~/Library/Application Support/Point/vocab.txt ("#" lines ignored).
func loadVocabulary() -> [String] {
    var words = ["Claude", "Claude Code", "ChatGPT", "GitHub", "TypeScript", "JavaScript",
                 "Python", "SwiftUI", "Xcode", "API", "MCP", "SQLite"]
    let url = POINT_DIR.appendingPathComponent("vocab.txt")
    if let text = try? String(contentsOf: url, encoding: .utf8) {
        words += text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
    return words
}

// ─── Apple on-device (macOS 26 SpeechAnalyzer) ──────────────────────────────

final class AppleTranscriber: Transcriber {
    // Resolved once at launch by prewarm(); a session before that skips transcription.
    private static var locale: Locale?
    private static var format: AVAudioFormat?

    static func prewarm() {
        Task {
            let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
                ?? Locale(identifier: "en-US")
            let module = SpeechTranscriber(locale: loc, preset: .progressiveTranscription)
            if await AssetInventory.status(forModules: [module]) != .installed {
                NSLog("Point: downloading speech model for %@", loc.identifier)
                do {
                    try await AssetInventory.assetInstallationRequest(supporting: [module])?
                        .downloadAndInstall()
                } catch {
                    NSLog("Point: speech model install failed: \(error)")
                    return
                }
            }
            format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
            locale = loc
            NSLog("Point: ✅ speech ready (%@)", loc.identifier)
        }
    }

    let engineName = "apple-speechtranscriber"
    var onPartial: ((String) -> Void)?
    var onFirstAudio: (() -> Void)?

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<String, Never>?
    private var recordFile: AVAudioFile?
    private var running = false

    func start(recordingTo url: URL?) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let locale = Self.locale, let target = Self.format else {
            NSLog("Point: transcription unavailable (mic permission or model not ready)")
            return
        }

        let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        continuation = cont

        // Record exactly what the model hears (its native format, usually 16 kHz mono)
        // so any engine can be re-scored later on identical audio.
        if let url {
            do {
                recordFile = try AVAudioFile(forWriting: url, settings: target.settings,
                                             commonFormat: target.commonFormat,
                                             interleaved: target.isInterleaved)
            } catch {
                NSLog("Point: can't record audio to \(url.path): \(error)")
            }
        }
        let file = recordFile

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: target) else { return }

        var sawAudio = false
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            if !sawAudio {
                sawAudio = true
                DispatchQueue.main.async { self?.onFirstAudio?() }
            }
            let ratio = target.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if err == nil, out.frameLength > 0 {
                try? file?.write(from: out)
                cont.yield(AnalyzerInput(buffer: out))
            }
        }

        do {
            try engine.start()
        } catch {
            NSLog("Point: audio engine failed: \(error)")
            input.removeTap(onBus: 0)
            cont.finish()
            return
        }
        running = true

        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            var finalized = ""
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        self?.emit(finalized)
                    } else {
                        self?.emit(finalized + text)
                    }
                }
            } catch {
                NSLog("Point: transcription error: \(error)")
            }
            return finalized
        }

        Task {
            let context = AnalysisContext()
            context.contextualStrings = [.general: loadVocabulary()]
            try? await analyzer.setContext(context)
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                NSLog("Point: analyzer start failed: \(error)")
            }
        }
    }

    private func emit(_ text: String) {
        let t = text
        DispatchQueue.main.async { [weak self] in self?.onPartial?(t) }
    }

    private func stopAudio() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        recordFile?.close()
        recordFile = nil
    }

    func stop() async -> String {
        guard running else { return "" }
        stopAudio()
        let analyzer = self.analyzer
        let results = self.resultsTask

        // Never hang the gesture on the model: give finalization 4s max.
        let finalize = Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            finalize.cancel()
            await analyzer?.cancelAndFinishNow()
        }
        _ = await finalize.value
        timeout.cancel()

        let text = await results?.value ?? ""
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        stopAudio()
        resultsTask?.cancel()
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
    }
}
