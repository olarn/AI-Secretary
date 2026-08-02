import Foundation

/// The time shown beside a message's name.
///
/// A conversation that ran over an afternoon and a conversation that ran over a
/// week look identical without one, and the thread is kept across launches.
public enum MessageTime {
    /// Time alone for anything sent today, date and time otherwise.
    ///
    /// A date on every line of a conversation you are having right now is noise;
    /// a bare time on a message from Tuesday is a lie by omission. Which of the
    /// two applies is decided against `now`, passed in rather than read from the
    /// clock so it can be checked.
    public static func label(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = calendar.isDate(date, inSameDayAs: now) ? .none : .short
        return formatter.string(from: date)
    }
}
