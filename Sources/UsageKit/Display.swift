// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// Whether percentages count down (what's left: a fresh week is 100%) or up (what's used: a fresh week is 0%). Set in Settings → General, or `"show"` in config.json; the CLI's `--left` / `--used` override it for one run.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case left
    case used

    /// The percentage this mode shows for `window`.
    public func percent(_ window: UsageWindow) -> Double {
        switch self {
        case .left: return window.leftPercent
        case .used: return 100 - window.leftPercent
        }
    }
}

/// How worried to be about a window, by what's left whichever way it's displayed: green while more than half is left, yellow down to a fifth, red below that.
public enum UsageLevel: Int, Comparable, Sendable {
    case ok
    case low
    case critical

    /// Above this much left is green.
    public static let okAbove: Double = 50
    /// Above this much left (and up to `okAbove`) is yellow; this much or less is red.
    public static let lowAbove: Double = 20

    public init(_ window: UsageWindow) {
        self.init(leftPercent: window.leftPercent)
    }

    public init(leftPercent: Double) {
        self = leftPercent > Self.okAbove ? .ok : leftPercent > Self.lowAbove ? .low : .critical
    }

    public static func < (a: UsageLevel, b: UsageLevel) -> Bool { a.rawValue < b.rawValue }
}
