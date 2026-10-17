// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// One limit window as `/usage` reports it.
public struct UsageWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?
    /// The text after "resets", kept for display when it can't be read as a date.
    public var resetText: String?

    public init(usedPercent: Double, resetsAt: Date? = nil, resetText: String? = nil) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetText = resetText
    }

    public var leftPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

/// The two windows claudebar shows: the 5-hour session and the all-models week. Per-model weekly windows (Fable, and whatever else /usage lists) are ignored on purpose.
public struct UsageReport: Codable, Equatable, Sendable {
    public var session: UsageWindow?
    public var week: UsageWindow?

    public init(session: UsageWindow? = nil, week: UsageWindow? = nil) {
        self.session = session
        self.week = week
    }

    public var isEmpty: Bool { session == nil && week == nil }
}

/// Reads the text `claude -p /usage` prints. Claude Code gives these numbers in no other form, so this is the one place that depends on its wording:
///
///     Current session: 2% used · resets Sep 24 at 4:49pm (Europe/Madrid)
///     Current week (all models): 54% used · resets Sep 29 at 2:59am (Europe/Madrid)
///     Current week (Fable): 0% used · resets Sep 29 at 3am (Europe/Madrid)
public enum UsageParser {
    public static func parse(_ text: String, now: Date = Date()) -> UsageReport {
        var report = UsageReport()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let rest = line.removingPrefix("Current session:") {
                report.session = window(rest, now: now)
            } else if let rest = line.removingPrefix("Current week (all models):") ?? line.removingPrefix("Current week:") {
                report.week = window(rest, now: now)
            }
        }
        return report
    }

    /// "54% used · resets Sep 29 at 2:59am (Europe/Madrid)" -> 54% used, resetting at that moment.
    static func window(_ text: String, now: Date) -> UsageWindow? {
        guard let m = match(#"^\s*(\d+(?:\.\d+)?)\s*%\s*used\b(?:.*?\bresets\s+(.+?))?\s*$"#, text),
              let used = m[1].flatMap(Double.init) else { return nil }
        let resetText = m[2]
        return UsageWindow(usedPercent: used, resetsAt: resetText.flatMap { resetDate($0, now: now) }, resetText: resetText)
    }

    /// "Sep 29 at 2:59am (Europe/Madrid)", "Sep 29 at 3am (Europe/Madrid)" or a bare "4:49pm (Europe/Madrid)". The year is left out, so a date that lands well in the past belongs to next year (a weekly reset seen across New Year); a bare time already gone is tomorrow's.
    static func resetDate(_ text: String, now: Date) -> Date? {
        let pattern = #"^(?:([a-z]{3})[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?\s+at\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)?\s*(?:\(([^)]+)\))?$"#
        guard let m = match(pattern, text.trimmingCharacters(in: .whitespaces)),
              var hour = m[4].flatMap(Int.init) else { return nil }
        let minute = m[5].flatMap(Int.init) ?? 0
        if let meridiem = m[6]?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = m[7].flatMap(TimeZone.init(identifier:)) ?? .current
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute

        guard let monthText = m[1] else {
            guard let today = calendar.date(from: parts) else { return nil }
            return today < now.addingTimeInterval(-60) ? calendar.date(byAdding: .day, value: 1, to: today) : today
        }
        guard let month = months.firstIndex(of: monthText.lowercased()),
              let day = m[2].flatMap(Int.init) else { return nil }
        parts.month = month + 1
        parts.day = day
        if let year = m[3].flatMap(Int.init) { parts.year = year }
        guard let date = calendar.date(from: parts) else { return nil }
        if m[3] == nil, date < now.addingTimeInterval(-30 * 86_400) {
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
        return date
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Capture groups of the first case-insensitive match (index 0 is the whole match); nil for a group that took no part.
    static func match(_ pattern: String, _ text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map { i in
            Range(result.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}

extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
