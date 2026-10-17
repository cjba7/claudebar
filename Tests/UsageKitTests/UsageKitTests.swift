// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import XCTest
@testable import UsageKit

final class UsageParserTests: XCTestCase {
    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private func madridDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// When the sample below was captured.
    private var now: Date { madridDate(2026, 9, 24, 11, 58) }

    /// Real `claude -p /usage` output (Claude Code 2.1.281), trimmed after the limits.
    private let sample = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 2% used · resets Sep 24 at 4:49pm (Europe/Madrid)
        Current week (all models): 54% used · resets Sep 29 at 2:59am (Europe/Madrid)
        Current week (Fable): 0% used · resets Sep 29 at 3am (Europe/Madrid)

        What's contributing to your limits usage?
        Last 24h · 12736 requests · 11 sessions
          99% of your usage came from subagent-heavy sessions
        """

    func testParsesSessionAndAllModelsWeek() {
        let report = UsageParser.parse(sample, now: now)
        XCTAssertEqual(report.session?.usedPercent, 2)
        XCTAssertEqual(report.session?.leftPercent, 98)
        XCTAssertEqual(report.session?.resetsAt, madridDate(2026, 9, 24, 16, 49))
        XCTAssertEqual(report.session?.resetText, "Sep 24 at 4:49pm (Europe/Madrid)")
        XCTAssertEqual(report.week?.usedPercent, 54)
        XCTAssertEqual(report.week?.resetsAt, madridDate(2026, 9, 29, 2, 59))
    }

    func testIgnoresPerModelWeeks() {
        let report = UsageParser.parse("Current week (Fable): 80% used · resets Sep 29 at 3am (Europe/Madrid)", now: now)
        XCTAssertTrue(report.isEmpty)
    }

    func testSignedOutOutputHasNoLimits() {
        let signedOut = "Total cost:            $0.0000\nTotal duration (API):  0s\nUsage:                 0 input, 0 output"
        XCTAssertTrue(UsageParser.parse(signedOut, now: now).isEmpty)
    }

    func testWindowWithoutReset() {
        let window = UsageParser.window("0% used", now: now)
        XCTAssertEqual(window, UsageWindow(usedPercent: 0))
    }

    func testUnreadableResetKeepsItsText() {
        let window = UsageParser.window("54% used · resets whenever it likes", now: now)
        XCTAssertEqual(window?.usedPercent, 54)
        XCTAssertNil(window?.resetsAt)
        XCTAssertEqual(window?.resetText, "whenever it likes")
    }

    func testOverLimitClampsLeftAtZero() {
        XCTAssertEqual(UsageParser.window("104% used", now: now)?.leftPercent, 0)
    }

    func testHoursWithoutMinutesAndTheTwelves() {
        XCTAssertEqual(UsageParser.resetDate("Sep 29 at 3am (Europe/Madrid)", now: now), madridDate(2026, 9, 29, 3, 0))
        XCTAssertEqual(UsageParser.resetDate("Sep 25 at 12am (Europe/Madrid)", now: now), madridDate(2026, 9, 25, 0, 0))
        XCTAssertEqual(UsageParser.resetDate("Sep 25 at 12pm (Europe/Madrid)", now: now), madridDate(2026, 9, 25, 12, 0))
        XCTAssertNil(UsageParser.resetDate("Sep 25 at 13pm (Europe/Madrid)", now: now))
    }

    func testTimeZoneComesFromTheText() {
        let reset = UsageParser.resetDate("Sep 24 at 4:49pm (Europe/London)", now: now)
        XCTAssertEqual(reset, madridDate(2026, 9, 24, 17, 49))  // London is an hour behind Madrid
    }

    func testWeeklyResetAcrossNewYearIsNextYear() {
        let newYearsEve = madridDate(2026, 12, 30, 10, 0)
        XCTAssertEqual(UsageParser.resetDate("Jan 2 at 9am (Europe/Madrid)", now: newYearsEve), madridDate(2027, 1, 2, 9, 0))
    }

    func testBareTimeIsTodayOrTomorrow() {
        XCTAssertEqual(UsageParser.resetDate("4:49pm (Europe/Madrid)", now: now), madridDate(2026, 9, 24, 16, 49))
        XCTAssertEqual(UsageParser.resetDate("9am (Europe/Madrid)", now: now), madridDate(2026, 9, 25, 9, 0))
    }
}

final class UsageFormatTests: XCTestCase {
    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func at(_ d: Int, _ h: Int, _ m: Int) -> Date {
        madrid.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    func testCountdown() {
        let now = at(24, 11, 58)
        XCTAssertEqual(UsageFormat.countdown(to: at(24, 16, 49), from: now), "4h 51m")
        XCTAssertEqual(UsageFormat.countdown(to: at(29, 2, 59), from: now), "4d 15h")
        XCTAssertEqual(UsageFormat.countdown(to: at(24, 12, 10), from: now), "12m")
        XCTAssertEqual(UsageFormat.countdown(to: at(24, 13, 58), from: now), "2h")
        XCTAssertEqual(UsageFormat.countdown(to: at(24, 11, 0), from: now), "now")
    }

    func testResetTimeTodayTomorrowAndLater() {
        let now = at(24, 11, 58)
        let gb = Locale(identifier: "en_GB")
        XCTAssertEqual(UsageFormat.resetTime(at(24, 16, 49), now: now, calendar: madrid, locale: gb), "16:49")
        // Whether the hour gets a leading zero ("9:00" or "09:00") depends on the ICU version, so only the rest is pinned.
        let tomorrow = UsageFormat.resetTime(at(25, 9, 0), now: now, calendar: madrid, locale: gb)
        XCTAssertTrue(tomorrow.hasPrefix("tomorrow ") && tomorrow.hasSuffix("9:00"), tomorrow)
        let later = UsageFormat.resetTime(at(29, 2, 59), now: now, calendar: madrid, locale: gb)
        XCTAssertTrue(later.hasPrefix("Tue 29"), later)
        XCTAssertTrue(later.hasSuffix("2:59"), later)
    }

    func testResetLineFallsBackToRawText() {
        XCTAssertEqual(UsageFormat.resetLine(UsageWindow(usedPercent: 5, resetText: "soon")), "resets soon")
        XCTAssertNil(UsageFormat.resetLine(UsageWindow(usedPercent: 5)))
    }

    func testLeftRoundsToWholePercent() {
        XCTAssertEqual(UsageFormat.left(UsageWindow(usedPercent: 2.4)), "98% left")
    }

    func testFreshWindowIsAllLeftOrNoneUsed() {
        let fresh = UsageWindow(usedPercent: 0)
        XCTAssertEqual(UsageFormat.percent(fresh, mode: .left), "100% left")
        XCTAssertEqual(UsageFormat.percent(fresh, mode: .used), "0% used")
        XCTAssertEqual(UsageFormat.percent(UsageWindow(usedPercent: 130), mode: .used), "100% used")
    }

    func testLevelsGoByWhatIsLeft() {
        XCTAssertEqual(UsageLevel(leftPercent: 100), .ok)
        XCTAssertEqual(UsageLevel(leftPercent: 51), .ok)
        XCTAssertEqual(UsageLevel(leftPercent: 50), .low)
        XCTAssertEqual(UsageLevel(leftPercent: 21), .low)
        XCTAssertEqual(UsageLevel(leftPercent: 20), .critical)
        XCTAssertEqual(UsageLevel(leftPercent: 0), .critical)
    }
}

final class AccountTests: XCTestCase {
    func testSlug() {
        XCTAssertEqual(Config.slug(for: "My Work", existing: []), "my-work")
        XCTAssertEqual(Config.slug(for: "My Work", existing: ["my-work"]), "my-work-2")
        XCTAssertEqual(Config.slug(for: "My Work", existing: ["my-work", "my-work-2"]), "my-work-3")
        XCTAssertEqual(Config.slug(for: "  ", existing: []), "account")
        XCTAssertEqual(Config.slug(for: "../etc", existing: []), "etc")
    }

    func testDefaultConfigDirIsRecognised() {
        XCTAssertTrue(Account(id: "a", name: "A", configDir: "~/.claude").usesDefaultConfigDir)
        XCTAssertTrue(Account(id: "a", name: "A", configDir: "~/.claude/").usesDefaultConfigDir)
        XCTAssertFalse(Account(id: "a", name: "A", configDir: "~/.claude-accounts/a").usesDefaultConfigDir)
    }

    func testInUseMatchesEmailAndOrganisation() {
        let account = Account(id: "a", name: "A", configDir: "~/.claude-accounts/a")
        let signedIn = AuthStatus(loggedIn: true, email: "me@example.com", orgId: "org-1")
        let usage = AccountUsage(auth: signedIn, report: nil, problem: nil)
        XCTAssertTrue(account.isInUse(usage: usage, defaultLogin: signedIn))
        XCTAssertFalse(account.isInUse(usage: usage, defaultLogin: AuthStatus(loggedIn: true, email: "me@example.com", orgId: "org-2")))
        XCTAssertFalse(account.isInUse(usage: usage, defaultLogin: AuthStatus(loggedIn: false)))
        XCTAssertFalse(account.isInUse(usage: usage, defaultLogin: nil))
    }

    func testConfigToleratesMissingFields() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"accounts":[{"id":"p","name":"Personal","configDir":"~/.claude-accounts/p"}]}"#.utf8))
        XCTAssertEqual(config.version, 1)
        XCTAssertNil(config.claudePath)
        XCTAssertEqual(config.accounts.first?.name, "Personal")
        XCTAssertNil(config.accounts.first?.email)
        XCTAssertEqual(config.displayMode, .left)
    }

    func testConfigReadsShowAndIgnoresNonsense() throws {
        let used = try JSONDecoder().decode(Config.self, from: Data(#"{"show":"used"}"#.utf8))
        XCTAssertEqual(used.displayMode, .used)
        let odd = try JSONDecoder().decode(Config.self, from: Data(#"{"show":"sideways"}"#.utf8))
        XCTAssertEqual(odd.displayMode, .left)
    }

    func testAuthStatusDecodesSignedOut() throws {
        let json = #"{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}"#
        let status = try JSONDecoder().decode(AuthStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.loggedIn)
        XCTAssertNil(status.email)
    }
}

final class SignInScriptTests: XCTestCase {
    private let claude = URL(fileURLWithPath: "/Users/me/.local/bin/claude")

    func testQuotesPathsAndPassesEmail() {
        let account = Account(id: "o", name: "O'Brien", configDir: "/tmp/it's here", email: "me@example.com")
        let script = SignInScript.contents(for: account, claude: claude)
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains(#"export CLAUDE_CONFIG_DIR='/tmp/it'\''s here'"#), script)
        XCTAssertTrue(script.contains("'/Users/me/.local/bin/claude' auth login --email 'me@example.com'"), script)
        XCTAssertTrue(script.contains("unset ANTHROPIC_API_KEY"), script)
    }

    func testScriptIsValidZsh() throws {
        let account = Account(id: "o", name: "O'Brien \"Ops\" $HOME", configDir: "/tmp/it's `here`", email: "me@example.com")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-sign-in-test.command")
        try SignInScript.contents(for: account, claude: claude).write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-n", file.path]  // parse only, run nothing
        try zsh.run()
        zsh.waitUntilExit()
        XCTAssertEqual(zsh.terminationStatus, 0)
    }

    /// Runs the real script against a stand-in `claude` that says where it ran, then exits with `status`.
    private func runScript(fakeClaudeExit status: Int32) throws -> (output: String, neutral: String, start: String, configDir: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-script-\(UUID().uuidString)")
        let start = root.appendingPathComponent("start"), neutral = root.appendingPathComponent("neutral")
        for dir in [start, neutral] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = root.appendingPathComponent("claude")
        try "#!/bin/zsh\necho \"ran in $PWD with $CLAUDE_CONFIG_DIR: $*\"\nexit \(status)\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let configDir = root.appendingPathComponent("config").path
        let script = root.appendingPathComponent("sign-in.command")
        try SignInScript.contents(for: Account(id: "t", name: "Test", configDir: configDir), claude: fake)
            .write(to: script, atomically: true, encoding: .utf8)

        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = [script.path]
        zsh.currentDirectoryURL = start  // where Terminal would have left us
        zsh.environment = ["TMPDIR": neutral.path, "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        zsh.standardOutput = out
        try zsh.run()
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        zsh.waitUntilExit()
        return (output, neutral.path, start.path, configDir)
    }

    func testScriptLeavesTheStartingFolderAndReportsSuccess() throws {
        let run = try runScript(fakeClaudeExit: 0)
        XCTAssertTrue(run.output.contains("ran in \(run.neutral) with \(run.configDir): auth login"), run.output)
        XCTAssertFalse(run.output.contains("ran in \(run.start)"), run.output)
        XCTAssertTrue(run.output.contains("Signed in."), run.output)
    }

    func testScriptSaysSoWhenSignInFails() throws {
        let run = try runScript(fakeClaudeExit: 1)
        XCTAssertTrue(run.output.contains("Sign-in didn't finish"), run.output)
        XCTAssertFalse(run.output.contains("Signed in."), run.output)
    }

    func testDefaultConfigDirUnsetsTheVariable() {
        let script = SignInScript.contents(for: Account(id: "d", name: "Default", configDir: "~/.claude"), claude: claude)
        XCTAssertTrue(script.contains("unset CLAUDE_CONFIG_DIR"), script)
        XCTAssertFalse(script.contains("export CLAUDE_CONFIG_DIR"), script)
        XCTAssertFalse(script.contains("--email"), script)
    }
}

final class ProbeHelperTests: XCTestCase {
    func testJSONObjectSurvivesAWarningLineAndPrettyPrinting() {
        let text = "warning: something\n{\n  \"loggedIn\": true\n}\n"
        let data = ClaudeProbe.jsonObject(in: text)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "{\n  \"loggedIn\": true\n}")
        XCTAssertNil(ClaudeProbe.jsonObject(in: "no json here"))
    }

    func testEnvironmentDropsOverridesAndSetsTheConfigDir() {
        setenv("ANTHROPIC_API_KEY", "sk-test", 1)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", "t", 1)
        setenv("CLAUDE_CONFIG_DIR", "/somewhere/else", 1)
        setenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1", 1)
        defer {
            unsetenv("ANTHROPIC_API_KEY")
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
            unsetenv("CLAUDE_CONFIG_DIR")
            unsetenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
        }
        let custom = ClaudeProbe.environment(configDir: URL(fileURLWithPath: "/tmp/acct"))
        XCTAssertNil(custom["ANTHROPIC_API_KEY"])
        XCTAssertNil(custom["CLAUDE_CODE_OAUTH_TOKEN"])
        XCTAssertEqual(custom["CLAUDE_CONFIG_DIR"], "/tmp/acct")
        XCTAssertEqual(custom["DISABLE_AUTOUPDATER"], "1")
        // It stops /usage fetching live numbers, so it must never reach a probe, even from the user's own environment.
        XCTAssertNil(custom["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
        XCTAssertNil(ClaudeProbe.environment(configDir: nil)["CLAUDE_CONFIG_DIR"])
    }
}
