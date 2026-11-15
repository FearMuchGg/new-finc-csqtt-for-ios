//
//  ServerPickerMenu.swift
//  CSQTT iOS
//
//  The server picker on the main screen: a glass capsule naming the active
//  server, opening a menu of every profile — grouped by subscription and by
//  hand — with refresh and management actions.
//
//  Choosing another server while the tunnel is up goes through
//  switchAndReconnect, the same path the Live Activity uses: the session is
//  rebuilt on the new profile instead of the UI silently pointing at a server
//  the running tunnel is not using.
//

import SwiftUI

struct ServerPickerMenu: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared
    @State private var showSubscriptions = false

    init(tunnel: TunnelManager) {
        self.tunnel = tunnel
    }

    var body: some View {
        Menu {
            let manual = store.servers.filter { $0.subscriptionId == nil }
            if !manual.isEmpty {
                Section {
                    ForEach(manual) { server in
                        Button {
                            pick(server.id)
                        } label: {
                            Label(server.serverName,
                                  systemImage: server.id == store.activeServerId
                                      ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } header: {
                    Text("Manual")
                }
            }

            ForEach(subscriptions.subscriptions) { sub in
                let list = store.servers(for: sub.id)
                if !list.isEmpty {
                    Section {
                        ForEach(list) { server in
                            Button {
                                pick(server.id)
                            } label: {
                                Label(server.serverName,
                                      systemImage: server.id == store.activeServerId
                                          ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } header: {
                        Text(sub.name)
                    }
                }
            }

            Section {
                Button {
                    Task { await subscriptions.refreshAll(force: true) }
                } label: {
                    Label(subscriptions.refreshing.isEmpty
                          ? LocalizedStringKey("Refresh subscriptions")
                          : LocalizedStringKey("Refreshing…"),
                          systemImage: "arrow.clockwise")
                }
                .disabled(!subscriptions.refreshing.isEmpty)

                Button {
                    showSubscriptions = true
                } label: {
                    Label("Manage subscriptions…", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.activeServer.serverName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .sheet(isPresented: $showSubscriptions) {
            NavigationView {
                SubscriptionsView()
            }
        }
        .onAppear {
            // A menu opened after a while is the cheapest moment to pick up a
            // server the provider added; throttled inside the store.
            Task { await subscriptions.refreshIfStale() }
        }
    }

    private func pick(_ id: UUID) {
        guard id != store.activeServerId else { return }
        CSQTTHaptic.selection()
        store.activate(id)
        if tunnel.status == .connected {
            Task { await tunnel.switchAndReconnect(to: id, because: .userPickedServer) }
        }
    }
}
