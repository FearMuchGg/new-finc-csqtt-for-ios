//
//  CSQTTOnboarding.swift
//  CSQTT iOS — cosmetic layer
//
//  A three-page welcome shown once, on first launch. It explains what the app
//  is for, what it needs (a server) and where the controls live. Kept in
//  CSQTTiOS/ so the app's own sources stay free of presentation-only code.
//
//  The screen is deliberately short: one idea per page, a skip on every page
//  and no form fields — the server is configured in Settings, not here.
//

import SwiftUI

struct CSQTTOnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 3

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                HStack {
                    Text("CSQTT")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if page < pageCount - 1 {
                        Button("csqtt.onboarding.skip") {
                            finish()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CSQTTTheme.Spacing.l)
                .padding(.top, CSQTTTheme.Spacing.m)

                TabView(selection: $page) {
                    welcome.tag(0)
                    features.tag(1)
                    ready.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: page)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x06181D), Color(hex: 0x0B2A33), Color(hex: 0x041014)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(CSQTTTheme.accent.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -120, y: -220)
            Circle()
                .fill(CSQTTTheme.accentDeep.opacity(0.45))
                .frame(width: 240, height: 240)
                .blur(radius: 80)
                .offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: CSQTTTheme.Spacing.l) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .csqttSymbolPulse(active: true)
            }
            VStack(spacing: CSQTTTheme.Spacing.s) {
                Text("csqtt.onboarding.welcome.title")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("csqtt.onboarding.welcome.body")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, CSQTTTheme.Spacing.l)
            }
            Spacer(minLength: 0)
        }
        .padding(CSQTTTheme.Spacing.l)
    }

    private var features: some View {
        VStack(spacing: CSQTTTheme.Spacing.m) {
            Spacer(minLength: 0)
            Text("csqtt.onboarding.features.title")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, CSQTTTheme.Spacing.xs)

            featureRow(icon: "bolt.horizontal.circle.fill",
                       title: "csqtt.onboarding.feature.speed.title",
                       body: "csqtt.onboarding.feature.speed.body")
            featureRow(icon: "lock.circle.fill",
                       title: "csqtt.onboarding.feature.privacy.title",
                       body: "csqtt.onboarding.feature.privacy.body")
            featureRow(icon: "switch.3.circle.fill",
                       title: "csqtt.onboarding.feature.control.title",
                       body: "csqtt.onboarding.feature.control.body")
            Spacer(minLength: 0)
        }
        .padding(CSQTTTheme.Spacing.l)
    }

    private var ready: some View {
        VStack(spacing: CSQTTTheme.Spacing.l) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(CSQTTTheme.success)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: CSQTTTheme.Spacing.s) {
                Text("csqtt.onboarding.ready.title")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("csqtt.onboarding.ready.body")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CSQTTTheme.Spacing.m)
            }
            Spacer(minLength: 0)
        }
        .padding(CSQTTTheme.Spacing.l)
    }

    private func featureRow(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: CSQTTTheme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CSQTTTheme.accent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .csqttGlass(corner: CSQTTTheme.Radius.tile, tint: CSQTTTheme.accent, padding: 14)
    }

    // MARK: - Footer

    /// The primary button's label as a key, not a `String`: a ternary of string
    /// literals would infer `String`, and `Text(String)` interpolates instead of
    /// looking the key up in the catalog.
    private var primaryTitle: LocalizedStringKey {
        page < pageCount - 1 ? "csqtt.onboarding.next" : "csqtt.onboarding.start"
    }

    private var footer: some View {
        VStack(spacing: CSQTTTheme.Spacing.m) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? CSQTTTheme.accent : Color.white.opacity(0.22))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: page)
                }
            }

            Button {
                if page < pageCount - 1 {
                    CSQTTHaptic.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                        page += 1
                    }
                } else {
                    finish()
                }
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(CSQTTFilledButtonStyle())
            .padding(.horizontal, CSQTTTheme.Spacing.l)
        }
        .padding(.bottom, CSQTTTheme.Spacing.l)
    }

    private func finish() {
        CSQTTHaptic.success()
        onDone()
    }
}
