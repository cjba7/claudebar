// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

#if DEBUG
import Foundation
import UsageKit

/// Development aid (`make snapshot DEMO=1`): with `CLAUDEBAR_DEMO=1` the debug build shows three made-up accounts instead of probing `claude`, so screenshots carry no real emails.
@MainActor
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.environment["CLAUDEBAR_DEMO"] == "1" }

    static func load(into store: UsageStore) {
        let now = Date()
        func account(_ id: String, _ name: String, _ email: String, _ plan: String, session: Double, week: Double, sessionIn: Double, weekIn: Double) -> (Account, AccountUsage) {
            let auth = AuthStatus(loggedIn: true, email: email, orgId: id, subscriptionType: plan)
            let report = UsageReport(
                session: UsageWindow(usedPercent: session, resetsAt: now.addingTimeInterval(sessionIn)),
                week: UsageWindow(usedPercent: week, resetsAt: now.addingTimeInterval(weekIn)))
            return (Account(id: id, name: name, configDir: "~/.claude-accounts/\(id)"),
                    AccountUsage(auth: auth, report: report, problem: nil))
        }
        let rows = [
            account("personal", "Personal", "me@example.com", "max", session: 12, week: 34, sessionIn: 3 * 3600 + 1260, weekIn: 4 * 86_400 + 7200),
            account("work", "Work", "me@work.example", "max", session: 61, week: 72, sessionIn: 1 * 3600 + 900, weekIn: 2 * 86_400 + 50_400),
            account("side", "Side project", "me@side.example", "pro", session: 88, week: 0, sessionIn: 2280, weekIn: 6 * 86_400 + 36_000),
        ]
        store.loadDemo(accounts: rows.map(\.0), usage: Dictionary(uniqueKeysWithValues: rows.map { ($0.0.id, $0.1) }))
    }
}
#endif
