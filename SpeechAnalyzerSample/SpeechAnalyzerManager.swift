import AVFoundation
import Foundation
import Speech
import SwiftUI

enum TranscriptionError: Error {
    case localeNotSupported
    case analyzerUnavailable
    case recordPermissionDenied
    case invalidAudioDataType
}

// マイクから入力された音声データを、SpeechAnalyzer が要求するフォーマットへ変換するためのクラス
class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none // Sacrifice quality of first samples in order to avoid any timestamp drift from source
        }

        guard let converter else {
            throw Error.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        var bufferProcessed = false

        let status = converter.convert(to: conversionBuffer, error: &nsError) { packetCount, inputStatusPointer in
            defer { bufferProcessed = true } // This closure can be called multiple times, but it only offers a single buffer.
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}

@Observable
final class SpeechAnalyzerManager {
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let speechTranscriber: SpeechTranscriber
    private let speechAnalyzer: SpeechAnalyzer
    private let bufferConverter = BufferConverter()

    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognitionTask: Task<(), Error>?
    private var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var analyzerFormat: AVAudioFormat?

    var volatileText: AttributedString = ""
    var finalizedText: AttributedString = ""
    var isRecording = false

    init() {
        let speechTranscriber = SpeechTranscriber(locale: Locale.ja,
                                                  transcriptionOptions: [],
                                                  reportingOptions: [.volatileResults],
                                                  attributeOptions: [.audioTimeRange])

        self.speechTranscriber = speechTranscriber
        self.speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
    }

    // MARK: - Speech Analyzer
    func setupAnalyzer() async throws {
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber])

        try await ensureModel(transcriber: speechTranscriber, locale: Locale.ja)

        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        recognitionTask = Task {
            do {
                for try await case let result in speechTranscriber.results {
                    let text = result.text

                    if result.isFinal {
                        finalizedText += text
                        volatileText = ""
                    } else {
                        volatileText = text
                        volatileText.foregroundColor = .white.opacity(0.8)
                    }
                }
            } catch {
                print("speech recognition failed")
            }
        }
    }

    func startAnalyzer() {
        Task {
            do {
                try await setupAnalyzer()

                guard let inputSequence, let inputBuilder else {
                    throw TranscriptionError.analyzerUnavailable
                }

                guard await requestRecordPermission() else {
                    throw TranscriptionError.recordPermissionDenied
                }

                try await activateAudioSession()

                try await speechAnalyzer.start(inputSequence: inputSequence)

                await MainActor.run {
                    isRecording = true
                }

                for await buffer in try await audioBufferStream() {
                    guard let analyzerFormat else {
                        throw TranscriptionError.invalidAudioDataType
                    }

                    let converted = try bufferConverter.convertBuffer(buffer, to: analyzerFormat)
                    let input = AnalyzerInput(buffer: converted)
                    inputBuilder.yield(input)
                }
            } catch {
                print("analyze failure: \(error)")
            }
        }
    }

    func stopAnalyzer() {
        Task {
            do {
                stopAudioEngine()

                try deactivateAudioSession()

                inputBuilder?.finish()

                try await speechAnalyzer.finalizeAndFinishThroughEndOfInput()

                recognitionTask?.cancel()
                recognitionTask = nil

                await MainActor.run {
                    isRecording = false
                }
            } catch {
                print("stop failure: \(error)")
            }
        }
    }
}

// MARK: - AudioEngine
private extension SpeechAnalyzerManager {
    func activateAudioSession() async throws {
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivateAudioSession() throws {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func requestRecordPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func audioBufferStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.audioBufferContinuation?.yield(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            self.audioBufferContinuation = continuation
        }
    }

    func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

// MARK: - Speech To Text Model Helpers
private extension SpeechAnalyzerManager {
    func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }

        let isInstalled = await installed(locale: locale)

        guard !isInstalled else { return }
        try await downloadIfNeeded(for: transcriber)
    }

    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
}
