import EventKit
import Foundation
import Combine

public struct EventSummaryItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let timeString: String
    public let dateString: String
    
    public init(id: String, title: String, timeString: String, dateString: String) {
        self.id = id
        self.title = title
        self.timeString = timeString
        self.dateString = dateString
    }
}

public enum ChatActionCard: Equatable {
    case clearEvents(dateDescription: String, events: [EventSummaryItem], isCompleted: Bool)
    case createCalendarEvent(title: String, date: Date, isCompleted: Bool)
    case createReminder(title: String, dueDate: Date, isCompleted: Bool)
}

public struct ChatMessage: Identifiable, Equatable {
    public let id: UUID
    public let isUser: Bool
    public var text: String
    public let timestamp: Date
    public var actionCard: ChatActionCard?
    
    public init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        timestamp: Date = Date(),
        actionCard: ChatActionCard? = nil
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.actionCard = actionCard
    }
}

@MainActor
public final class AssistantChatEngine: ObservableObject {
    public static let shared = AssistantChatEngine()
    
    @Published public var messages: [ChatMessage] = []
    @Published public var isThinking: Bool = false
    
    private let eventKit = EventKitService.shared
    private let transcriptStore = TranscriptStore.shared
    
    public init() {
        // Welcome message with dynamic date
        let df = DateFormatter()
        df.dateStyle = .medium
        let todayStr = df.string(from: Date())
        
        messages = [
            ChatMessage(
                isUser: false,
                text: "Hello! I am your on-device AI assistant. Today is \(todayStr).\n\nYou can ask me:\n• \"What meetings do I have this week?\"\n• \"What are my reminders for today?\"\n• \"Clear my meetings for today\"\n• \"What did we discuss in our last meeting?\""
            )
        ]
    }
    
    /// Sends a user query and processes it dynamically using on-device context.
    public func sendQuery(_ userText: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 1. Append User Message
        messages.append(ChatMessage(isUser: true, text: trimmed))
        isThinking = true
        
        // 2. Request permissions for EventKit
        _ = await eventKit.requestCalendarAccess()
        _ = await eventKit.requestReminderAccess()
        
        // 3. Process query dynamically
        let response = await processQueryDynamically(trimmed)
        
        isThinking = false
        messages.append(response)
    }
    
    private func processQueryDynamically(_ query: String) async -> ChatMessage {
        let lower = query.lowercased()
        
        // Time formatters
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"
        
        // CASE 1: Clear / Delete Meetings for Today or specific date
        if lower.contains("clear") || lower.contains("cancel") || lower.contains("delete") {
            if lower.contains("today") || lower.contains("all meeting") {
                let todayEvents = eventKit.fetchEventsForToday()
                if todayEvents.isEmpty {
                    return ChatMessage(
                        isUser: false,
                        text: "You have no meetings scheduled for today to clear."
                    )
                } else {
                    let items = todayEvents.map {
                        EventSummaryItem(
                            id: $0.eventIdentifier ?? UUID().uuidString,
                            title: $0.title ?? "Untitled Event",
                            timeString: "\(timeFormatter.string(from: $0.startDate)) - \(timeFormatter.string(from: $0.endDate))",
                            dateString: "Today"
                        )
                    }
                    return ChatMessage(
                        isUser: false,
                        text: "I found \(todayEvents.count) meeting\(todayEvents.count > 1 ? "s" : "") scheduled for today. Would you like me to remove them from your Calendar?",
                        actionCard: .clearEvents(dateDescription: "Today", events: items, isCompleted: false)
                    )
                }
            }
        }
        
        // CASE 2: Query Meetings for Next 1 Week (7 Days)
        if lower.contains("week") || lower.contains("7 day") || lower.contains("next few day") || lower.contains("upcoming meeting") {
            let weekEvents = eventKit.fetchEventsForNextDays(7)
            let upcomingReminders = await eventKit.fetchUpcomingReminders(days: 7)
            
            var text = ""
            if weekEvents.isEmpty {
                text += "📅 **Calendar (Next 7 Days):**\nYou have no calendar events scheduled for the next 7 days.\n"
            } else {
                text += "📅 **Calendar (Next 7 Days):** (\(weekEvents.count) event\(weekEvents.count > 1 ? "s" : "")):\n"
                for (idx, event) in weekEvents.enumerated() {
                    let dateStr = dateFormatter.string(from: event.startDate)
                    let timeStr = timeFormatter.string(from: event.startDate)
                    let title = event.title ?? "Meeting"
                    text += "\(idx + 1). **\(title)** — \(dateStr) at \(timeStr)\n"
                }
            }
            
            text += "\n"
            if upcomingReminders.isEmpty {
                text += "⏰ **Reminders:**\nNo pending reminders due this week."
            } else {
                text += "⏰ **Pending Reminders:** (\(upcomingReminders.count) task\(upcomingReminders.count > 1 ? "s" : "")):\n"
                for (idx, rem) in upcomingReminders.enumerated() {
                    let title = rem.title ?? "Task"
                    if let comp = rem.dueDateComponents, let d = Calendar.current.date(from: comp) {
                        text += "\(idx + 1). \(title) *(Due: \(dateFormatter.string(from: d)))*\n"
                    } else {
                        text += "\(idx + 1). \(title)\n"
                    }
                }
            }
            
            return ChatMessage(isUser: false, text: text)
        }
        
        // CASE 3: Query Today's Schedule & Reminders
        if lower.contains("today") || lower.contains("schedule") {
            let todayEvents = eventKit.fetchEventsForToday()
            let reminders = await eventKit.fetchUpcomingReminders(days: 1)
            
            var text = ""
            if todayEvents.isEmpty {
                text += "📅 **Today's Meetings:**\nNo meetings scheduled for today.\n"
            } else {
                text += "📅 **Today's Meetings:** (\(todayEvents.count) event\(todayEvents.count > 1 ? "s" : "")):\n"
                for (idx, event) in todayEvents.enumerated() {
                    let timeStr = "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
                    text += "\(idx + 1). **\(event.title ?? "Meeting")** at \(timeStr)\n"
                }
            }
            
            text += "\n"
            if reminders.isEmpty {
                text += "⏰ **Reminders for Today:**\nNo reminders due today."
            } else {
                text += "⏰ **Reminders for Today:**\n"
                for (idx, rem) in reminders.enumerated() {
                    text += "\(idx + 1). \(rem.title ?? "Task")\n"
                }
            }
            
            return ChatMessage(isUser: false, text: text)
        }
        
        // CASE 4: Query Past Recorded Meetings & Discussion Memory
        if lower.contains("discuss") || lower.contains("meeting") || lower.contains("said") || lower.contains("last") || lower.contains("action item") || lower.contains("transcript") {
            let records = transcriptStore.records
            if records.isEmpty {
                return ChatMessage(
                    isUser: false,
                    text: "You haven't recorded any meetings yet. Tap the red record button on the Meetings tab to record your first session!"
                )
            }
            
            // Search records for matching keywords
            var matchingRecord = records.first
            let keywords = query.components(separatedBy: " ").filter { $0.count > 3 }
            for record in records {
                let textToSearch = "\(record.payload.meetingSummary) \(record.rawTranscript)".lowercased()
                if keywords.contains(where: { textToSearch.contains($0.lowercased()) }) {
                    matchingRecord = record
                    break
                }
            }
            
            if let record = matchingRecord {
                let recDate = dateFormatter.string(from: record.timestamp)
                var response = "📝 **From your meeting on \(recDate):**\n\n"
                response += "**Summary:** \(record.payload.meetingSummary)\n\n"
                
                if !record.payload.actionItems.isEmpty {
                    response += "**Action Items:**\n"
                    for item in record.payload.actionItems {
                        response += "• \(item)\n"
                    }
                }
                
                return ChatMessage(isUser: false, text: response)
            }
        }
        
        // CASE 5: General Natural Language Answer with dynamic context
        let todayEvents = eventKit.fetchEventsForToday()
        let eventCount = todayEvents.count
        let meetingCount = transcriptStore.records.count
        
        return ChatMessage(
            isUser: false,
            text: "You currently have **\(eventCount) meeting\(eventCount == 1 ? "" : "s")** scheduled for today and **\(meetingCount) recorded meeting\(meetingCount == 1 ? "" : "s")** in your offline archive.\n\nTry asking:\n• \"Check my meetings for the next 1 week\"\n• \"Clear my meetings for today\"\n• \"What are my open action items?\""
        )
    }
    
    // MARK: - Action Execution
    
    /// Executes the clearing of events when user taps "Confirm Delete" on a chat card.
    public func executeClearEventsCard(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              case .clearEvents(_, _, let isCompleted) = messages[idx].actionCard,
              !isCompleted else {
            return
        }
        
        do {
            let deletedCount = try eventKit.clearEvents(on: Date())
            messages[idx].actionCard = .clearEvents(dateDescription: "Today", events: [], isCompleted: true)
            messages.append(ChatMessage(
                isUser: false,
                text: "✓ Successfully cleared \(deletedCount) meeting\(deletedCount == 1 ? "" : "s") from your Apple Calendar."
            ))
        } catch {
            messages.append(ChatMessage(
                isUser: false,
                text: "Error clearing meetings: \(error.localizedDescription)"
            ))
        }
    }
}
