import SwiftUI

public struct AssistantChatView: View {
    @ObservedObject private var chatEngine = AssistantChatEngine.shared
    @ObservedObject private var speechService = SpeechRecognitionService.shared
    
    @State private var inputText: String = ""
    @State private var isVoiceTyping: Bool = false
    @FocusState private var isInputFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(chatEngine.messages) { message in
                                ChatMessageBubble(message: message) {
                                    chatEngine.executeClearEventsCard(messageId: message.id)
                                }
                                .id(message.id)
                            }
                            
                            if chatEngine.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(AssistantTheme.systemBlue)
                                    Text("AI is checking your offline schedule...")
                                        .font(.footnote)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .id("ThinkingIndicator")
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                    }
                    .onChange(of: chatEngine.messages.count) {
                        if let lastMessage = chatEngine.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Quick Suggestion Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SuggestionChip(text: "📅 Next 7 Days") {
                            sendQuery("What meetings and reminders do I have for the next 1 week?")
                        }
                        SuggestionChip(text: "🗑️ Clear Today's Meetings") {
                            sendQuery("Clear all my meetings for today")
                        }
                        SuggestionChip(text: "⏰ Today's Schedule") {
                            sendQuery("What is my schedule for today?")
                        }
                        SuggestionChip(text: "📝 Past Meeting Decisions") {
                            sendQuery("What did we discuss in our last meeting?")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                
                Divider()
                
                // Input Bar with Text & Voice Input
                HStack(spacing: 10) {
                    // Voice Dictation Button
                    Button(action: toggleVoiceInput) {
                        Image(systemName: isVoiceTyping ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isVoiceTyping ? AssistantTheme.systemRed : AssistantTheme.systemBlue)
                            .padding(8)
                            .background(isVoiceTyping ? AssistantTheme.systemRed.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
                            .clipShape(Circle())
                    }
                    
                    // Text Field
                    TextField("Ask about schedule, clear meetings...", text: $inputText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .focused($isInputFocused)
                        .onSubmit {
                            handleSend()
                        }
                    
                    // Send Button
                    Button(action: handleSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : AssistantTheme.systemBlue)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("AI Assistant")
                            .font(.headline)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AssistantTheme.systemGreen)
                                .frame(width: 6, height: 6)
                            Text("100% Offline")
                                .font(.caption2)
                                .foregroundColor(AssistantTheme.secondaryLabel)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleSend() {
        let text = inputText
        inputText = ""
        isInputFocused = false
        sendQuery(text)
    }
    
    private func sendQuery(_ text: String) {
        Task {
            await chatEngine.sendQuery(text)
        }
    }
    
    private func toggleVoiceInput() {
        if isVoiceTyping {
            let spoken = speechService.stopRecording()
            if !spoken.isEmpty {
                inputText = spoken
            }
            isVoiceTyping = false
        } else {
            Task {
                let permissions = await SpeechRecognitionService.requestPermissions()
                guard permissions.micAuthorized && permissions.speechAuthorized else { return }
                
                do {
                    try speechService.startRecording()
                    isVoiceTyping = true
                } catch {
                    print("Error starting voice typing: \(error)")
                }
            }
        }
    }
}

// MARK: - Subviews

struct ChatMessageBubble: View {
    let message: ChatMessage
    let onConfirmAction: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 40)
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(AssistantTheme.systemBlue)
                    .font(.system(size: 14))
                    .padding(6)
                    .background(AssistantTheme.systemBlue.opacity(0.15))
                    .clipShape(Circle())
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(LocalizedStringKey(message.text))
                    .font(.system(size: 15))
                    .foregroundColor(message.isUser ? .white : AssistantTheme.label)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? AssistantTheme.systemBlue : Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Action Card if present
                if let actionCard = message.actionCard {
                    switch actionCard {
                    case .clearEvents(let desc, let events, let isCompleted):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "calendar.badge.minus")
                                    .foregroundColor(AssistantTheme.systemRed)
                                Text("Clear Meetings (\(desc))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            if !isCompleted {
                                ForEach(events) { ev in
                                    Text("• \(ev.title) (\(ev.timeString))")
                                        .font(.caption)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                }
                                
                                Button(action: onConfirmAction) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text("Confirm Delete from Calendar")
                                    }
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(AssistantTheme.systemRed)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .padding(.top, 4)
                            } else {
                                Text("✓ Cleared from Apple Calendar")
                                    .font(.caption)
                                    .foregroundColor(AssistantTheme.systemGreen)
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    default:
                        EmptyView()
                    }
                }
            }
            
            if !message.isUser {
                Spacer(minLength: 40)
            }
        }
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .foregroundColor(AssistantTheme.label)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
