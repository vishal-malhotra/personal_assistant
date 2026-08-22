import EventKit
import Foundation

public enum EventKitError: LocalizedError {
    case calendarAccessDenied
    case reminderAccessDenied
    case invalidDateRange
    case saveFailed(String)
    case deletionFailed(String)
    case eventNotFound
    
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
        case .deletionFailed(let message):
            return "Failed to delete from EventKit: \(message)"
        case .eventNotFound:
            return "Event or reminder was not found."
        }
    }
}

/// Service for creating, querying, and managing Apple Calendar events and Reminders via EventKit.
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
    
    // MARK: - Calendar Query & Operations
    
    /// Fetches all calendar events within a given date range.
    public func fetchEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
    
    /// Fetches events scheduled for today.
    public func fetchEventsForToday() -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return fetchEvents(from: startOfDay, to: endOfDay)
    }
    
    /// Fetches events for the upcoming N days (e.g. next 7 days).
    public func fetchEventsForNextDays(_ days: Int = 7) -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: days, to: startOfDay) else {
            return []
        }
        return fetchEvents(from: startOfDay, to: endDate)
    }
    
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
    
    /// Deletes a specific calendar event by its identifier.
    public func deleteEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw EventKitError.eventNotFound
        }
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            throw EventKitError.deletionFailed(error.localizedDescription)
        }
    }
    
    /// Deletes all calendar events scheduled for a specific date (e.g. today).
    public func clearEvents(on date: Date) throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }
        let events = fetchEvents(from: startOfDay, to: endOfDay)
        var deletedCount = 0
        for event in events {
            try eventStore.remove(event, span: .thisEvent)
            deletedCount += 1
        }
        return deletedCount
    }
    
    // MARK: - Reminder Query & Operations
    
    /// Fetches incomplete reminders due within the upcoming N days.
    public func fetchUpcomingReminders(days: Int = 7) async -> [EKReminder] {
        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let list = reminders ?? []
                let calendar = Calendar.current
                guard let cutoff = calendar.date(byAdding: .day, value: days, to: Date()) else {
                    continuation.resume(returning: list)
                    return
                }
                
                let filtered = list.filter { reminder in
                    guard let dueComponents = reminder.dueDateComponents,
                          let dueDate = calendar.date(from: dueComponents) else {
                        return true // Include unscheduled tasks as well
                    }
                    return dueDate <= cutoff
                }
                continuation.resume(returning: filtered)
            }
        }
    }
    
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
    
    /// Deletes a specific reminder by its identifier.
    public func deleteReminder(identifier: String) throws {
        guard let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.eventNotFound
        }
        do {
            try eventStore.remove(item, commit: true)
        } catch {
            throw EventKitError.deletionFailed(error.localizedDescription)
        }
    }
}
