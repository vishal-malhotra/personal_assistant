import SwiftUI

public struct ActionReviewSheetView: View {
    let payload: MeetingPayload
    let rawTranscript: String
    let onDismiss: () -> Void
    
    @StateObject private var confirmationManager = ActionConfirmationManager()
    @Environment(\.dismiss) private var dismiss
    
    public init(payload: MeetingPayload, rawTranscript: String, onDismiss: @escaping () -> Void) {
        self.payload = payload
        self.rawTranscript = rawTranscript
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 0: Complete Spoken Transcript
                Section(header: Text("Full Meeting Transcript")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rawTranscript.isEmpty ? "No transcript captured." : rawTranscript)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(AssistantTheme.label)
                            .lineSpacing(3)
                            .padding(.vertical, 4)
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                UIPasteboard.general.string = rawTranscript
                            }) {
                                Label("Copy Transcript", systemImage: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(AssistantTheme.systemBlue)
                            }
                        }
                    }
                }
                
                // Section 1: Detailed Meeting Summary
                Section(header: Text("Discussion Summary")) {
                    Text(payload.meetingSummary)
                        .font(.body)
                        .foregroundColor(AssistantTheme.label)
                        .lineSpacing(4)
                }
                
                // Section 2: Key Decisions
                if !payload.keyDecisions.isEmpty {
                    Section(header: Text("Key Decisions")) {
                        ForEach(payload.keyDecisions, id: \.self) { decision in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(AssistantTheme.systemGreen)
                                    .padding(.top, 2)
                                Text(decision)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                
                // Section 3: Speaker 1 & Speaker 2 Dialogue Breakdown
                if !payload.dialogueTurns.isEmpty {
                    Section(header: Text("Speaker Breakdown")) {
                        ForEach(payload.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(turn.speaker.contains("1") || turn.speaker.lowercased().contains("vishal") ? AssistantTheme.systemBlue : AssistantTheme.systemOrange)
                                    Text(turn.speaker)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(turn.speaker.contains("1") || turn.speaker.lowercased().contains("vishal") ? AssistantTheme.systemBlue : AssistantTheme.systemOrange)
                                }
                                Text(turn.text)
                                    .font(.subheadline)
                                    .foregroundColor(AssistantTheme.label)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                
                // Section 4: Key Action Items
                if !payload.actionItems.isEmpty {
                    Section(header: Text("Action Items")) {
                        ForEach(payload.actionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checklist")
                                    .foregroundColor(AssistantTheme.systemBlue)
                                    .padding(.top, 2)
                                Text(item)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                // Section 5: Calendar Events (EventKit)
                if !confirmationManager.pendingEvents.isEmpty {
                    Section(header: Text("Calendar Events (\(confirmationManager.pendingEvents.count))")) {
                        ForEach($confirmationManager.pendingEvents) { $event in
                            Toggle(isOn: $event.isSelected) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.item.title)
                                        .font(.headline)
                                    
                                    Text("\(event.item.date) at \(event.item.time)")
                                        .font(.subheadline)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                    
                                    if !event.item.attendees.isEmpty {
                                        Text("Attendees: \(event.item.attendees.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(AssistantTheme.secondaryLabel)
                                    }
                                    
                                    if event.isSaved {
                                        Text("✓ Added to Apple Calendar")
                                            .font(.caption)
                                            .foregroundColor(AssistantTheme.systemGreen)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Section 6: Reminders (EventKit)
                if !confirmationManager.pendingReminders.isEmpty {
                    Section(header: Text("Reminders (\(confirmationManager.pendingReminders.count))")) {
                        ForEach($confirmationManager.pendingReminders) { $reminder in
                            Toggle(isOn: $reminder.isSelected) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reminder.item.title)
                                        .font(.headline)
                                    
                                    Text("Due: \(reminder.item.dueDate) at \(reminder.item.time)")
                                        .font(.subheadline)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                    
                                    if reminder.isSaved {
                                        Text("✓ Added to Apple Reminders")
                                            .font(.caption)
                                            .foregroundColor(AssistantTheme.systemGreen)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meeting Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        Task {
                            await confirmationManager.commitSelectedActions()
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            onDismiss()
                            dismiss()
                        }
                    }) {
                        if confirmationManager.isExecuting {
                            ProgressView()
                        } else {
                            Text(confirmationManager.executionFinished ? "Done" : "Add to iOS")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(confirmationManager.isExecuting || (confirmationManager.pendingEvents.isEmpty && confirmationManager.pendingReminders.isEmpty))
                }
            }
            .onAppear {
                confirmationManager.load(payload: payload)
            }
        }
    }
}
