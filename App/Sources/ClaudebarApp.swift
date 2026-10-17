// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import SwiftUI

/// claudebar menu-bar app. Agent by default (LSUIElement in Info.plist): a `MenuBarExtra` window listing every account's limits, plus a `Settings` scene, sharing one `UsageStore`.
@main
struct ClaudebarApp: App {
    @StateObject private var store = UsageStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            // The needle follows the least left on any account; it bounces once when fresh numbers land.
            Image(systemName: GaugeIcon.name(lowestLeft: store.lowestLeft))
                .symbolEffect(.bounce, value: store.lastRefresh)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, settings: settings)
        }
    }
}
