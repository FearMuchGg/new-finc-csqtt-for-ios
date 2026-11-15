// VPNLiveActivity.swift
//
// The Lock Screen and Dynamic Island presentations (GitHub issue #64, M2).
//
// Two things here are correctness, not decoration:
//
//  1. `context.isStale`. Only the app may refresh a Live Activity, and the app
//     is suspended for most of a tunnel's life — so a state published 20
//     minutes ago may no longer be true. Past the staleDate the system tells us
//     so, and every presentation then stops ASSERTING the state: the dot goes
//     grey, the label reads "Last known", and the session clock is withdrawn
//     because we can no longer vouch for it either. A control surface that
//     confidently reports a tunnel that dropped is worse than one that admits
//     it doesn't know.
//
//  2. The session clock is `Text(_:style:.timer)` over a Date, never a number
//     we push. The system ticks it with the app dead. See
//     VPNActivityAttributes.swift for why no other counter can be here.
//
// Everything is laid out for a name of arbitrary length: server names are user
// input, so every label truncates rather than pushing the timer off-screen.
//
// Three layout rules, each learned the hard way — (a) on device, (b) and (c) on
// the prototype:
//
//  a. The COMPACT island is sized by its content, and it shares the status bar
//     with the clock, signal and battery. A live text there (`style: .timer`)
//     asks for a width unrelated to the string it shows, so it MUST be given an
//     explicit `.frame` — unbounded it took ~82% of the screen and hid the status
//     bar entirely (build 205; fixed in 207). See compactTrailing for the numbers.
//  b. The island's expanded .bottom region has a fixed height and silently CLIPS
//     anything past it — a cancel/paging row stacked under the server list
//     simply vanished, leaving no way out of the picker. Chrome therefore lives
//     in .leading/.trailing, which are separate regions. The rows themselves are
//     compact (~25 pt: 12 pt text, 5 pt padding) in build 498 so that THREE fit
//     completely; at the earlier 9 pt padding the third row crossed the lower
//     edge and its bottom half was cut off.
//  c. An expired picker renders as the NORMAL layout. staleDate is the picker's
//     deadline (see LiveActivityController): the app is asleep and cannot close
//     the menu itself, so this is the only thing that gets the user out without
//     a tap.

import ActivityKit
import SwiftUI
import WidgetKit

/// The compact-leading pill: a tiny brand capsule instead of a bare dot.
///
/// Sized 28 × 22 on purpose — Apple asks compact content to fit a 28 pt circle
/// when the island renders with reduced width (landscape, iPhone Duo, or two
/// simultaneous Live Activities), and a larger capsule would simply be clipped
/// by the region. Colour carries the state: the tunnel's own tint while the data
/// is live, grey once it is stale — a stale activity must not claim a live
/// tunnel (rule (c) in the file header).
private struct IslandBrandPill: View {
    let color: Color
    let stale: Bool
    /// DIRECT routing mark. The bare status dot used to carry it as a small
    /// amber dot next to the tunnel colour; the capsule must keep that signal
    /// (build 502 — it was lost when the dot became a pill).
    let direct: Bool

    var body: some View {
        Image(systemName: stale ? "shield.slash.fill" : "checkmark.shield.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 28, height: 22)
            .background {
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: stale
                            ? [Color.gray.opacity(0.60), Color.gray.opacity(0.32)]
                            : [color.opacity(0.95), color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
            }
            .overlay(alignment: .bottomTrailing) {
                // On the capsule's corner, not beside it: the compact region's
                // width is the system's, and a dot in the layout would either
                // widen the pill or push it into the clip.
                if direct {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5)
                        }
                        .offset(x: 1.5, y: 1.5)
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [stale ? "Tunnel status: last known" : "Tunnel status"]
        if direct { parts.append("Direct routing") }
        return parts.joined(separator: ", ")
    }
}

struct VPNLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VPNActivityAttributes.self) { context in
            Group {
                if picking(context) { lockScreenPicker(context) } else { lockScreen(context) }
            }
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if picking(context), #available(iOS 17.0, *) {
                        Button(intent: ExitPickerIntent()) {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.ultraThinMaterial))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                    Label {
                        // SHORT form only: this region is ~1/3 of the island's
                        // width, and "Last known: Connected" truncated to
                        // "Last kno…" — which said less than nothing. The
                        // staleness wording lives in .bottom, which is full
                        // width; here it shows as the grey glyph and colour.
                        //
                        // Even the short form does not always fit: "Connecting…"
                        // came back as "Connecti..." on an iPhone Air (29.07).
                        // Latent since build 192 — the island had only ever been
                        // looked at while Connected, which does fit — and stage 2
                        // surfaced it by making a long stay in Connecting easy.
                        // Shrink the word rather than cut it; a scaled label is
                        // still a word, a truncated one is a puzzle.
                        Text(shortStatus(context.state.status))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } icon: {
                        // A couple of points to the right: the leading region
                        // clips its left edge, and the dot's outer ring was
                        // being shaved by it.
                        statusDot(context, size: 11)
                            .offset(x: 3)
                    }
                    .foregroundStyle(context.isStale ? .secondary : .primary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if picking(context) {
                        if context.state.pageCount > 1, #available(iOS 17.0, *) {
                            Button(intent: NextPageIntent()) {
                                Text("\(context.state.page + 1)/\(context.state.pageCount) ›")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                                    .overlay(Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        clock(context)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if picking(context) {
                        if #available(iOS 17.0, *) {
                            // Nothing else may go in here — see rule (b) above.
                            // Spacing 3 keeps three ~25 pt rows inside the
                            // region; the rows themselves are compacted in
                            // serverButton.
                            VStack(spacing: 3) {
                                ForEach(context.state.choices) { c in
                                    serverButton(c, busy: context.state.busyServerId == c.id)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Text(context.state.serverName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if context.isStale {
                                    Text("· last known")
                                        .lineLimit(1)
                                        .layoutPriority(1)   // drop the NAME first, not this
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if #available(iOS 17.0, *) {
                                controls(context)
                            }
                        }
                    }
                }
            } compactLeading: {
                // A brand capsule rather than a bare dot — the leading pill from
                // the reference, in this app's own colours. It is 28 × 22, i.e.
                // exactly the 28 pt circle Apple's reduced-width guidance asks
                // compact content to fit into (ActivityKit › Displaying live
                // data › Support presentations with reduced width), so the same
                // view survives landscape, iPhone Duo and a second Live
                // Activity instead of being clipped by the region.
                IslandBrandPill(color: dotColor(context),
                                stale: context.isStale,
                                direct: isDirect(context))
                    .offset(x: -1)
            } compactTrailing: {
                // 🚨 The `.frame` is load-bearing — never drop it. A live text
                // (`style: .timer`, and `Text(timerInterval:)` too) asks for a
                // width that has NOTHING to do with the string on screen, and the
                // compact island sizes itself to its content. Unbounded, the pill
                // grew to ~82% of the screen and swallowed the whole status bar:
                // no clock, no signal, no battery. That is what build 205 shipped.
                //
                // A/B-measured on an iPhone Air simulator, 12 h 35 m session:
                //   unbounded ................ 82% wide, status bar gone
                //   Text(timerInterval:) ..... 92% wide — worse, and no better
                //                              bounded: a 1 h range showing "0:15"
                //                              reserves as much as a 99 h one
                //   frame 44 + scale 0.6 ..... 53% wide, "12:35:18" in full ✅
                //   no clock at all .......... 40% wide
                //
                // 44pt is chosen for the longest string the format really produces
                // ("12:34:56" = 8 glyphs), which is why the prototype's 42pt was
                // wrong twice over: it was picked for "0:12" and truncated a
                // 12-hour session to "12:3…". minimumScaleFactor is the insurance
                // — past 99 h the label shrinks instead of truncating, because a
                // scaled number is still a number (same reasoning as build 203).
                //
                // What it costs is why the clock here is OPT-IN (Settings ›
                // Advanced, default off): iOS sheds status-bar items right-to-left
                // as the island grows, so 53% drops the "LTE"/"5G" label on
                // cellular — this app's normal habitat, where the signal bars,
                // battery and clock all survive — or the cellular dots on Wi-Fi.
                // Off, the pill is 40% wide and the status bar stays intact.
                //
                // `compactClock == true`, not `?? false`: nil means the state was
                // published before the setting existed, which reads as off.
                if context.state.compactClock == true {
                    clock(context)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 44)
                } else if context.isStale {
                    // Staleness still has to be sayable with the clock off: the
                    // greyed shield alone reads as a colour choice, not as "we
                    // stopped being able to vouch for this" (stage 1). One
                    // character, and only while stale.
                    Text("?")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                // One dot, as the main screen uses. It no longer identifies the
                // app by shape — the activity's own header and the Lock Screen
                // card do — but it keeps the colour language consistent. 12 pt:
                // the minimal pill is the one place a dot can afford to read.
                statusDot(context, size: 12, glow: false, ring: false)
            }
            .keylineTint(context.state.direct == true ? .orange : tint(context))
        }
    }

    // MARK: - Controls (iOS 17+)

    /// Is the picker open AND still live? See rule (c) in the file header.
    private func picking(_ context: ActivityViewContext<VPNActivityAttributes>) -> Bool {
        context.state.mode == .picking && !context.isStale
    }

    @available(iOS 17.0, *)
    @ViewBuilder
    private func controls(_ context: ActivityViewContext<VPNActivityAttributes>) -> some View {
        // A floating bottom bar, like the app's own tab bar: a capsule of
        // icon buttons plus one round action, all at the BOTTOM of the card.
        // Rule (b) still holds — the island's bottom region fits three
        // controls, and this is exactly three (power, DIRECT, switch).
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button(intent: DisconnectIntent()) {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 34)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(context.state.status == .disconnecting)

                Button(intent: SetDirectIntent(direct: !isDirect(context))) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 34)
                        .foregroundStyle(isDirect(context) ? Color.orange : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(context.state.status != .connected)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

            Button(intent: EnterPickerIntent()) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// nil means "published before this field existed" and reads as tunnelled —
    /// the safe direction: it never claims the kill switch is off when it may
    /// not be.
    private func isDirect(_ context: ActivityViewContext<VPNActivityAttributes>) -> Bool {
        context.state.direct ?? false
    }

    @available(iOS 17.0, *)
    private func serverButton(_ choice: ServerChoice, busy: Bool) -> some View {
        Button(intent: SelectServerIntent(serverId: choice.id)) {
            HStack(spacing: 6) {
                Circle()
                    .fill(busy ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(choice.name)
                    // 12 pt + 5 pt of padding is ~25 pt per row, so THREE rows
                    // fit the island's expanded .bottom with room to spare
                    // (build 498). At the previous 9 pt padding and .caption the
                    // third row crossed the region's lower edge and its bottom
                    // half was cut — the "половина кнопки не видна" report.
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: busy ? "hourglass" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The picker, Lock Screen edition. Roomier than the island, so the chrome
    /// can sit on the title row instead of borrowing other regions.
    @ViewBuilder
    private func lockScreenPicker(_ context: ActivityViewContext<VPNActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Switch server").font(.subheadline.weight(.semibold))
                Spacer()
                if #available(iOS 17.0, *) {
                    HStack(spacing: 6) {
                        Button(intent: ExitPickerIntent()) {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.ultraThinMaterial))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        if context.state.pageCount > 1 {
                            Button(intent: NextPageIntent()) {
                                Label("More (\(context.state.page + 1)/\(context.state.pageCount))",
                                      systemImage: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                                    .overlay(Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if #available(iOS 17.0, *) {
                ForEach(context.state.choices) { c in
                    serverButton(c, busy: context.state.busyServerId == c.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<VPNActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
            statusDot(context, size: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText(context))
                    .font(.headline)
                    .foregroundStyle(context.isStale ? .secondary : .primary)
                    .lineLimit(1)
                Text(context.state.serverName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            clock(context)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
                // Never let a long uptime squeeze the name below legibility —
                // but bound it, do NOT use .fixedSize().
                //
                // 🚨 `.fixedSize()` here made the whole card fail to render:
                // shield, status and server name appeared, the clock and BOTH
                // buttons did not. Proven by bisection in ~/work/la-widget-harness
                // on 2026-07-30 — removing this one modifier brought them back.
                // Mechanism: a live text asks for a width unrelated to its string
                // (the same property that blew up the compact island), and
                // .fixedSize() promotes that absurd width to a requirement the
                // layout cannot satisfy, so WidgetKit abandons the subtree.
                // Simulator-only so far — the device has always rendered this
                // card — but there is no version of this modifier that is worth
                // that risk.
                // 170pt because the Lock Screen does NOT render this as a clock:
                // `.timer` becomes a PHRASE there ("<1 minute", "12 hours, 35
                // minutes") while the island renders the same view as digits
                // ("2:16"). 20 characters at .title3 is ~175pt, so anything
                // tighter truncates a real session to "12 hours, 35 min…".
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 170, alignment: .trailing)
        }
        if #available(iOS 17.0, *) {
            controls(context)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Pieces

    /// Status indicator: a dot, the same language as the app's main screen.
    /// Grey whenever the content is stale — at that point the colour would be
    /// a claim we can't back. A small orange dot marks DIRECT.
    ///
    /// `glow` and `ring` are OFF in the compact island on purpose: the pill is
    /// measured against the status bar, and a soft shadow there reads as a
    /// smudge over the signal/battery glyphs. The ring is also what made the
    /// dot look clipped in the expanded region — it was drawn outside the
    /// view's frame. `side` now reserves the ring's diameter, so nothing is
    /// cut off when connecting.
    private func statusDot(_ context: ActivityViewContext<VPNActivityAttributes>,
                           size: CGFloat = 12,
                           glow: Bool = true,
                           ring: Bool = true) -> some View {
        let color = dotColor(context)
        let showRing = ring && context.state.status == .connecting && !context.isStale
        let ringSize = size * 1.9
        let side = showRing ? ringSize : size
        return ZStack {
            if showRing {
                Circle()
                    .strokeBorder(color.opacity(0.35), lineWidth: 2)
                    .frame(width: ringSize, height: ringSize)
            }
            Circle()
                .fill(RadialGradient(colors: [color, color.opacity(0.7)],
                                     center: .center,
                                     startRadius: 0,
                                     endRadius: size))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
                .shadow(color: glow ? color.opacity(0.55) : .clear,
                        radius: glow ? size * 0.38 : 0)
                .overlay(alignment: .bottomTrailing) {
                    if context.state.direct == true {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: max(4, size * 0.55), height: max(4, size * 0.55))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                            .offset(x: size * 0.15, y: size * 0.15)
                    }
                }
        }
        .frame(width: side, height: side)
        // A shadow is drawn OUTSIDE the view's bounds, so in the expanded
        // leading region its soft edge was reaching the island's rounded
        // corner. The padding reserves that edge inside the dot's own slot;
        // the compact island skips it (no glow there anyway).
        .padding(glow ? 3 : 0)
    }

    private func dotColor(_ context: ActivityViewContext<VPNActivityAttributes>) -> Color {
        guard !context.isStale else { return .gray }
        switch context.state.status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .disconnected: return .gray
        }
    }

    /// The session clock, or a dash. Withheld while connecting (there is no
    /// session yet) and while stale (we can't vouch for it still running).
    ///
    /// Anywhere this goes it needs a width the layout controls: in the expanded
    /// island and on the Lock Screen the region itself provides one, but in the
    /// compact island it must be given an explicit `.frame` — see the note at
    /// `compactTrailing` for what an unbounded live text does to the island.
    @ViewBuilder
    private func clock(_ context: ActivityViewContext<VPNActivityAttributes>) -> some View {
        if context.isStale {
            // A question mark, not a dash: a dash reads as "no session", and the
            // point is that we no longer know. The compact island says the same
            // thing with its own "?" for the same reason.
            Text("?")
        } else if let since = context.state.connectedSince {
            Text(since, style: .timer)
        } else {
            Text("—")
        }
    }

    /// Plain state, for places too narrow for a qualifier.
    private func shortStatus(_ s: VPNActivityStatus) -> String {
        switch s {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Disconnected"
        }
    }

    /// Full wording — only for the Lock Screen, which has the width for it.
    private func statusText(_ context: ActivityViewContext<VPNActivityAttributes>) -> String {
        let base = shortStatus(context.state.status)
        guard context.isStale else { return base }
        return "Last known: " + base.replacingOccurrences(of: "…", with: "")
    }

    private func tint(_ context: ActivityViewContext<VPNActivityAttributes>) -> Color {
        guard !context.isStale else { return .gray }
        switch context.state.status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .disconnected: return .gray
        }
    }

    private func symbol(_ s: VPNActivityStatus) -> String {
        switch s {
        case .connected: return "lock.shield.fill"
        case .connecting, .disconnecting: return "shield.lefthalf.filled"
        case .disconnected: return "shield.slash"
        }
    }
}
