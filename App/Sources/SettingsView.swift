// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import SwiftUI
import UsageKit

/// The Settings scene: manage accounts (add, rename, sign in, remove) and app preferences (launch at login, show in Dock, where `claude` is).
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    @State private var newName = ""
    @State private var newEmail = ""
    @State private var claudePath = ""

    var body: some View {
        TabView {
            accountsTab.tabItem { Label("Accounts", systemImage: "person.2") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 580, height: 440)
        .padding()
    }

    // MARK: - Accounts

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts").font(.headline)
            Text("Each account signs in once into its own Claude Code config folder. claudebar then runs /usage against that folder, which is free: no model call, no tokens.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.accounts.isEmpty {
                Text("None yet. Add one below.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.accounts) { account in
                    AccountSettingsRow(
                        account: account,
                        status: status(for: account),
                        onRename: { store.rename(id: account.id, to: $0) },
                        onSignIn: { store.signIn(account) },
                        onRemove: { store.remove(id: account.id) })
                }
            }

            Divider().padding(.vertical, 4)

            Text("Add an account").font(.headline)
            HStack {
                TextField("Name, e.g. Personal", text: $newName).frame(width: 180)
                TextField("Email (optional)", text: $newEmail).frame(width: 210)
                Button("Add") {
                    store.addAccount(name: newName, email: newEmail)
                    newName = ""
                    newEmail = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Then press Sign in… and approve in the browser. The browser approves whichever claude.ai account it is signed in to, so switch to the right one there first.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Show config file") { store.revealConfig() }
                Spacer()
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") { store.refresh() }
                    .disabled(store.isRefreshing)
            }
        }
    }

    private func status(for account: Account) -> (text: String, warning: Bool) {
        guard let usage = store.usage[account.id] else { return ("not checked yet", false) }
        if usage.needsSignIn { return ("not signed in", true) }
        if let problem = usage.problem { return (problem, true) }
        let details = [usage.auth?.email, usage.auth?.subscriptionType?.capitalized].compactMap { $0 }
        return (details.isEmpty ? "signed in" : details.joined(separator: " · "), false)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            Toggle("Show in Dock", isOn: Binding(
                get: { settings.showInDock }, set: { settings.setShowInDock($0) }))
            Divider()
            Picker("Show", selection: Binding(get: { store.displayMode }, set: { store.setDisplayMode($0) })) {
                Text("Remaining").tag(DisplayMode.left)
                Text("Used").tag(DisplayMode.used)
            }
            .pickerStyle(.segmented)
            Text(store.displayMode == .left
                 ? "Counts down: a fresh week is 100%. Bars are green above 50% left, yellow down to 20%, red at 20% or less."
                 : "Counts up: a fresh week is 0%. Bars are green below 50% used, yellow up to 80%, red from 80%.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            TextField("claude path", text: $claudePath, prompt: Text("Find automatically"))
                .onSubmit { store.setClaudePath(claudePath) }
            Text(store.resolvedClaude.map { "Using \(Paths.abbreviateHome($0.path)). Leave empty to find it automatically." }
                 ?? "claude not found: enter its full path and press Return.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .onAppear { claudePath = store.claudePath }
    }
}

/// One configured account with in-place rename, sign in and remove.
private struct AccountSettingsRow: View {
    let account: Account
    let status: (text: String, warning: Bool)
    let onRename: (String) -> Void
    let onSignIn: () -> Void
    let onRemove: () -> Void

    @State private var name: String

    init(account: Account, status: (text: String, warning: Bool),
         onRename: @escaping (String) -> Void, onSignIn: @escaping () -> Void,
         onRemove: @escaping () -> Void) {
        self.account = account
        self.status = status
        self.onRename = onRename
        self.onSignIn = onSignIn
        self.onRemove = onRemove
        _name = State(initialValue: account.name)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name).frame(width: 150).onSubmit { onRename(name) }
                Text(account.configDir).font(.caption).foregroundStyle(.secondary)
            }
            Text(status.text).font(.caption)
                .foregroundStyle(status.warning ? Color.orange : Color.secondary)
                .lineLimit(2)
            Spacer()
            Button("Sign in…", action: onSignIn)
            Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove from claudebar. Its folder, and the login in it, stay on disk.")
        }
    }
}
