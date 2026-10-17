// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// Display strings shared by the menu and the CLI.
public enum UsageFormat {
    /// "97% left"
    public static func left(_ window: UsageWindow) -> String {
        percent(window, mode: .left)
    }

    /// "97% left" or "3% used", as `mode` says.
    public static func percent(_ window: UsageWindow, mode: DisplayMode) -> String {
        "\(Int(mode.percent(window).rounded()))% \(mode.rawValue)"
    }

    /// Time until `date`, coarse: "4d 15h", "4h 51m", "12m", "now".
    public static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
        return "\(mins)m"
    }

    /// The reset moment in the viewer's own locale and time zone: "16:49" today, "tomorrow 09:00", else "Tue 29 Sep 02:59".
    public static func resetTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) \(time)"
    }

    /// "resets 16:49 · in 4h 51m", or the raw /usage text when its date couldn't be read.
    public static func resetLine(_ window: UsageWindow, now: Date = Date()) -> String? {
        if let date = window.resetsAt {
            return "resets \(resetTime(date, now: now)) · in \(countdown(to: date, from: now))"
        }
        return window.resetText.map { "resets \($0)" }
    }
}
