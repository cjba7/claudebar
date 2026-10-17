// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// Where claudebar keeps its files, where it looks for `claude`, and the `~` handling the config file allows.
public enum Paths {
    /// `~/Library/Application Support/claudebar/`, created on first use.
    public static func appSupport() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("claudebar", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `config.json`, shared by the app (which writes it) and the CLI (which only reads it). `CLAUDEBAR_CONFIG` points both at another file.
    public static var configURL: URL {
        get throws {
            if let path = ProcessInfo.processInfo.environment["CLAUDEBAR_CONFIG"], !path.isEmpty {
                return URL(fileURLWithPath: expandTilde(path))
            }
            return try appSupport().appendingPathComponent("config.json")
        }
    }

    /// Claude Code's default config dir, the one a plain `claude` uses.
    public static var defaultClaudeConfigDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude", isDirectory: true)
    }

    /// The config dir a newly added account gets.
    public static func newAccountConfigDir(id: String) -> String {
        "~/.claude-accounts/\(id)"
    }

    public static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public static func abbreviateHome(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// The `claude` executable. A path set in the config is used as given; otherwise the usual install locations are tried, since an app started from Finder doesn't inherit the shell's PATH.
    public static func locateClaude(override: String?) -> URL? {
        if let path = override?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            let expanded = expandTilde(path)
            return FileManager.default.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
