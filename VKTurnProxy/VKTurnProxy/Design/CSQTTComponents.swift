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
        // `bool(forKey:)` rather than `object(forKey:) as? Bool`: the latter
        // depends on NSNumber bridging and reads nil for a value a Toggle
        // wrote moments ago, which is exactly how "haptics off" kept buzzing.
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: CSQTTTheme.Key.haptics) != nil else { return true }
        return defaults.bool(forKey: CSQTTTheme.Key.haptics)
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

    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
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
        .csqttCapsuleGlass()
        .overlay {
            Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1)
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner ?? height / 2, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion
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

enum CSQTTTab: Int, CaseIterable, Identifiable, Hashable {
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

/// Press feedback for a tab item: a soft squash and a glassy highlight.
private struct CSQTTTabItemStyle: ButtonStyle {
    var animated: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .animation(animated ? .spring(response: 0.26, dampingFraction: 0.62) : nil,
                       value: configuration.isPressed)
    }
}

/// The floating bar from the reference: a capsule of tabs. It is the app's
/// own control, not a system TabView — the floating shape is the design and
/// UITabBar cannot be reshaped into it.
///
/// Both cosmetic switches are honoured HERE, not only in the modifiers: the
/// bar is the most visible glass surface in the app and the most visible
/// animation, so a switch that changed nothing else looked dead.
struct CSQTTTabBar: View {
    @Binding var selection: CSQTTTab

    /// The band the bar occupies, shadow bleed included. ContentView reserves
    /// this inside the bottom safe area (build 496), so no tab screen carries a
    /// bottom padding of its own — the two that did each guessed a different
    /// number and Settings had none, which is how its last rows ended up under
    /// the glass.
    static let bandHeight: CGFloat = 96

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Neither glass nor motion is a preference any more (build 503): the system
    // owns both, and this bar is the iOS 15-18 fallback only.
    private let glassEnabled = true
    private var motion: Bool { !reduceMotion }

    /// The selected tab's capsule as a LENS rather than a solid chip: the
    /// accent stays, but the fill is translucent at its edges, a specular dot
    /// sits near the top, the rim is brighter than the fill, and a hairline of
    /// black under it gives the drop an underside. The bar's own backdrop
    /// therefore reads as something the drop is sitting ON, not something it is
    /// painted over.
    private var selectedLens: some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(
                colors: [CSQTTTheme.accent.opacity(glassEnabled ? 0.92 : 1),
                         CSQTTTheme.accentDeep.opacity(glassEnabled ? 0.86 : 1)],
                startPoint: .top,
                endPoint: .bottom))
            .overlay {
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(glassEnabled ? 0.46 : 0),
                                 Color.white.opacity(glassEnabled ? 0.08 : 0),
                                 Color.clear],
                        startPoint: .top,
                        endPoint: .center))
            }
            .overlay {
                // The lamp: a small radial highlight where light enters the
                // drop. Kept on one side so the capsule has a direction.
                Capsule(style: .continuous)
                    .fill(RadialGradient(colors: [Color.white.opacity(glassEnabled ? 0.50 : 0),
                                                  Color.clear],
                                         center: UnitPoint(x: 0.5, y: 0.12),
                                         startRadius: 0,
                                         endRadius: 46))
                    .blendMode(.plusLighter)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(glassEnabled ? 0.78 : 0),
                                 Color.white.opacity(glassEnabled ? 0.16 : 0)],
                        startPoint: .top,
                        endPoint: .bottom), lineWidth: 0.9)
            }
            .shadow(color: CSQTTTheme.accent.opacity(glassEnabled ? 0.55 : 0.25),
                    radius: glassEnabled ? 10 : 4, x: 0, y: glassEnabled ? 5 : 3)
            .shadow(color: Color.black.opacity(glassEnabled ? 0.20 : 0),
                    radius: 1.5, x: 0, y: -1)
            .matchedGeometryEffect(id: "selected", in: pill)
    }

    /// The bar's own glass: frosted material, a diagonal tint (white entering
    /// top-left, brand colour gathering bottom-right), a radial "lamp" near the
    /// top edge and a darker lower band for thickness. Clipped to the capsule so
    /// no highlight spills past the rim.
    private var glassBackdrop: some View {
        ZStack {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.22),
                             Color.white.opacity(0.04),
                             CSQTTTheme.accent.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            Capsule(style: .continuous)
                .fill(RadialGradient(colors: [Color.white.opacity(0.24), Color.clear],
                                     center: UnitPoint(x: 0.30, y: 0.02),
                                     startRadius: 0,
                                     endRadius: 120))
                .blendMode(.plusLighter)
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [Color.clear, Color.black.opacity(0.20)],
                                     startPoint: .center,
                                     endPoint: .bottom))
        }
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func tabIcon(_ tab: CSQTTTab) -> some View {
        if #available(iOS 17.0, *), motion {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .semibold))
                .symbolEffect(.bounce, value: selection == tab)
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .semibold))
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CSQTTTab.allCases) { tab in
                Button {
                    CSQTTHaptic.selection()
                    withAnimation(motion ? .spring(response: 0.38, dampingFraction: 0.72) : nil) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        tabIcon(tab)
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
                            selectedLens
                        }
                    }
                }
                .buttonStyle(CSQTTTabItemStyle(animated: motion))
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background {
            if glassEnabled {
                glassBackdrop
            } else {
                Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
            }
        }
        .overlay {
            if glassEnabled {
                // Two concentric strokes read as THICKNESS; one alone reads as
                // a sticker. The outer rim is brightest at the top-left — the
                // side the light comes from — and the inner hairline catches
                // the refraction just inside the edge.
                Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(0.55),
                                 Color.white.opacity(0.14),
                                 Color.white.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing), lineWidth: 1)
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.6)
                    .padding(1.7)
            } else {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .overlay(alignment: .top) {
            if glassEnabled {
                // The wet line along the top edge, faded at both ends: the one
                // detail that turned the flat capsule into a lens.
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Color.clear,
                                                  Color.white.opacity(0.60),
                                                  Color.clear],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(height: 1)
                    .blur(radius: 0.7)
                    .padding(.horizontal, 28)
                    .offset(y: 0.5)
            }
        }
        .shadow(color: Color.black.opacity(glassEnabled ? 0.34 : 0.10),
                radius: glassEnabled ? 26 : 8,
                x: 0, y: glassEnabled ? 14 : 4)
        .shadow(color: CSQTTTheme.accent.opacity(glassEnabled ? 0.16 : 0),
                radius: 12, x: 0, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .animation(motion ? .spring(response: 0.4, dampingFraction: 0.8) : nil, value: selection)
    }
}
