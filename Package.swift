// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import PackageDescription

let package = Package(
    name: "claudebar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"]),
        .executable(name: "claudebar", targets: ["claudebar"]),
        .executable(name: "ClaudebarApp", targets: ["ClaudebarApp"]),
    ],
    targets: [
        // Shared library: the accounts config, the `claude` probe and the /usage parser.
        .target(
            name: "UsageKit"
        ),
        // CLI executable: the same probe as the app, printed in the terminal.
        .executableTarget(
            name: "claudebar",
            dependencies: ["UsageKit"]
        ),
        // Menu-bar app: SwiftUI MenuBarExtra + Settings. Built into an .app bundle by `make app` (a bare SwiftPM executable can't be a menu-bar agent).
        .executableTarget(
            name: "ClaudebarApp",
            dependencies: ["UsageKit"],
            path: "App/Sources"
        ),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"]
        ),
    ]
)
