//
//  CSQTTComponents.swift
//  CSQTT iOS — cosmetic layer
//
//  Reusable views that turn the plain rows of the app into the glass styles:
//  a status orb, a stat tile, a server badge, an empty state, a skeleton and
//  an inline error banner. Plus the haptic helpers and two motion modifiers.
//
//  Every type here is additive: the app's existing views keep their names and
//  call sites, and only the ones this project touches switch to these.
//

import SwiftUI
import UIKit

// MARK: - Haptics

enum CSQTTHaptic {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: CSQTTTheme.Key.haptics) as? Bool ?? true
    }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Motion

private struct CSQTTPulseModifier: ViewModifier {
    var active: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CSQTTTheme.Key.animations) private var animations = true

    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && animations && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(0.45), lineWidth: 2)
                        .scaleEffect(pulsing ? 1.8 : 1.0)
                        .opacity(pulsing ? 0.0 : 0.8)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false),
                                   value: pulsing)
                }
            }
            .onAppear { pulsing = true }
            .onChange(of: active) { _ in pulsing = true }
    }
}

private struct CSQTTNumericModifier: ViewModifier {
    // @ViewBuilder is required: the two branches return different types, and a
    // bare `some View` body cannot choose between them.
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}

private struct CSQTTSymbolPulseModifier: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), active, !reduceMotion {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}

extension View {
    /// A halo that breathes while the tunnel is busy (connecting / disconnecting).
    func csqttPulse(active: Bool, color: Color = CSQTTTheme.warning) -> some View {
        modifier(CSQTTPulseModifier(active: active, color: color))
    }

    /// Digits roll instead of jumping when a counter changes.
    func csqttNumeric() -> some View {
        modifier(CSQTTNumericModifier())
    }

    /// SF Symbol pulse for the status glyph (iOS 17+), a no-op below.
    func csqttSymbolPulse(active: Bool) -> some View {
        modifier(CSQTTSymbolPulseModifier(active: active))
    }
}

// MARK: - Status orb

/// The big circle on the main screen: a filled, glowing dot that breathes
/// while the status is transitional.
struct CSQTTStatusOrb: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [color, color.opacity(0.65)],
                               center: .center,
                               startRadius: 1,
                               endRadius: 30)
            )
            .frame(width: 46, height: 46)
            .shadow(color: color.opacity(0.55), radius: pulsing ? 14 : 8)
            .csqttPulse(active: pulsing, color: color)
            .animation(.easeInOut(duration: 0.35), value: color)
            .accessibilityHidden(true)
    }
}

/// Compact pill: dot + label, for sub-headers and cards.
struct CSQTTStatusPill: View {
    let text: String
    let color: Color
    var pulsing: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .csqttPulse(active: pulsing, color: color)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat tile

/// Drop-in replacement for the old `StatBox`: glass, monospaced digits and a
/// numeric transition. The initialiser matches, so call sites don't change.
struct CSQTTStatTile: View {
    let title: String
    let value: String
    let sub: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .csqttNumeric()
            if let sub = sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .csqttNumeric()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .csqttGlass(corner: CSQTTTheme.Radius.tile, padding: 0)
    }
}

// MARK: - Server badge

/// A deterministic monogram for a server row: initials plus a hue derived from
/// the name's scalars. Deterministic on purpose — `hashValue` is seeded per
/// process and would repaint every launch.
struct CSQTTServerBadge: View {
    let name: String
    var size: CGFloat = 34

    private var initials: String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        if letters.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return letters.joined().uppercased()
    }

    private var hue: Double {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360.0
    }

    private var base: Color {
        Color(hue: hue, saturation: 0.55, brightness: 0.78)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [base.opacity(0.95), base.opacity(0.55)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

struct CSQTTEmptyStateView<Extra: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(spacing: CSQTTTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CSQTTTheme.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CSQTTGhostButtonStyle())
            }
            extra()
        }
        .frame(maxWidth: .infinity)
        .csqttGlass(padding: CSQTTTheme.Spacing.l)
    }
}

extension CSQTTEmptyStateView where Extra == EmptyView {
    init(systemImage: String,
         title: LocalizedStringKey,
         message: LocalizedStringKey,
         actionTitle: LocalizedStringKey? = nil,
         action: (() -> Void)? = nil) {
        self.init(systemImage: systemImage,
                  title: title,
                  message: message,
                  actionTitle: actionTitle,
                  action: action,
                  extra: { EmptyView() })
    }
}

// MARK: - Skeleton

/// A shimmering placeholder, for screens that would otherwise show an empty
/// rectangle while a first value is on its way.
struct CSQTTSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var corner: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CSQTTTheme.Key.animations) private var animations = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner ?? height / 2, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !animations)) { context in
            let phase = reduceMotion || !animations
                ? 0.0
                : (context.date.timeIntervalSinceReferenceDate * 0.9).truncatingRemainder(dividingBy: 2.0)
            shape
                .fill(Color.primary.opacity(0.08))
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * (phase - 0.4))
                    }
                    .clipShape(shape)
                }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Error banner

/// Inline, dismissible error. A banner keeps the context visible instead of
/// covering the screen with an alert, and it can carry a retry action.
struct CSQTTErrorBanner: View {
    let text: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: CSQTTTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CSQTTTheme.danger)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("csqtt.common.retry", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CSQTTTheme.accent)
                .buttonStyle(.plain)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("csqtt.common.close")
            }
        }
        .csqttGlass(corner: CSQTTTheme.Radius.tile, tint: CSQTTTheme.danger, padding: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Bottom tab bar

enum CSQTTTab: Int, CaseIterable, Identifiable {
    case home, logs, speed, settings

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "csqtt.tab.home"
        case .logs: return "csqtt.tab.logs"
        case .speed: return "csqtt.tab.speed"
        case .settings: return "csqtt.tab.settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .speed: return "speedometer"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The floating bar from the reference: a capsule of tabs. It is the app's
/// own control, not a system TabView — the floating shape is the design and
/// UITabBar cannot be reshaped into it. No round trailing action: the
/// Connect button lives on the Home tab, where it belongs.
struct CSQTTTabBar: View {
    @Binding var selection: CSQTTTab

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CSQTTTab.allCases) { tab in
                Button {
                    CSQTTHaptic.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                    .background {
                        if selection == tab {
                            Capsule(style: .continuous)
                                .fill(CSQTTTheme.accent)
                                .matchedGeometryEffect(id: "selected", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
