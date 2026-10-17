// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// One Claude account: a display name and the Claude Code config dir that holds its login.
public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: String            // stable key, a slug of the name it was added with
    public var name: String
    /// `CLAUDE_CONFIG_DIR` for this account (`~` allowed). `~/.claude` means Claude Code's default login, whichever account a plain `claude` is signed in to.
    public var configDir: String
    /// Optional: pre-fills the sign-in page (`claude auth login --email`).
    public var email: String?

    public init(id: String, name: String, configDir: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.configDir = configDir
        self.email = email
    }

    public var configURL: URL {
        URL(fileURLWithPath: Paths.expandTilde(configDir), isDirectory: true).standardizedFileURL
    }

    /// True for the default `~/.claude`, which is probed with `CLAUDE_CONFIG_DIR` unset, exactly like a plain `claude`.
    public var usesDefaultConfigDir: Bool {
        configURL.resolvingSymlinksInPath().path == Paths.defaultClaudeConfigDir.resolvingSymlinksInPath().path
    }

    /// Whether this is the account a plain `claude` is signed in to right now.
    public func isInUse(usage: AccountUsage?, defaultLogin: AuthStatus?) -> Bool {
        if usesDefaultConfigDir { return usage?.auth?.loggedIn == true }
        guard let auth = usage?.auth, let login = defaultLogin else { return false }
        return auth.isSameLogin(as: login)
    }
}

/// The config file model. The app owns writes; the CLI only reads. Hand edits are picked up on the app's next refresh.
public struct Config: Codable, Equatable {
    public var version: Int
    /// Path to `claude`; nil finds it in the usual places.
    public var claudePath: String?
    /// Percent left or percent used; nil means left.
    public var show: DisplayMode?
    public var accounts: [Account]

    public init(version: Int = 1, claudePath: String? = nil, show: DisplayMode? = nil, accounts: [Account] = []) {
        self.version = version
        self.claudePath = claudePath
        self.show = show
        self.accounts = accounts
    }

    public var displayMode: DisplayMode { show ?? .left }

    // Lenient decoding: tolerate a hand-edited file missing version/accounts.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath)
        show = try? c.decodeIfPresent(DisplayMode.self, forKey: .show)
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
    }

    // MARK: - Load / save (atomic: temp + rename via .atomic)

    public static func load(from url: URL? = nil) throws -> Config {
        let u = try (url ?? Paths.configURL)
        guard FileManager.default.fileExists(atPath: u.path) else {
            return Config()  // no config yet -> empty default
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: u))
    }

    public func save(to url: URL? = nil) throws {
        let u = try (url ?? Paths.configURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: u, options: .atomic)
    }

    /// A lowercase, path-safe id for a new account, unique among `existing`: "My Work" -> "my-work".
    public static func slug(for name: String, existing: [String]) -> String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let root = words.isEmpty ? "account" : words.joined(separator: "-")
        var candidate = root
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(root)-\(n)"
            n += 1
        }
        return candidate
    }
}
