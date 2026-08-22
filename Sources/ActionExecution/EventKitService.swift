import EventKit
import Foundation

public enum EventKitError: LocalizedError {
    case calendarAccessDenied
    case reminderAccessDenied
    case invalidDateRange
    case saveFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            return "Calendar access was not granted by the user."
        case .reminderAccessDenied:
            return "Reminders access was not granted by the user."
        case .invalidDateRange:
            return "The provided start or end date is invalid."
        case .saveFailed(let message):
            return "Failed to save to EventKit: \(message)"
        }
    }
}

/// Service for creating Apple Calendar events and Reminders via EventKit.
public final class EventKitService {
    public static let shared = EventKitService()
    
    private let eventStore = EKEventStore()
    
    private init() {}
    
    // MARK: - Permissions
    
    public func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    public func requestReminderAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    // MARK: - Calendar Operations
    
    /// Checks for conflicting calendar events within a given time range.
    public func checkConflicts(start: Date, end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
    }
    
    /// Creates and saves a new event in the user's default calendar.
    public func createCalendarEvent(
        title: String,
        startDate: Date,
        durationMinutes: Double = 60.0,
        notes: String? = nil,
        attendeeNames: [String] = []
    ) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(durationMinutes * 60.0)
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        var notesCombined = notes ?? ""
        if !attendeeNames.isEmpty {
            notesCombined += "\nAttendees: \(attendeeNames.joined(separator: ", "))"
        }
        event.notes = notesCombined.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Reminder Operations
    
    /// Creates and saves a new reminder in the user's default Reminders list.
    public func createReminder(
        title: String,
        dueDate: Date,
        notes: String? = nil
    ) throws -> String {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        reminder.notes = notes
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.dueDateComponents = components
        reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        
        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }
}
