// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// What `claude auth status --json` says about one config dir.
public struct AuthStatus: Codable, Equatable, Sendable {
    public var loggedIn: Bool
    public var authMethod: String?
    public var email: String?
    public var orgId: String?
    public var orgName: String?
    public var subscriptionType: String?

    public init(loggedIn: Bool, authMethod: String? = nil, email: String? = nil, orgId: String? = nil,
                orgName: String? = nil, subscriptionType: String? = nil) {
        self.loggedIn = loggedIn
        self.authMethod = authMethod
        self.email = email
        self.orgId = orgId
        self.orgName = orgName
        self.subscriptionType = subscriptionType
    }

    // Lenient decoding: only `loggedIn` matters when signed out, and newer Claude Code versions may add or drop fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loggedIn = try c.decodeIfPresent(Bool.self, forKey: .loggedIn) ?? false
        authMethod = try c.decodeIfPresent(String.self, forKey: .authMethod)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        orgId = try c.decodeIfPresent(String.self, forKey: .orgId)
        orgName = try c.decodeIfPresent(String.self, forKey: .orgName)
        subscriptionType = try c.decodeIfPresent(String.self, forKey: .subscriptionType)
    }

    /// Same person in the same organisation, whichever config dir the login lives in.
    public func isSameLogin(as other: AuthStatus) -> Bool {
        loggedIn && other.loggedIn && email != nil && email == other.email && orgId == other.orgId
    }
}

/// One account's result from a refresh.
public struct AccountUsage: Codable, Equatable, Sendable {
    public var auth: AuthStatus?
    public var report: UsageReport?
    /// Why there are no numbers (not signed in, `claude` failed, /usage reworded); nil when the report is good.
    public var problem: String?
    public var fetchedAt: Date

    public init(auth: AuthStatus?, report: UsageReport?, problem: String?, fetchedAt: Date = Date()) {
        self.auth = auth
        self.report = report
        self.problem = problem
        self.fetchedAt = fetchedAt
    }

    public var needsSignIn: Bool { auth?.loggedIn == false }
}

public enum ProbeError: Error, CustomStringConvertible {
    case launch(String)
    case killed(String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .launch(let detail): return "Couldn't run claude: \(detail)"
        case .killed(let command): return "claude \(command) didn't finish (timed out or was killed)"
        case .unreadable(let detail): return detail
        }
    }
}

/// Asks the `claude` CLI about an account, using two read-only commands: `claude auth status --json` (who is signed in) and `claude -p /usage`, which Claude Code runs as a local command (no model call, no tokens) and answers with the same numbers as the interactive /usage screen. Claude Code keeps each config dir's login fresh itself; claudebar never reads or stores a token.
public enum ClaudeProbe {
    static let timeout: TimeInterval = 45

    public static func probe(_ account: Account, claude: URL) async -> AccountUsage {
        let configDir = account.usesDefaultConfigDir ? nil : account.configURL
        do {
            let auth = try await authStatus(configDir: configDir, claude: claude)
            guard auth.loggedIn else {
                return AccountUsage(auth: auth, report: nil, problem: "Not signed in")
            }
            let text = try await usageText(configDir: configDir, claude: claude)
            let report = UsageParser.parse(text)
            guard !report.isEmpty else {
                let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "no output"
                return AccountUsage(auth: auth, report: nil, problem: "No limits in /usage (\(first))")
            }
            return AccountUsage(auth: auth, report: report, problem: nil)
        } catch {
            return AccountUsage(auth: nil, report: nil, problem: String(describing: error))
        }
    }

    /// Probes every account concurrently, keeping the config's order.
    public static func probeAll(_ accounts: [Account], claude: URL) async -> [AccountUsage] {
        await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (i, account) in accounts.enumerated() {
                group.addTask { (i, await probe(account, claude: claude)) }
            }
            var results = [AccountUsage?](repeating: nil, count: accounts.count)
            for await (i, usage) in group { results[i] = usage }
            return results.compactMap { $0 }
        }
    }

    /// Who a plain `claude` (the default `~/.claude`) is signed in as right now.
    public static func defaultLogin(claude: URL) async -> AuthStatus? {
        try? await authStatus(configDir: nil, claude: claude)
    }

    /// `claude auth status --json`. It exits 1 when signed out, so the JSON is read whatever the exit code.
    static func authStatus(configDir: URL?, claude: URL) async throws -> AuthStatus {
        let out = try await run(claude, ["auth", "status", "--json"], configDir: configDir)
        guard let json = jsonObject(in: out.stdout),
              let status = try? JSONDecoder().decode(AuthStatus.self, from: json) else {
            throw ProbeError.unreadable("claude auth status: \(summary(out))")
        }
        return status
    }

    /// The text of `claude -p /usage`. `--safe-mode` keeps hooks, MCP servers and plugins out of it; `--no-session-persistence` leaves no session behind.
    static func usageText(configDir: URL?, claude: URL) async throws -> String {
        let out = try await run(claude, ["-p", "/usage", "--safe-mode", "--no-session-persistence", "--output-format", "json"], configDir: configDir)
        struct Result: Decodable {
            var result: String?
            var is_error: Bool?
        }
        guard let json = jsonObject(in: out.stdout),
              let decoded = try? JSONDecoder().decode(Result.self, from: json),
              let text = decoded.result else {
            throw ProbeError.unreadable("claude -p /usage: \(summary(out))")
        }
        if decoded.is_error == true { throw ProbeError.unreadable("claude -p /usage: \(text)") }
        return text
    }

    // MARK: - Running claude

    struct Output {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// The child's environment: the account's config dir and nothing that could override its login. An API key, a parent Claude Code session or a cloud-provider switch would each change what /usage reports, so every ANTHROPIC_* and CLAUDE* variable goes. Otherwise it stays as close to a plain `claude` run as possible: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` makes /usage skip its live fetch (a freshly signed-in account then shows no limits, and others may show cached ones), and even `DISABLE_TELEMETRY` changes which lines it prints. Only auto-update is off, so a probe never installs anything.
    static func environment(configDir: URL?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !(key.hasPrefix("ANTHROPIC_") || key.hasPrefix("CLAUDE"))
        }
        if let configDir { env["CLAUDE_CONFIG_DIR"] = configDir.path }
        env["DISABLE_AUTOUPDATER"] = "1"
        return env
    }

    static func run(_ claude: URL, _ arguments: [String], configDir: URL?) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = claude
                process.arguments = arguments
                process.environment = environment(configDir: configDir)
                // A neutral working dir, so no project's .claude/ settings or CLAUDE.md apply.
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                let stdout = Pipe(), stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProbeError.launch("\(claude.path): \(error.localizedDescription)"))
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                // Drain stderr on another thread so neither pipe can fill up and stall the child.
                let errors = DataBox()
                let drained = DispatchGroup()
                drained.enter()
                DispatchQueue.global().async {
                    errors.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    drained.leave()
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                drained.wait()
                process.waitUntilExit()
                watchdog.cancel()
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: ProbeError.killed(arguments.joined(separator: " ")))
                    return
                }
                continuation.resume(returning: Output(
                    status: process.terminationStatus,
                    stdout: String(decoding: output, as: UTF8.self),
                    stderr: String(decoding: errors.data, as: UTF8.self)))
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// The JSON object in `text`, from its first `{` to its last `}` (auth status pretty-prints over several lines; a warning line could precede either command's JSON).
    static func jsonObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }

    /// A one-line account of a failed run, for the menu.
    static func summary(_ out: Output) -> String {
        let line = [out.stderr, out.stdout]
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "no output"
        return "exit \(out.status), \(line.prefix(200))"
    }
}
