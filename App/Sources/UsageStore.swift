// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import AppKit
import Foundation
import UsageKit

/// Lightweight file log (agents have nowhere to print): set `CLAUDEBAR_APP_LOG=1`.
enum AppLog {
    private static let enabled = ProcessInfo.processInfo.environment["CLAUDEBAR_APP_LOG"] == "1"
    private static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("claudebar-app.log")
    static func log(_ message: String) {
        guard enabled else { return }
        let line = "[\(Date())] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// App-wide state. `@MainActor` so every `@Published` change happens on the main thread. The app owns config writes (the CLI only reads) and re-reads the file before every refresh and every change, so hand edits apply without a restart.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var usage: [String: AccountUsage] = [:]   // by account id
    /// Who a plain `claude` (`~/.claude`) is signed in as, to mark that account "in use".
    @Published private(set) var defaultLogin: AuthStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    /// A problem that stops every account (config unreadable, `claude` missing).
    @Published private(set) var problem: String?
    /// Percent left or percent used, from the config.
    @Published private(set) var displayMode: DisplayMode = .left

    private var config = Config()
    private var keyWindowObserver: NSObjectProtocol?

    init() {
        // The menu's window becomes key each time it opens, so this doubles as "the menu opened".
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIfStale() }
        }
        refresh()
        #if DEBUG
        Snapshot.runIfRequested(store: self)
        #endif
    }

    var claudePath: String { config.claudePath ?? "" }
    var resolvedClaude: URL? { Paths.locateClaude(override: config.claudePath) }

    func isInUse(_ account: Account) -> Bool {
        account.isInUse(usage: usage[account.id], defaultLogin: defaultLogin)
    }

    /// The least left in any window of any account, 0-100, for the menu-bar gauge; nil before the first numbers arrive.
    var lowestLeft: Double? {
        let windows = usage.values.compactMap(\.report).flatMap { [$0.session, $0.week] }.compactMap { $0 }
        return windows.map(\.leftPercent).min()
    }

    // MARK: - Refresh

    /// Refresh when the menu opens unless the numbers are recent: under a minute old when every account came back clean, ten seconds when one didn't (so a fresh sign-in shows up quickly).
    func refreshIfStale() {
        guard let last = lastRefresh else { return refresh() }
        let clean = accounts.allSatisfy { usage[$0.id] != nil && usage[$0.id]?.problem == nil }
        if Date().timeIntervalSince(last) > (clean ? 60 : 10) { refresh() }
    }

    /// Probes every account concurrently; each row updates as its result lands.
    func refresh() {
        guard !isRefreshing else { return }
        problem = nil
        loadConfig()
        guard problem == nil else { return }
        #if DEBUG
        if Demo.isOn { return Demo.load(into: self) }
        #endif
        guard let claude = resolvedClaude else {
            problem = config.claudePath == nil
                ? "Can't find the claude CLI. Set its path in Settings."
                : "No claude CLI at \(config.claudePath ?? ""). Fix the path in Settings."
            return
        }
        isRefreshing = true
        let accounts = self.accounts
        AppLog.log("refresh: \(accounts.count) account(s) via \(claude.path)")
        Task {
            async let login = ClaudeProbe.defaultLogin(claude: claude)
            await withTaskGroup(of: (String, AccountUsage).self) { group in
                for account in accounts {
                    group.addTask { (account.id, await ClaudeProbe.probe(account, claude: claude)) }
                }
                for await (id, result) in group {
                    self.usage[id] = result
                    AppLog.log("\(id): \(result.problem ?? "ok")")
                }
            }
            self.defaultLogin = await login
            self.lastRefresh = Date()
            self.isRefreshing = false
        }
    }

    // MARK: - Accounts (the app owns writes; atomic)

    /// Adds an account with its own config dir, `~/.claude-accounts/<id>`, then checks it (it will want signing in once).
    func addAccount(name: String, email: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        mutate { config in
            let id = Config.slug(for: name, existing: config.accounts.map(\.id))
            config.accounts.append(Account(
                id: id, name: name, configDir: Paths.newAccountConfigDir(id: id),
                email: email.isEmpty ? nil : email))
        }
        refresh()
    }

    func rename(id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        mutate { config in
            if let i = config.accounts.firstIndex(where: { $0.id == id }) { config.accounts[i].name = name }
        }
    }

    /// Forgets the account. Its config dir, and the login in it, stay on disk.
    func remove(id: String) {
        mutate { config in config.accounts.removeAll { $0.id == id } }
        usage[id] = nil
    }

    func setDisplayMode(_ mode: DisplayMode) {
        mutate { config in config.show = mode }
    }

    func setClaudePath(_ path: String) {
        let path = path.trimmingCharacters(in: .whitespaces)
        mutate { config in config.claudePath = path.isEmpty ? nil : path }
    }

    /// Opens Terminal on `claude auth login` for this account's config dir; the next menu open re-checks it.
    func signIn(_ account: Account) {
        guard let claude = resolvedClaude else {
            problem = "Can't find the claude CLI. Set its path in Settings."
            return
        }
        do {
            NSWorkspace.shared.open(try SignInScript.write(for: account, claude: claude))
        } catch {
            problem = "Couldn't start sign-in: \(error.localizedDescription)"
        }
    }

    func revealConfig() {
        guard let url = try? Paths.configURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) { mutate { _ in } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func loadConfig() {
        do {
            config = try Config.load()
            accounts = config.accounts
            if displayMode != config.displayMode { displayMode = config.displayMode }
            usage = usage.filter { id, _ in config.accounts.contains { $0.id == id } }
        } catch {
            problem = "Can't read config.json: \(error.localizedDescription)"
            AppLog.log("config load failed: \(error)")
        }
    }

    /// Re-read, change, save: a hand edit made since the last refresh isn't overwritten, and a file that can't be read isn't replaced.
    private func mutate(_ change: (inout Config) -> Void) {
        problem = nil
        loadConfig()
        guard problem == nil else { return }
        change(&config)
        do {
            try config.save()
        } catch {
            problem = "Can't save config.json: \(error.localizedDescription)"
            AppLog.log("save failed: \(error)")
        }
        accounts = config.accounts
        displayMode = config.displayMode
    }

    #if DEBUG
    /// For `Demo`: made-up accounts and numbers, no `claude` involved.
    func loadDemo(accounts: [Account], usage: [String: AccountUsage]) {
        self.accounts = accounts
        self.usage = usage
        self.defaultLogin = usage[accounts.first?.id ?? ""]?.auth
        self.lastRefresh = Date()
    }
    #endif
}
