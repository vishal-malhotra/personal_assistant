import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject private var speechService = SpeechRecognitionService.shared
    @ObservedObject private var transcriptStore = TranscriptStore.shared
    @ObservedObject private var modelDownloader = ModelDownloadManager.shared
    
    @State private var isRecordingViewPresented: Bool = false
    @State private var isProcessing: Bool = false
    @State private var activePayload: MeetingPayload?
    @State private var lastTranscript: String = ""
    @State private var showReviewSheet: Bool = false
    @State private var searchText: String = ""
    @State private var errorMessage: String?
    
    public init() {}
    
    private var filteredRecords: [MeetingRecord] {
        if searchText.isEmpty {
            return transcriptStore.records
        } else {
            return transcriptStore.records.filter {
                $0.payload.meetingSummary.localizedCaseInsensitiveContains(searchText) ||
                $0.rawTranscript.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: AI Model Engine Status & Downloader
                Section(header: Text("On-Device AI Engine")) {
                    if modelDownloader.isDownloaded {
                        HStack {
                            Image(systemName: "cpu.fill")
                                .foregroundColor(AssistantTheme.systemGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Neural LLM Active")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Llama 3.2 1B (Quantized Q4_K_M)")
                                    .font(.caption2)
                                    .foregroundColor(AssistantTheme.secondaryLabel)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AssistantTheme.systemGreen)
                        }
                    } else if modelDownloader.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Downloading Neural Model...")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Cancel") {
                                    modelDownloader.cancelDownload()
                                }
                                .font(.caption)
                                .foregroundColor(AssistantTheme.systemRed)
                            }
                            
                            ProgressView(value: modelDownloader.downloadProgress, total: 1.0)
                                .tint(AssistantTheme.systemBlue)
                            
                            Text(modelDownloader.progressStatusText)
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "bolt.shield")
                                    .foregroundColor(AssistantTheme.systemBlue)
                                Text("Dynamic Natural Language Active")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Text("Fast on-device parsing active. You can also download the full neural LLM for extended reasoning.")
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                            
                            Button(action: {
                                modelDownloader.startDownload()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download Llama 3.2 Model (750 MB)")
                                }
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(AssistantTheme.systemBlue.opacity(0.15))
                                .foregroundColor(AssistantTheme.systemBlue)
                                .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Section 2: Privacy Telemetry Note
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(AssistantTheme.systemGreen)
                        Text("All audio & transcripts processed 100% on-device. Zero data leaves this iPhone.")
                            .font(.footnote)
                            .foregroundColor(AssistantTheme.secondaryLabel)
                    }
                }
                
                // Section 3: Meetings List
                if filteredRecords.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 40))
                                .foregroundColor(AssistantTheme.secondaryLabel)
                                .padding(.top, 16)
                            
                            Text("No Recordings")
                                .font(.headline)
                                .foregroundColor(AssistantTheme.label)
                            
                            Text("Tap the red record button below to start a meeting transcription session.")
                                .font(.subheadline)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section(header: Text("All Meetings")) {
                        ForEach(filteredRecords) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.timestamp, style: .date)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(Int(record.durationSeconds))s")
                                        .font(.caption)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                }
                                
                                Text(record.payload.meetingSummary)
                                    .font(.subheadline)
                                    .foregroundColor(AssistantTheme.secondaryLabel)
                                    .lineLimit(2)
                                
                                if !record.payload.calendarEvents.isEmpty || !record.payload.reminders.isEmpty {
                                    HStack(spacing: 10) {
                                        if !record.payload.calendarEvents.isEmpty {
                                            Label("\(record.payload.calendarEvents.count) Events", systemImage: "calendar")
                                                .font(.caption2)
                                                .foregroundColor(AssistantTheme.systemBlue)
                                        }
                                        if !record.payload.reminders.isEmpty {
                                            Label("\(record.payload.reminders.count) Reminders", systemImage: "bell")
                                                .font(.caption2)
                                                .foregroundColor(AssistantTheme.systemOrange)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.activePayload = record.payload
                                self.lastTranscript = record.rawTranscript
                                self.showReviewSheet = true
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = filteredRecords[index]
                                transcriptStore.deleteRecord(id: item.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search meetings & transcripts")
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        
                        // Apple Voice Memos Style Red Circular Record Button
                        Button(action: handleStartRecording) {
                            ZStack {
                                Circle()
                                    .stroke(Color(uiColor: .systemGray4), lineWidth: 3)
                                    .frame(width: 64, height: 64)
                                
                                Circle()
                                    .fill(AssistantTheme.systemRed)
                                    .frame(width: 52, height: 52)
                            }
                        }
                        .accessibilityLabel("Record New Meeting")
                        
                        Spacer()
                    }
                }
            }
            .fullScreenCover(isPresented: $isRecordingViewPresented) {
                ActiveRecordingView(onStop: handleStopRecording)
            }
            .sheet(isPresented: $showReviewSheet) {
                if let payload = activePayload {
                    ActionReviewSheetView(
                        payload: payload,
                        rawTranscript: lastTranscript,
                        onDismiss: {
                            self.activePayload = nil
                        }
                    )
                }
            }
            .overlay {
                if isProcessing {
                    ProcessingOverlayView()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleStartRecording() {
        Task {
            let permissions = await SpeechRecognitionService.requestPermissions()
            guard permissions.micAuthorized && permissions.speechAuthorized else {
                errorMessage = "Microphone and Speech Recognition permissions are required."
                return
            }
            
            do {
                try speechService.startRecording()
                isRecordingViewPresented = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleStopRecording() {
        isRecordingViewPresented = false
        isProcessing = true
        
        let transcript = speechService.stopRecording()
        let duration = speechService.sessionDuration
        lastTranscript = transcript
        
        Task {
            do {
                let payload = try await ModelManager.shared.processTranscript(transcript)
                
                let record = MeetingRecord(
                    durationSeconds: duration,
                    rawTranscript: transcript,
                    payload: payload
                )
                TranscriptStore.shared.saveRecord(record)
                
                await MainActor.run {
                    self.activePayload = payload
                    self.isProcessing = false
                    self.showReviewSheet = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
