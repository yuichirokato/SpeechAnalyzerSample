import AVFoundation
import Foundation
import Speech

@Observable
final class SpeechRecognizerManager {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.ja)
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var recognitionTaskWrapper: Task<(), Error>?

    var recognizedText = ""
    var isRecording = false

    func startRecognition() {
        Task {
            do {
                guard await requestSpeechRecognizerPermission() else {
                    print("Speech recognition permission denied")
                    return
                }

                try await setupAudioSession()

                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

                guard let request = recognitionRequest else { return }
                request.shouldReportPartialResults = true

                await MainActor.run {
                    isRecording = true
                    recognizedText = ""
                }

                recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                    if let error = error {
                        print("recognition error: \(error.localizedDescription)")
                        Task { @MainActor in
                            self?.isRecording = false
                        }
                        return
                    }

                    if let result = result, !result.bestTranscription.formattedString.isEmpty {
                        Task { @MainActor in
                            self?.recognizedText = result.bestTranscription.formattedString
                        }
                    }
                }

                recognitionTaskWrapper = Task {
                    for try await buffer in try await audioBufferStream() {
                        recognitionRequest?.append(buffer)
                    }
                }
                
                try await recognitionTaskWrapper?.value
            } catch {
                print("recognition start failure: \(error)")
                await MainActor.run {
                    isRecording = false
                }
            }
        }
    }
    
    func stopRecognition() {
        Task {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            recognitionTaskWrapper?.cancel()
            recognitionTaskWrapper = nil
            
            stopAudioEngine()
            
            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
            
            await MainActor.run {
                isRecording = false
            }
        }
    }
}

// MARK: - AudioEngine
private extension SpeechRecognizerManager {
    func setupAudioSession() async throws {
        try audioSession.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func requestSpeechRecognizerPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                case .denied, .restricted, .notDetermined:
                    continuation.resume(returning: false)
                @unknown default:
                    continuation.resume(returning: false)
                }
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
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
    }
}
