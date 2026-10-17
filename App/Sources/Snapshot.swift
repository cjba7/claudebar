// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

#if DEBUG
import AppKit
import SwiftUI

/// Development aid (`make snapshot`): with `CLAUDEBAR_SNAPSHOT=/path/menu.png` the debug build renders the menu to a PNG once the first refresh settles, then quits, so the layout can be checked without clicking the menu bar. Controls AppKit draws (buttons, spinners) may come out as placeholders.
@MainActor
enum Snapshot {
    static func runIfRequested(store: UsageStore) {
        guard let path = ProcessInfo.processInfo.environment["CLAUDEBAR_SNAPSHOT"] else { return }
        let dark = ProcessInfo.processInfo.environment["CLAUDEBAR_SNAPSHOT_DARK"] == "1"
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(60)
            repeat {
                try? await Task.sleep(nanoseconds: 200_000_000)
            } while store.isRefreshing && Date() < deadline
            let menu = MenuContentView(store: store)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: menu)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
