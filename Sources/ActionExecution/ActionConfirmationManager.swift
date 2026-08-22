import Foundation

public struct PendingEventAction: Identifiable, Equatable {
    public let id: String
    public var item: CalendarEventItem
    public var isSelected: Bool
    public var isSaved: Bool
    public var error: String?
    
    public init(item: CalendarEventItem, isSelected: Bool = true) {
        self.id = item.id
        self.item = item
        self.isSelected = isSelected
        self.isSaved = false
    }
}

public struct PendingReminderAction: Identifiable, Equatable {
    public let id: String
    public var item: ReminderItem
    public var isSelected: Bool
    public var isSaved: Bool
    public var error: String?
    
    public init(item: ReminderItem, isSelected: Bool = true) {
        self.id = item.id
        self.item = item
        self.isSelected = isSelected
        self.isSaved = false
    }
}

@MainActor
public final class ActionConfirmationManager: ObservableObject {
    @Published public var pendingEvents: [PendingEventAction] = []
    @Published public var pendingReminders: [PendingReminderAction] = []
    @Published public var isExecuting: Bool = false
    @Published public var executionFinished: Bool = false
    
    public init() {}
    
    /// Populates pending actions from the decoded LLM payload.
    public func load(payload: MeetingPayload) {
        self.pendingEvents = payload.calendarEvents.map { PendingEventAction(item: $0) }
        self.pendingReminders = payload.reminders.map { PendingReminderAction(item: $0) }
        self.isExecuting = false
        self.executionFinished = false
    }
    
    /// Commits all selected events and reminders to EventKit upon user confirmation.
    public func commitSelectedActions() async {
        isExecuting = true
        
        let eventKit = EventKitService.shared
        _ = await eventKit.requestCalendarAccess()
        _ = await eventKit.requestReminderAccess()
        
        // 1. Process Calendar Events
        for index in pendingEvents.indices where pendingEvents[index].isSelected && !pendingEvents[index].isSaved {
            let item = pendingEvents[index].item
            if let startDate = item.targetStartDate() {
                do {
                    _ = try eventKit.createCalendarEvent(
                        title: item.title,
                        startDate: startDate,
                        attendeeNames: item.attendees
                    )
                    pendingEvents[index].isSaved = true
                } catch {
                    pendingEvents[index].error = error.localizedDescription
                }
            } else {
                pendingEvents[index].error = "Invalid date/time format."
            }
        }
        
        // 2. Process Reminders
        for index in pendingReminders.indices where pendingReminders[index].isSelected && !pendingReminders[index].isSaved {
            let item = pendingReminders[index].item
            if let dueDate = item.targetDueDate() {
                do {
                    _ = try eventKit.createReminder(
                        title: item.title,
                        dueDate: dueDate
                    )
                    pendingReminders[index].isSaved = true
                } catch {
                    pendingReminders[index].error = error.localizedDescription
                }
            } else {
                pendingReminders[index].error = "Invalid date/time format."
            }
        }
        
        isExecuting = false
        executionFinished = true
    }
}
