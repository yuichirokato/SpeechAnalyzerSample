import SwiftUI
import SwiftData
import Speech
import AVFoundation

enum ManagerType: String, CaseIterable {
    case analyzer = "SpeechAnalyzer"
    case recognizer = "SFSpeechRecognizer"

    var displayName: String {
        switch self {
        case .analyzer:
            return "Speech Analyzer"
        case .recognizer:
            return "Speech Recognizer"
        }
    }
}

@available(iOS 26.0, *)
struct ContentView: View {
    @State private var analyzerManager = SpeechAnalyzerManager()
    @State private var recognizerManager = SpeechRecognizerManager()
    @State private var selectedManager: ManagerType = .analyzer
    
    private var isRecording: Bool {
        selectedManager == .analyzer 
            ? analyzerManager.isRecording 
            : recognizerManager.isRecording
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 現在選択されているマネージャーを表示
                Text("使用中: \(selectedManager.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top)
                
                // 音声認識結果を表示
                if selectedManager == .analyzer {
                    Text(analyzerManager.finalizedText + analyzerManager.volatileText)
                        .padding()
                } else {
                    Text(recognizerManager.recognizedText)
                        .padding()
                }

                // 音声入力開始/停止ボタン
                Button(action: {
                    if selectedManager == .analyzer {
                        if isRecording {
                            analyzerManager.stopAnalyzer()
                        } else {
                            analyzerManager.startAnalyzer()
                        }
                    } else {
                        if isRecording {
                            recognizerManager.stopRecognition()
                        } else {
                            recognizerManager.startRecognition()
                        }
                    }
                }) {
                    HStack {
                        // アイコンを状態に応じて切り替え
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30))
                        
                        // テキストを状態に応じて切り替え
                        Text(isRecording ? "停止" : "音声入力")
                            .font(.headline)
                    }
                    .foregroundColor(isRecording ? .red : .blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        isRecording 
                            ? Color.red.opacity(0.1) 
                            : Color.blue.opacity(0.1)
                    )
                    .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("音声認識")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(ManagerType.allCases, id: \.self) { managerType in
                            Button(action: {
                                // 現在録音中の場合は停止
                                if selectedManager == .analyzer && analyzerManager.isRecording {
                                    analyzerManager.stopAnalyzer()
                                } else if selectedManager == .recognizer && recognizerManager.isRecording {
                                    recognizerManager.stopRecognition()
                                }
                                
                                selectedManager = managerType
                            }) {
                                HStack {
                                    Text(managerType.displayName)
                                    if selectedManager == managerType {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
