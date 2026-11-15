//
//  CSQTTTheme.swift
//  CSQTT iOS — cosmetic layer
//
//  Every visual decision this project adds lives in CSQTTiOS/: colours,
//  spacing, corner radii, the "liquid glass" surface, motion and haptics.
//  Nothing here knows about the tunnel, the Go bridge or ServerStore, so the
//  file compiles into the app target alone and cannot affect the extension.
//
//  The glass surface is OURS, not UIKit's: `.glassEffect` (Liquid Glass, iOS
//  26) only exists in a project built with the iOS 26 SDK, and the app's floor
//  is iOS 15. A build with an older Xcode would fail on a call it cannot see,
//  even behind `#available`. So the style is reproduced with
//  `.ultraThinMaterial`, a specular gradient, a hairline border and two
//  shadows — the same recipe at every SDK level, which is also why the CI can
//  build it with whichever Xcode the runner has.
//

import SwiftUI
import UIKit

// MARK: - Tokens

enum CSQTTTheme {
    /// UserDefaults keys. Declared here so the app, the views and the
    /// preferences mirror cannot disagree about a spelling.
    enum Key {
        static let appearance = "csqttAppearance"
        static let glass = "csqttGlassEnabled"
        static let animations = "csqttAnimationsEnabled"
        static let haptics = "csqttHapticsEnabled"
        static let onboardingDone = "csqttOnboardingDone"
    }

    // Brand. A calm teal reads as "secure network" without competing with the
    // status colours, and stays legible on both schemes.
    static let accent = Color(hex: 0x2CB1C4)
    static let accentDeep = Color(hex: 0x0E7C8C)
    static let success = Color(hex: 0x2ECC8F)
    static let warning = Color(hex: 0xF2A33C)
    static let danger = Color(hex: 0xE5484D)
    static let direct = Color(hex: 0xF08A24)

    enum Radius {
        static let card: CGFloat = 20
        static let tile: CGFloat = 14
        static let pill: CGFloat = 14
        static let button: CGFloat = 16
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    /// The accent is intentionally NOT read from Asset Catalog: the project
    /// ships only an AppIcon set, and adding colours there would need a
    /// project-file change for no visual gain.
    static func tint(for status: CSQTTStatusTint) -> Color {
        switch status {
        case .connected: return success
        case .busy: return warning
        case .off: return .gray
        case .direct: return direct
        case .error: return danger
        }
    }
}

enum CSQTTStatusTint {
    case connected, busy, off, direct, error
}

// MARK: - Appearance

enum CSQTTAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "csqtt.appearance.system"
        case .light: return "csqtt.appearance.light"
        case .dark: return "csqtt.appearance.dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Glass

/// The liquid-glass recipe: frosted material, a top-left specular highlight,
/// a hairline gradient border and a soft float shadow.
struct CSQTTGlassSurface: View {
    var corner: CGFloat = CSQTTTheme.Radius.card
    var tint: Color = CSQTTTheme.accent
    var elevated: Bool = true

    @Environment(\.colorScheme) private var scheme

    private var specular: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.14 : 0.55),
                tint.opacity(scheme == .dark ? 0.10 : 0.07),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var border: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.30 : 0.85),
                tint.opacity(scheme == .dark ? 0.28 : 0.22),
                Color.white.opacity(scheme == .dark ? 0.05 : 0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(specular) }
            .overlay {
                // A second, tighter highlight at the very top edge: the
                // "wet" line that makes glass read as glass rather than as a
                // grey card.
                shape
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.45), lineWidth: 0.8)
                    .blur(radius: 0.4)
            }
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.10),
                    radius: elevated ? 18 : 8,
                    x: 0,
                    y: elevated ? 10 : 4)
            .shadow(color: tint.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}

private struct CSQTTGlassModifier: ViewModifier {
    var corner: CGFloat
    var tint: Color
    var elevated: Bool
    var padding: CGFloat

    @AppStorage(CSQTTTheme.Key.glass) private var glassEnabled = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if glassEnabled {
                    CSQTTGlassSurface(corner: corner, tint: tint, elevated: elevated)
                } else {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                }
            }
    }
}

extension View {
    /// Wrap content in the CSQTT glass surface.
    func csqttGlass(corner: CGFloat = CSQTTTheme.Radius.card,
                    tint: Color = CSQTTTheme.accent,
                    elevated: Bool = true,
                    padding: CGFloat = CSQTTTheme.Spacing.m) -> some View {
        modifier(CSQTTGlassModifier(corner: corner, tint: tint, elevated: elevated, padding: padding))
    }
}

// MARK: - Buttons

/// Filled, brand-tinted button with a glass sheen. Used for Connect and for
/// the onboarding's primary action.
struct CSQTTFilledButtonStyle: ButtonStyle {
    var tint: Color = CSQTTTheme.accent
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: CSQTTTheme.Radius.button, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.78)],
                                         startPoint: .top,
                                         endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: CSQTTTheme.Radius.button, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.clear],
                                                 startPoint: .top,
                                                 endPoint: .center))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: CSQTTTheme.Radius.button, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                    }
                    .shadow(color: tint.opacity(configuration.isPressed ? 0.15 : 0.35),
                            radius: configuration.isPressed ? 6 : 14,
                            x: 0,
                            y: configuration.isPressed ? 2 : 8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Secondary, glass-backed button (sheet actions, "skip", toolbar items).
struct CSQTTGhostButtonStyle: ButtonStyle {
    var tint: Color = CSQTTTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Colour helper

extension Color {
    /// `Color(hex: 0x2CB1C4)` — sRGB, opaque. Kept here so no other file has
    /// to repeat the byte-shuffling.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
