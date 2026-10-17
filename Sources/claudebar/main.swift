// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation
import UsageKit

// claudebar CLI: every configured account's 5-hour and weekly limits, from the same probe as the menu-bar app.

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("claudebar: \(message)\n".utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    let configPath = (try? Paths.configURL).map { Paths.abbreviateHome($0.path) } ?? "config.json"
    print("""
        usage: claudebar [--json] [--left | --used]

        Shows the 5-hour session and weekly limit on each account in \(configPath).
          --left   percent remaining (a fresh week is 100%)
          --used   percent used (a fresh week is 0%)
        Without either, the app's Settings → General choice applies (left by default).
        """)
    exit(0)
}
let asJSON = arguments.contains("--json")

let config: Config
do {
    config = try Config.load()
} catch {
    fail("can't read the config: \(error)", code: 2)
}
if config.accounts.isEmpty {
    fail("no accounts configured; add them in the claudebar app's Settings", code: 2)
}
let mode: DisplayMode = arguments.contains("--used") ? .used : arguments.contains("--left") ? .left : config.displayMode
guard let claude = Paths.locateClaude(override: config.claudePath) else {
    fail("can't find the claude CLI; set claudePath in the config", code: 3)
}

let results = await ClaudeProbe.probeAll(config.accounts, claude: claude)
let defaultLogin = await ClaudeProbe.defaultLogin(claude: claude)
let rows = Array(zip(config.accounts, results))

if asJSON {
    struct WindowJSON: Encodable {
        let usedPercent: Double
        let leftPercent: Double
        let resetsAt: Date?
        let resetText: String?
        init(_ w: UsageWindow) {
            usedPercent = w.usedPercent
            leftPercent = w.leftPercent
            resetsAt = w.resetsAt
            resetText = w.resetText
        }
    }
    struct AccountJSON: Encodable {
        let id: String
        let name: String
        let email: String?
        let plan: String?
        let inUse: Bool
        let session: WindowJSON?
        let week: WindowJSON?
        let problem: String?
        let fetchedAt: Date
    }
    let payload = rows.map { account, usage in
        AccountJSON(
            id: account.id, name: account.name,
            email: usage.auth?.email ?? account.email, plan: usage.auth?.subscriptionType,
            inUse: account.isInUse(usage: usage, defaultLogin: defaultLogin),
            session: usage.report?.session.map(WindowJSON.init), week: usage.report?.week.map(WindowJSON.init),
            problem: usage.problem, fetchedAt: usage.fetchedAt)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    exit(results.contains { $0.problem != nil } ? 1 : 0)
}

let colour = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

func paint(_ text: String, _ code: String) -> String {
    colour ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
}

/// A ten-cell bar of what's left (or used, per `mode`), coloured by what's left: green, then yellow, then red as it runs down.
func bar(_ window: UsageWindow) -> String {
    let filled = Int((mode.percent(window) / 10).rounded())
    let cells = String(repeating: "█", count: filled) + String(repeating: "░", count: 10 - filled)
    let code: String
    switch UsageLevel(window) {
    case .ok: code = "32"
    case .low: code = "33"
    case .critical: code = "31"
    }
    return paint(cells, code)
}

func windowLine(_ title: String, _ window: UsageWindow?) -> String {
    let label = title.padding(toLength: 7, withPad: " ", startingAt: 0)
    guard let window else { return "  \(label) not reported" }
    var line = "  \(label) \(bar(window))  \(UsageFormat.percent(window, mode: mode).padding(toLength: 9, withPad: " ", startingAt: 0))"
    if let reset = UsageFormat.resetLine(window) { line += "  " + paint(reset, "2") }
    return line
}

for (account, usage) in rows {
    var details: [String] = []
    if let email = usage.auth?.email ?? account.email { details.append(email) }
    if let plan = usage.auth?.subscriptionType { details.append(plan.capitalized) }
    if account.isInUse(usage: usage, defaultLogin: defaultLogin) { details.append("in use") }
    print(paint(account.name, "1") + (details.isEmpty ? "" : "  " + paint(details.joined(separator: " · "), "2")))
    if let report = usage.report {
        print(windowLine("5-hour", report.session))
        print(windowLine("weekly", report.week))
    } else {
        let hint = usage.needsSignIn ? paint("  (Sign in… in claudebar's Settings)", "2") : ""
        print("  " + paint(usage.problem ?? "no data", "33") + hint)
    }
    print()
}
exit(results.contains { $0.problem != nil } ? 1 : 0)
