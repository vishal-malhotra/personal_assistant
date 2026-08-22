import SwiftUI

public struct SettingsConfigView: View {
    @ObservedObject private var config = LLMConfigurationManager.shared
    @ObservedObject private var modelDownloader = ModelDownloadManager.shared
    @ObservedObject private var speechService = SpeechRecognitionService.shared
    @ObservedObject private var transcriptStore = TranscriptStore.shared
    
    @State private var showingResetAlert = false
    @State private var showingClearRecordsAlert = false
    @State private var showingPromptEditor = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: System Prompt Configuration
                Section(header: Text("LLM System Prompt")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customize how the on-device AI reasons, extracts decisions, and structures your meeting notes.")
                            .font(.caption)
                            .foregroundColor(AssistantTheme.secondaryLabel)
                        
                        TextEditor(text: $config.customSystemPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 140)
                            .padding(4)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .cornerRadius(8)
                        
                        HStack {
                            Text("Variables: {CURRENT_DATE}, {TIMEZONE}")
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                            
                            Spacer()
                            
                            Button("Reset Prompt") {
                                config.resetPromptToDefault()
                            }
                            .font(.caption)
                            .foregroundColor(AssistantTheme.systemBlue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section 2: Model Inference Hyperparameters
                Section(header: Text("Model Hyperparameters (A14 Bionic)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f", config.temperature))
                                .font(.subheadline)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                                .monospacedDigit()
                        }
                        Slider(value: $config.temperature, in: 0.0...1.0, step: 0.05)
                            .tint(AssistantTheme.systemBlue)
                        Text("Lower values (0.1–0.3) produce stricter JSON; higher values increase creativity.")
                            .font(.caption2)
                            .foregroundColor(AssistantTheme.secondaryLabel)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Top-P Sampling")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f", config.topP))
                                .font(.subheadline)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                                .monospacedDigit()
                        }
                        Slider(value: $config.topP, in: 0.1...1.0, step: 0.05)
                            .tint(AssistantTheme.systemBlue)
                    }
                    .padding(.vertical, 2)
                    
                    Picker("Max Output Tokens", selection: $config.maxTokens) {
                        Text("512 (Fast)").tag(512)
                        Text("1024 (Standard)").tag(1024)
                        Text("2048 (Extended)").tag(2048)
                    }
                }
                
                // Section 3: Speech & Acoustic Recognition
                Section(header: Text("Speech Recognition & Acoustics")) {
                    Picker("Speech Language", selection: $speechService.selectedLocaleIdentifier) {
                        ForEach(RecognitionLanguage.supported) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang.id)
                        }
                    }
                    
                    Toggle("Whisper Acoustic Refinement", isOn: $config.isWhisperRefinementEnabled)
                        .tint(AssistantTheme.systemGreen)
                    
                    Text("Runs a secondary on-device Whisper Metal pass on audio recordings for peak Hinglish & accent accuracy.")
                        .font(.caption2)
                        .foregroundColor(AssistantTheme.secondaryLabel)
                }
                
                // Section 4: On-Device Storage & Model Weights
                Section(header: Text("Local Model Storage")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Llama 3.2 1B Weights")
                                .font(.subheadline)
                            Text(modelDownloader.isDownloaded ? "750 MB (Cached on device)" : "Not downloaded")
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                        }
                        Spacer()
                        if modelDownloader.isDownloaded {
                            Button("Delete", role: .destructive) {
                                modelDownloader.deleteModel(type: .llama)
                            }
                            .font(.caption)
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Whisper Base Weights")
                                .font(.subheadline)
                            Text(modelDownloader.isWhisperDownloaded ? "142 MB (Cached on device)" : "Not downloaded")
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                        }
                        Spacer()
                        if modelDownloader.isWhisperDownloaded {
                            Button("Delete", role: .destructive) {
                                modelDownloader.deleteModel(type: .whisper)
                            }
                            .font(.caption)
                        }
                    }
                }
                
                // Section 5: Data & Privacy Reset
                Section(header: Text("Data & Factory Reset")) {
                    Button(role: .destructive, action: { showingClearRecordsAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Meeting History (\(transcriptStore.records.count) Records)")
                        }
                    }
                    .disabled(transcriptStore.records.isEmpty)
                    
                    Button("Reset All Settings to Default") {
                        showingResetAlert = true
                    }
                    .foregroundColor(AssistantTheme.systemBlue)
                }
            }
            .navigationTitle("Configuration")
            .alert("Clear All Meetings?", isPresented: $showingClearRecordsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    for record in transcriptStore.records {
                        transcriptStore.deleteRecord(id: record.id)
                    }
                }
            } message: {
                Text("This permanently deletes all encrypted transcripts and meeting records from this iPhone.")
            }
            .alert("Reset Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    config.resetAllToDefaults()
                }
            } message: {
                Text("This resets the system prompt, temperature, and tokens back to factory defaults.")
            }
        }
    }
}
