// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and claudebar contributors
//
// This file is part of claudebar.

import AppKit
import SwiftUI
import UsageKit

/// The MenuBarExtra window: a header with the left/used switch, one card per account, and a footer.
struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if store.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No accounts yet").font(.headline)
                    Text("Open Settings to add your Claude accounts, then sign each one in once.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Re-render every 30 s so the "in 4h 51m" countdowns stay true while the menu is open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                            AccountRowView(
                                account: account,
                                usage: store.usage[account.id],
                                inUse: store.isInUse(account),
                                isRefreshing: store.isRefreshing,
                                mode: store.displayMode,
                                now: context.date,
                                index: index,
                                onSignIn: { store.signIn(account) })
                        }
                    }
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .animation(.snappy, value: store.problem)
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: GaugeIcon.name(lowestLeft: store.lowestLeft))
                .font(.title3)
                .foregroundStyle(GaugeIcon.tint(lowestLeft: store.lowestLeft))
                .contentTransition(.symbolEffect(.replace))
            Text("claudebar").font(.headline)
            Spacer()
            ModeSwitch(mode: store.displayMode, onChange: store.setDisplayMode)
            .help("Count down what's left (a fresh week is 100%) or count up what's used (a fresh week is 0%)")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { store.refresh() } label: {
                Label {
                    Text(store.isRefreshing ? "Refreshing…" : "Refresh")
                } icon: {
                    SpinningArrow(spinning: store.isRefreshing)
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(store.isRefreshing)
            .keyboardShortcut("r")
            if let last = store.lastRefresh, !store.isRefreshing {
                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                NSApp.activate()
                openSettings()
            } label: { Image(systemName: "gearshape") }
            .buttonStyle(PillButtonStyle())
            .help("Settings…")
            .keyboardShortcut(",")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(PillButtonStyle())
                .help("Quit claudebar")
                .keyboardShortcut("q")
        }
        .font(.callout)
        .animation(.easeInOut(duration: 0.25), value: store.isRefreshing)
    }
}

/// Left / Used, as a capsule whose highlight slides to the chosen side.
struct ModeSwitch: View {
    let mode: DisplayMode
    let onChange: (DisplayMode) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases, id: \.self) { option in
                Text(option == .left ? "Left" : "Used")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(option == mode ? Color.primary : Color.secondary)
                    .frame(width: 48, height: 20)
                    .background {
                        if option == mode {
                            Capsule().fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onChange(option) }
                    }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// A soft capsule button that lifts slightly under the pointer and dips when pressed.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration)
    }

    private struct PillButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(hovering ? 0.22 : 0.12)))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// One account card: name, plan and email, then the 5-hour and weekly windows (or why they're missing). Cards fade and slide in one after another when the menu opens.
struct AccountRowView: View {
    let account: Account
    let usage: AccountUsage?
    let inUse: Bool
    let isRefreshing: Bool
    let mode: DisplayMode
    let now: Date
    let index: Int
    let onSignIn: () -> Void

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(account.name).font(.headline)
                if inUse {
                    Text("in use")
                        .font(.caption2.weight(.medium)).foregroundStyle(.tint)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .help("A plain `claude` (your ~/.claude) is signed in to this account")
                }
                Spacer()
                if let plan = usage?.auth?.subscriptionType {
                    Text(plan.capitalized).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let email = usage?.auth?.email ?? account.email {
                Text(email).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(index) * 0.06)) { shown = true }
        }
    }

    @ViewBuilder private var content: some View {
        if let report = usage?.report {
            WindowRow(title: "5-hour", window: report.session, mode: mode, now: now, delay: Double(index) * 0.06)
            WindowRow(title: "Weekly", window: report.week, mode: mode, now: now, delay: Double(index) * 0.06 + 0.05)
        } else if usage?.needsSignIn == true {
            HStack {
                Label("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("Sign in…", action: onSignIn).font(.caption)
            }
        } else if let problem = usage?.problem {
            Text(problem).font(.caption).foregroundStyle(.orange)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        } else if isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Not checked yet: press Refresh").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A limit window: the bar, the percentage (left or used), and when it resets.
struct WindowRow: View {
    let title: String
    let window: UsageWindow?
    let mode: DisplayMode
    let now: Date
    var delay: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title).font(.caption).frame(width: 46, alignment: .leading)
                UsageBar(fraction: window.map { mode.percent($0) / 100 } ?? 0,
                         level: window.map(UsageLevel.init) ?? .ok, delay: delay)
                percentText
                    .frame(width: 66, alignment: .trailing)
            }
            if let window, let line = UsageFormat.resetLine(window, now: now) {
                Text(line).font(.caption2).foregroundStyle(.secondary).padding(.leading, 54)
            }
        }
    }

    @ViewBuilder private var percentText: some View {
        if let window {
            Text(UsageFormat.percent(window, mode: mode))
                .font(.caption.monospacedDigit())
                .contentTransition(.numericText(value: mode.percent(window)))
                .animation(.snappy, value: mode)
        } else {
            Text("not reported").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Green while more than half is left, yellow down to a fifth, red below that (`UsageLevel`), whichever way the numbers are shown.
extension UsageLevel {
    var color: Color {
        switch self {
        case .ok: return .green
        case .low: return Color(red: 0.96, green: 0.72, blue: 0.10)
        case .critical: return .red
        }
    }
}

/// The bar: fills from empty when it first appears, glides to new values, and a red bar breathes gently so it's noticed.
struct UsageBar: View {
    let fraction: Double
    let level: UsageLevel
    var delay: Double = 0

    @State private var drawn = false
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [level.color.opacity(0.75), level.color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, drawn ? fraction : 0)) * geo.size.width)
                    .shadow(color: level.color.opacity(level == .critical && breathe ? 0.7 : 0), radius: 4)
            }
        }
        .frame(height: 7)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: fraction)
        .animation(.easeInOut(duration: 0.4), value: level)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1 + delay)) { drawn = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// The refresh arrow, turning while a refresh runs.
struct SpinningArrow: View {
    let spinning: Bool
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(angle))
            .onChange(of: spinning, initial: true) { _, isOn in
                if isOn {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { angle = 0 }
                }
            }
    }
}

/// The menu-bar gauge: its needle follows the least left in any window of any account, and the header copy turns that level's colour.
enum GaugeIcon {
    static func name(lowestLeft: Double?) -> String {
        guard let left = lowestLeft else { return "gauge.with.dots.needle.33percent" }
        switch left {
        case 84...: return "gauge.with.dots.needle.100percent"
        case 59..<84: return "gauge.with.dots.needle.67percent"
        case 42..<59: return "gauge.with.dots.needle.50percent"
        case 17..<42: return "gauge.with.dots.needle.33percent"
        default: return "gauge.with.dots.needle.0percent"
        }
    }

    static func tint(lowestLeft: Double?) -> Color {
        lowestLeft.map { UsageLevel(leftPercent: $0).color } ?? .secondary
    }
}
