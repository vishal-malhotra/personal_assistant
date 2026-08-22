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
                // Section 1: Meeting Summary
                Section(header: Text("Summary")) {
                    Text(payload.meetingSummary)
                        .font(.body)
                        .foregroundColor(AssistantTheme.label)
                }
                
                // Section 2: Action Items
                if !payload.actionItems.isEmpty {
                    Section(header: Text("Key Action Items")) {
                        ForEach(payload.actionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(AssistantTheme.systemBlue)
                                    .padding(.top, 2)
                                Text(item)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                // Section 3: Calendar Events (EventKit)
                if !confirmationManager.pendingEvents.isEmpty {
                    Section(header: Text("Calendar Events")) {
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
                                        Text("✓ Added to Calendar")
                                            .font(.caption)
                                            .foregroundColor(AssistantTheme.systemGreen)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Section 4: Reminders (EventKit)
                if !confirmationManager.pendingReminders.isEmpty {
                    Section(header: Text("Reminders")) {
                        ForEach($confirmationManager.pendingReminders) { $reminder in
                            Toggle(isOn: $reminder.isSelected) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reminder.item.title)
                                        .font(.headline)
                                    
                                    Text("Due: \(reminder.item.dueDate) at \(reminder.item.time)")
                                        .font(.subheadline)
                                        .foregroundColor(AssistantTheme.secondaryLabel)
                                    
                                    if reminder.isSaved {
                                        Text("✓ Added to Reminders")
                                            .font(.caption)
                                            .foregroundColor(AssistantTheme.systemGreen)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review & Save")
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
                    .disabled(confirmationManager.isExecuting)
                }
            }
            .onAppear {
                confirmationManager.load(payload: payload)
            }
        }
    }
}
