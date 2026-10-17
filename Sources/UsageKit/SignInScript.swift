// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import Foundation

/// The Terminal script behind "Sign in…": `claude auth login` for one account's config dir. Signing in is a browser round trip that can ask for a pasted code, so it runs where it can be seen rather than hidden inside the app.
public enum SignInScript {
    public static func contents(for account: Account, claude: URL) -> String {
        var lines = [
            "#!/bin/zsh",
            "# Written by claudebar: signs one account in to Claude Code.",
            "# Terminal starts this in whichever folder its last window was in, which can be gone or off limits (a cloud-storage folder, say), and claude can't start there, so work from a neutral one.",
            #"cd -- "${TMPDIR:-/tmp}" || cd /"#,
            "unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN",
        ]
        if account.usesDefaultConfigDir {
            lines.append("unset CLAUDE_CONFIG_DIR")
        } else {
            lines.append("mkdir -p \(quote(account.configURL.path))")
            lines.append("export CLAUDE_CONFIG_DIR=\(quote(account.configURL.path))")
        }
        lines.append("echo \(quote("Signing in \(account.name). The browser approves whichever claude.ai account it is signed in to, so check it is the right one."))")
        var login = "\(quote(claude.path)) auth login"
        if let email = account.email?.trimmingCharacters(in: .whitespaces), !email.isEmpty {
            login += " --email \(quote(email))"
        }
        lines += [
            "if \(login); then",
            "  echo",
            "  echo \(quote("Signed in. Open claudebar to see this account; this window can be closed."))",
            "else",
            "  echo",
            "  echo \(quote("Sign-in didn't finish (see above). Press Sign in… in claudebar to try again."))",
            "fi",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the script into Application Support and returns it, ready to open in Terminal.
    public static func write(for account: Account, claude: URL) throws -> URL {
        let name = "sign-in-\(Config.slug(for: account.id, existing: [])).command"
        let url = try Paths.appSupport().appendingPathComponent(name)
        try contents(for: account, claude: claude).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Single-quotes a value for zsh.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
